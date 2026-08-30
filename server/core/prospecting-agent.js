import { getAdminDb, requireRole } from './db.js';

const TASK_TYPES = new Set(['analyze','draft_outreach','send_outreach','follow_up','negotiate','handoff','start_service','review_service']);

export async function handleProspectingApi({ path, method, body, user }) {
  requireRole(user);
  const db = getAdminDb();

  if (path === '/api/prospecting/search' && method === 'POST') {
    const query = typeof body?.query === 'string' ? body.query.trim() : '';
    if (!query) return { status: 400, body: { error: 'query is required' } };
    const { data, error } = await db.from('prospecting_searches').insert({
      created_by: user.id,
      query,
      target_city: body.target_city || null,
      target_industry: body.target_industry || null,
      status: 'pending',
      metadata: body.metadata && typeof body.metadata === 'object' ? body.metadata : {}
    }).select().single();
    if (error) return { status: 500, body: { error: 'Could not create prospecting search' } };
    return { status: 201, body: { search: data, provider_status: 'discovery_provider_required' } };
  }

  if (path === '/api/prospecting/candidates' && method === 'POST') {
    const searchId = body?.search_id;
    if (!searchId || !Array.isArray(body?.candidates)) return { status: 400, body: { error: 'search_id and candidates[] are required' } };
    const rows = body.candidates.filter(c => c?.company_name).map(c => ({
      search_id: searchId,
      company_name: String(c.company_name).trim(),
      website_url: c.website_url || null,
      contact_phone: c.contact_phone || null,
      source: c.source || null,
      source_url: c.source_url || null,
      score: Number.isFinite(Number(c.score)) ? Number(c.score) : null,
      analysis: c.analysis && typeof c.analysis === 'object' ? c.analysis : {},
      status: c.analysis ? 'analyzed' : 'new'
    }));
    if (!rows.length) return { status: 400, body: { error: 'At least one valid candidate is required' } };
    const { data, error } = await db.from('prospect_candidates').insert(rows).select();
    if (error) return { status: 500, body: { error: 'Could not save prospect candidates' } };
    await db.from('prospecting_searches').update({ status: 'completed', completed_at: new Date().toISOString() }).eq('id', searchId).eq('created_by', user.id);
    return { status: 201, body: { candidates: data } };
  }

  if (path === '/api/prospecting/task' && method === 'POST') {
    const leadId = body?.lead_id;
    const taskType = body?.task_type;
    if (!leadId || !TASK_TYPES.has(taskType)) return { status: 400, body: { error: 'lead_id and a valid task_type are required' } };
    const waiting = Boolean(body.requires_human);
    const { data, error } = await db.from('sales_agent_tasks').insert({
      lead_id: leadId,
      task_type: taskType,
      status: waiting ? 'waiting_approval' : 'pending',
      requires_human: waiting,
      payload: body.payload && typeof body.payload === 'object' ? body.payload : {}
    }).select().single();
    if (error) return { status: 500, body: { error: 'Could not create sales agent task' } };
    return { status: 201, body: { task: data } };
  }

  if (path === '/api/prospecting/tasks' && method === 'GET') {
    const { data, error } = await db.from('sales_agent_tasks').select('id,lead_id,task_type,status,requires_human,payload,result,scheduled_at,completed_at,created_at').order('created_at', { ascending: false }).limit(100);
    if (error) return { status: 500, body: { error: 'Could not load sales agent tasks' } };
    return { status: 200, body: { tasks: data || [] } };
  }

  return null;
}
