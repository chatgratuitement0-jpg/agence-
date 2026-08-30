import crypto from 'node:crypto';
import { getAdminDb } from './db.js';
import { createProviders } from '../providers/index.js';

const providers = createProviders();
const PREVIEW_TTL_HOURS = 72;
function hashToken(token){ return crypto.createHash('sha256').update(token).digest('hex'); }
function previewBaseUrl(){ return String(process.env.PREVIEW_BASE_URL || process.env.PUBLIC_BASE_URL || '').replace(/\/$/,''); }

async function getProjectForClient(db, projectId, token) {
  if (!token) throw new Error('Preview token required');
  const { data: project, error } = await db.from('website_projects')
    .select('id,lead_id,company_id,deal_id,status,preview_token_hash,preview_expires_at,client_approved_at,rendered_html,preview_view_count')
    .eq('id', projectId).single();
  if (error || !project) throw new Error('Preview not found');
  if (!project.preview_token_hash || hashToken(token) !== project.preview_token_hash) throw new Error('Invalid preview token');
  if (!project.preview_expires_at || new Date(project.preview_expires_at).getTime() < Date.now()) throw new Error('Preview expired');
  return project;
}

export async function generateWebsitePreview({ projectId, userId }) {
  const db = getAdminDb();
  const { data: project, error } = await db.from('website_projects').select('*,companies(id,name,industry,city,website,email,phone),leads(id,name,owner_id,recommended_service,notes)').eq('id', projectId).single();
  if (error || !project) throw new Error('Website project not found');
  if (project.leads?.owner_id && project.leads.owner_id !== userId) throw new Error('Not authorized');

  const context = { project: { id: project.id, status: project.status, business_data: project.business_data, project_data: project.project_data }, company: project.companies || null, lead: project.leads || null };
  await db.from('website_projects').update({ status: 'generating' }).eq('id', project.id);
  let generated;
  try { generated = await providers.ai.generateWebsite(context); }
  catch (e) { await db.from('website_projects').update({ status: 'generation_failed', notes: e.message }).eq('id', project.id); throw e; }

  const token = crypto.randomBytes(32).toString('hex');
  const expiresAt = new Date(Date.now() + PREVIEW_TTL_HOURS * 60 * 60 * 1000).toISOString();
  const base = previewBaseUrl();
  const previewUrl = base ? `${base}/preview/${project.id}?token=${token}` : `/preview/${project.id}?token=${token}`;
  const { data: updated, error: updateError } = await db.from('website_projects').update({ status: 'preview_ready', rendered_html: generated.text, preview_url: previewUrl, preview_token_hash: hashToken(token), preview_expires_at: expiresAt, last_generation_at: new Date().toISOString(), delivery_status: 'preview_ready', notes: 'Preview generated. Final package remains gated by client approval and first payment.' }).eq('id', project.id).select().single();
  if (updateError) throw new Error(updateError.message);
  return { project: updated, preview_url: previewUrl, expires_at: expiresAt, usage: generated.usage || {} };
}

export async function getWebsitePreview({ projectId, token }) {
  const db = getAdminDb();
  const project = await getProjectForClient(db, projectId, token);
  await db.from('website_preview_views').insert({ website_project_id: project.id, user_agent: null, source: 'client_preview' });
  await db.from('website_projects').update({ preview_view_count: Number(project.preview_view_count || 0) + 1, last_preview_viewed_at: new Date().toISOString() }).eq('id', project.id);
  return project.rendered_html || '';
}

export async function reviewWebsitePreview({ projectId, token, decision, message }) {
  const db = getAdminDb();
  const project = await getProjectForClient(db, projectId, token);
  if (!['approved', 'changes_requested'].includes(decision)) throw new Error('Invalid review decision');
  if (decision === 'approved') {
    const { data, error } = await db.from('website_projects').update({ status: 'approved_final', client_approved_at: new Date().toISOString(), delivery_status: 'awaiting_first_payment', delivery_notes: 'Client approved preview. Final package is gated by first payment.' }).eq('id', project.id).select('id,status,client_approved_at,delivery_status').single();
    if (error) throw new Error(error.message);
    return { decision, project: data, next_step: 'first_payment' };
  }

  if (!message?.trim()) throw new Error('A change request message is required');
  const { error: revisionError } = await db.from('website_revision_requests').insert({ website_project_id: project.id, lead_id: project.lead_id, company_id: project.company_id, message: message.trim().slice(0, 5000), requested_by: 'client', status: 'requested', context: { source: 'client_preview' } });
  if (revisionError) throw new Error(revisionError.message);
  const { data, error } = await db.from('website_projects').update({ status: 'revision_requested', delivery_status: 'not_ready', delivery_notes: 'Client requested changes to the preview.' }).eq('id', project.id).select('id,status,delivery_status').single();
  if (error) throw new Error(error.message);
  return { decision, project: data, next_step: 'revision' };
}
