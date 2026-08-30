import crypto from 'node:crypto';
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
function u16(n) { const b = Buffer.alloc(2); b.writeUInt16LE(n, 0); return b; }
function u32(n) { const b = Buffer.alloc(4); b.writeUInt32LE(n >>> 0, 0); return b; }
function makeZip(files) {
  const local = [], central = [];
  let offset = 0;
  for (const file of files) {
    const name = Buffer.from(file.name, 'utf8');
    const data = Buffer.from(file.content, 'utf8');
    const crc = crc32(data);
    const header = Buffer.concat([Buffer.from('PK\x03\x04', 'binary'), u16(20), u16(0), u16(0), u16(0), u16(0), u32(crc), u32(data.length), u32(data.length), u16(name.length), u16(0), name]);
    local.push(header, data);
    central.push(Buffer.concat([Buffer.from('PK\x01\x02', 'binary'), u16(20), u16(20), u16(0), u16(0), u16(0), u16(0), u32(crc), u32(data.length), u32(data.length), u16(name.length), u16(0), u16(0), u16(0), u16(0), u32(0), u32(offset), name]));
    offset += header.length + data.length;
  }
  const centralSize = central.reduce((n, b) => n + b.length, 0);
  return Buffer.concat([...local, ...central, Buffer.from('PK\x05\x06', 'binary'), Buffer.alloc(2), Buffer.alloc(2), u16(files.length), u16(files.length), u32(centralSize), u32(offset), u16(0)]);
}

async function assertOwner(db, projectId, userId) {
  const { data, error } = await db.from('website_projects').select('id,lead_id,company_id,deal_id,status,rendered_html,client_approved_at,first_payment_at,package_generated_at,delivered_at,delivery_status,package_path,final_zip_generated_at,final_zip_size,final_zip_sha256').eq('id', projectId).single();
  if (error || !data) throw new Error('Website project not found');
  if (data.lead_id) {
    const { data: lead } = await db.from('leads').select('owner_id').eq('id', data.lead_id).single();
    if (!lead || lead.owner_id !== userId) throw new Error('Not authorized');
  }
  return data;
}

export async function approveWebsitePreview({ projectId, userId }) {
  const db = getAdminDb();
  const project = await assertOwner(db, projectId, userId);
  if (!project.rendered_html) throw new Error('Preview is not ready');
  const now = new Date().toISOString();
  const { data, error } = await db.from('website_projects').update({ client_approved_at: now, status: project.first_payment_at ? 'approved' : 'awaiting_first_payment', delivery_status: project.first_payment_at ? 'ready_for_package' : 'awaiting_first_payment', notes: project.first_payment_at ? 'Client approved preview. Final package can be generated.' : 'Client approved preview. Waiting for first payment.' }).eq('id', projectId).select().single();
  if (error) throw new Error(error.message);
  return data;
}

export async function registerFirstPayment({ projectId, paymentId, userId }) {
  const db = getAdminDb();
  const project = await assertOwner(db, projectId, userId);
  if (!project.client_approved_at) throw new Error('Client approval is required before first payment is registered');
  const { data: payment, error: paymentError } = await db.from('payments').select('id,status,paid_at,milestone_type,website_project_id,deal_id').eq('id', paymentId).single();
  if (paymentError || !payment) throw new Error('Payment not found');
  if (payment.website_project_id && payment.website_project_id !== projectId) throw new Error('Payment does not belong to this project');
  if (payment.status !== 'paid') throw new Error('Payment is not marked as paid');
  const paidAt = payment.paid_at || new Date().toISOString();
  const { data, error } = await db.from('website_projects').update({ first_payment_at: paidAt, status: 'approved', delivery_status: 'ready_for_package', notes: 'First payment verified. Final package is now unlocked.' }).eq('id', projectId).select().single();
  if (error) throw new Error(error.message);
  return data;
}

export async function generateFinalWebsitePackage({ projectId, userId }) {
  const db = getAdminDb();
  const project = await assertOwner(db, projectId, userId);
  if (!project.client_approved_at) throw new Error('Client approval required');
  if (!project.first_payment_at) throw new Error('First payment required before final package generation');
  if (!project.rendered_html) throw new Error('Website preview has not been generated');

  if (project.package_path && project.package_generated_at) {
    const delivery = await createDeliverySignedUrl({ path: project.package_path });
    return {
      project,
      filename: project.package_path.split('/').pop(),
      sha256: project.final_zip_sha256,
      size: project.final_zip_size,
      delivery,
      reused: true
    };
  }

  const zip = makeZip([
    { name: 'index.html', content: project.rendered_html },
    { name: 'README.txt', content: 'Website package generated by the AI Agency CRM. The client preview was approved and the first payment was verified.' }
  ]);
  const sha256 = crypto.createHash('sha256').update(zip).digest('hex');
  const filename = `website-${projectId}.zip`;
  const storage = await uploadDeliveryPackage({ projectId, zipBuffer: zip, fileName: filename });
  const now = new Date().toISOString();

  const { data, error } = await db.from('website_projects').update({ package_generated_at: now, final_zip_generated_at: now, final_zip_size: zip.length, final_zip_sha256: sha256, package_path: storage.path, delivery_status: 'package_ready', status: 'approved', notes: 'Final package generated, uploaded to private storage, and ready for signed delivery.' }).eq('id', projectId).select().single();
  if (error) throw new Error(error.message);

  return { project: data, filename, sha256, size: zip.length, delivery: storage, reused: false };
}

export async function downloadFinalWebsitePackage({ projectId, userId }) {
  const db = getAdminDb();
  const project = await assertOwner(db, projectId, userId);
  if (!project.client_approved_at) throw new Error('Client approval required');
  if (!project.first_payment_at) throw new Error('First payment required before package download');
  if (!project.package_path) throw new Error('Final package has not been generated');

  const delivery = await createDeliverySignedUrl({ path: project.package_path });
  return {
    projectId,
    filename: project.package_path.split('/').pop(),
    sha256: project.final_zip_sha256,
    size: project.final_zip_size,
    delivery
  };
}
