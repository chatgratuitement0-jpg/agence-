import crypto from 'node:crypto';
import QRCode from 'qrcode';
import { getAdminDb } from './db.js';
import { uploadDeliveryPackage, createDeliverySignedUrl } from './storage-delivery.js';

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function u16(n) { const b = Buffer.alloc(2); b.writeUInt16LE(n); return b; }
function u32(n) { const b = Buffer.alloc(4); b.writeUInt32LE(n >>> 0); return b; }
function makeZip(files) {
  const local = [], central = [];
  let offset = 0;
  for (const file of files) {
    const name = Buffer.from(file.name, 'utf8');
    const data = Buffer.from(file.content, 'utf8');
    const crc = crc32(data);
    const header = Buffer.concat([
      Buffer.from('PK\x03\x04', 'binary'), u16(20), u16(0), u16(0), u16(0), u16(0),
      u32(crc), u32(data.length), u32(data.length), u16(name.length), u16(0), name
    ]);
    local.push(header, data);
    central.push(Buffer.concat([
      Buffer.from('PK\x01\x02', 'binary'), u16(20), u16(20), u16(0), u16(0), u16(0), u16(0),
      u32(crc), u32(data.length), u32(data.length), u16(name.length), u16(0), u16(0), u16(0),
      u16(0), u32(0), u32(offset), name
    ]));
    offset += header.length + data.length;
  }
  const centralSize = central.reduce((n, b) => n + b.length, 0);
  return Buffer.concat([...local, ...central, Buffer.from('PK\x05\x06', 'binary'), Buffer.alloc(2), Buffer.alloc(2), u16(files.length), u16(files.length), u32(centralSize), u32(offset), u16(0)]);
}

async function getQrProject(db, projectId, userId, userRole = 'sales') {
  const { data, error } = await db.from('qr_projects').select('*').eq('id', projectId).single();
  if (error || !data) throw new Error('QR project not found');
  if (userRole === 'admin' || userRole === 'manager') return data;
  let ownerId = null;
  if (data.lead_id) {
    const { data: lead } = await db.from('leads').select('owner_id').eq('id', data.lead_id).single();
    ownerId = lead?.owner_id || null;
  }
  if (!ownerId && data.deal_id) {
    const { data: deal } = await db.from('deals').select('lead_id').eq('id', data.deal_id).single();
    if (deal?.lead_id) {
      const { data: lead } = await db.from('leads').select('owner_id').eq('id', deal.lead_id).single();
      ownerId = lead?.owner_id || null;
    }
  }
  if (!ownerId || ownerId !== userId) throw new Error('Not authorized');
  return data;
}

export async function createQrProject({ leadId, companyId, serviceId, dealId, templateId, destinationUrl, projectName, userId, userRole = 'sales' }) {
  const db = getAdminDb();
  if (!destinationUrl || !/^https?:\/\//i.test(destinationUrl)) throw new Error('A valid http(s) destination URL is required');
  if (userRole !== 'admin' && userRole !== 'manager') {
    const { data: lead } = await db.from('leads').select('owner_id').eq('id', leadId).single();
    if (!lead || lead.owner_id !== userId) throw new Error('Not authorized');
  }
  const token = crypto.randomBytes(32).toString('hex');
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
  const { data, error } = await db.from('qr_projects').insert({
    lead_id: leadId || null,
    company_id: companyId,
    service_id: serviceId || null,
    deal_id: dealId || null,
    template_id: templateId || null,
    project_name: projectName || 'QR Code Project',
    destination_url: destinationUrl,
    preview_token_hash: tokenHash,
    preview_expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    status: 'pending',
    notes: 'QR project created. Generation and final package require approval and first payment.'
  }).select().single();
  if (error) throw new Error(`Could not create QR project: ${error.message}`);
  return { project: data, preview_token: token };
}

export async function generateQrPreview({ projectId, userId, userRole = 'sales' }) {
  const db = getAdminDb();
  const project = await getQrProject(db, projectId, userId, userRole);
  if (!project.destination_url) throw new Error('QR destination URL is required');
  const svg = await QRCode.toString(project.destination_url, { type: 'svg', errorCorrectionLevel: 'H', margin: 2, width: 1024 });
  const checksum = crypto.createHash('sha256').update(svg).digest('hex');
  const { data, error } = await db.from('qr_projects').update({ rendered_svg: svg, svg_checksum: checksum, generated_at: new Date().toISOString(), status: 'review' }).eq('id', projectId).select().single();
  if (error) throw new Error(`Could not save QR preview: ${error.message}`);
  return { project: data, svg, checksum };
}

export async function clientReviewQr({ token, action, message = null }) {
  const db = getAdminDb();
  const hash = crypto.createHash('sha256').update(String(token || '')).digest('hex');
  const { data: project, error } = await db.from('qr_projects').select('*').eq('preview_token_hash', hash).gt('preview_expires_at', new Date().toISOString()).single();
  if (error || !project) throw new Error('QR preview is unavailable or expired');
  if (action === 'approve') {
    const { data, error: updateError } = await db.from('qr_projects').update({ client_approved_at: project.client_approved_at || new Date().toISOString(), status: 'approved_final', notes: 'Client approved QR preview. Waiting for first payment before final package delivery.' }).eq('id', project.id).select().single();
    if (updateError) throw new Error(updateError.message);
    return data;
  }
  if (action === 'request_revision') {
    if (!String(message || '').trim()) throw new Error('A revision message is required');
    const { data, error: updateError } = await db.from('qr_projects').update({ status: 'review', notes: `Client revision requested: ${String(message).trim().slice(0, 5000)}` }).eq('id', project.id).select().single();
    if (updateError) throw new Error(updateError.message);
    return data;
  }
  throw new Error('Unsupported QR review action');
}

export async function registerQrFirstPayment({ projectId, paymentId, userId, userRole = 'sales' }) {
  const db = getAdminDb();
  const project = await getQrProject(db, projectId, userId, userRole);
  if (!project.client_approved_at) throw new Error('Client approval is required before first payment is registered');
  const { data: payment, error } = await db.from('payments').select('id,status,paid_at,milestone_type,qr_project_id,deal_id').eq('id', paymentId).single();
  if (error || !payment) throw new Error('Payment not found');
  if (payment.qr_project_id && payment.qr_project_id !== projectId) throw new Error('Payment does not belong to this QR project');
  if (payment.status !== 'paid') throw new Error('Payment is not marked as paid');
  const { data, error: updateError } = await db.from('qr_projects').update({ first_payment_at: payment.paid_at || new Date().toISOString(), status: 'approved_final', notes: 'First payment verified. Final QR package is unlocked.' }).eq('id', projectId).select().single();
  if (updateError) throw new Error(updateError.message);
  return data;
}

export async function generateFinalQrPackage({ projectId, userId, userRole = 'sales' }) {
  const db = getAdminDb();
  const project = await getQrProject(db, projectId, userId, userRole);
  if (!project.client_approved_at) throw new Error('Client approval required');
  if (!project.first_payment_at) throw new Error('First payment required before final package generation');
  if (!project.destination_url) throw new Error('QR destination URL is required');
  if (project.package_path && project.package_generated_at) {
    return { project, filename: project.package_path.split('/').pop(), size: project.package_size, sha256: project.package_sha256, delivery: await createDeliverySignedUrl({ path: project.package_path }), reused: true };
  }
  const svg = project.rendered_svg || await QRCode.toString(project.destination_url, { type: 'svg', errorCorrectionLevel: 'H', margin: 2, width: 1024 });
  const files = [
    { name: 'qr.svg', content: svg },
    { name: 'destination.txt', content: `${project.destination_url}\n` },
    { name: 'README.txt', content: 'QR package generated by the AI Agency CRM. Client approval and first payment were verified.\n' }
  ];
  const zip = makeZip(files);
  const sha256 = crypto.createHash('sha256').update(zip).digest('hex');
  const filename = `qr-${projectId}.zip`;
  const storage = await uploadDeliveryPackage({ projectId, zipBuffer: zip, fileName: filename });
  const now = new Date().toISOString();
  const { data, error } = await db.from('qr_projects').update({ package_path: storage.path, package_size: zip.length, package_sha256: sha256, package_generated_at: now, asset_path: storage.path, status: 'packaged', notes: 'Final QR package generated and uploaded to private storage.' }).eq('id', projectId).select().single();
  if (error) throw new Error(`Could not save QR package metadata: ${error.message}`);
  return { project: data, filename, size: zip.length, sha256, delivery: storage, reused: false };
}

export async function downloadFinalQrPackage({ projectId, userId, userRole = 'sales' }) {
  const db = getAdminDb();
  const project = await getQrProject(db, projectId, userId, userRole);
  if (!project.client_approved_at) throw new Error('Client approval required');
  if (!project.first_payment_at) throw new Error('First payment required before package download');
  if (!project.package_path) throw new Error('Final QR package has not been generated');
  return { projectId, filename: project.package_path.split('/').pop(), size: project.package_size, sha256: project.package_sha256, delivery: await createDeliverySignedUrl({ path: project.package_path }) };
}
