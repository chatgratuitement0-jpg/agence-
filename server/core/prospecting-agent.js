import { getAdminDb, requireRole } from './db.js';
import { runDiscoverySearch } from './discovery-agent.js';
import { startApprovedService } from './service-delivery.js';

const TASK_TYPES = new Set(['analyze','draft_outreach','send_outreach','follow_up','negotiate','handoff','start_service','review_service']);
const APPROVABLE = new Set(['send_outreach','start_service','review_service']);
const MANAGER_ROLES = new Set(['admin', 'manager']);

async function assertSearchOwner(db, searchId, userId) {
  const { data, error } = await db.from('prospecting_searches').select('id,created_by').eq('id', searchId).eq('created_by', userId).single();
  if (error || !data) {
    const e = new Error('Prospecting search not found');
    e.status = 404;
    throw e;
  }
  return data;
}

async function assertLeadAccess(db, leadId, user) {
  const { data: lead, error } = await db.from('leads').select('id,owner_id').eq('id', leadId).single();
  if (error || !lead) {
    const e = new Error('Lead not found');
    e.status = 404;
    throw e;
  }
  if (!MANAGER_ROLES.has(user.role) && lead.owner_id !== user.id) {
    const e = new Error('Not authorized');
    e.status = 403;
    throw e;
  }
  return lead;
}

async function assertTaskAccess(db, taskId, user) {
  const { data: task, error } = await db.from('sales_agent_tasks').select('*').eq('id', taskId).single();
  if (error || !task) return null;
  await assertLeadAccess(db, task.lead_id, user);
  return task;
}

export async function handleProspectingApi({ path, method, body, user }) {
  requireRole(user);
  const db = getAdminDb();

  if (path === '/api/prospecting/search' && method === 'POST') {
    const query = typeof body?.query === 'string' ? body.query.trim() : '';
    if (!query) return { status: 400, body: { error: 'query is required' } };
    const { data, error } = await db.from('prospecting_searches').insert({ created_by: user.id, query, target_city: body.target_city || null, target_industry: body.target_industry || null, status: 'pending', metadata: body.metadata && typeof body.metadata === 'object' ? body.metadata : {} }).select().single();
    if (error) return { status: 500, body: { error: 'Could not create prospecting search' } };

    try {
      const discovery = await runDiscoverySearch({ searchId: data.id, userId: user.id });
      return { status: 201, body: { search: { ...data, status: 'completed' }, discovery } };
    } catch (discoveryError) {
      return { status: 202, body: { search: data, discovery: { status: 'failed', error: discoveryError.message } } };
    }
  }

  if (path === '/api/prospecting/candidates' && method === 'POST') {
    const searchId = body?.search_id;
    if (!searchId || !Array.isArray(body?.candidates)) return { status: 400, body: { error: 'search_id and candidates[] are required' } };
    try {
      await assertSearchOwner(db, searchId, user.id);
    } catch (e) {
      return { status: e.status || 403, body: { error: e.message } };
    }
    const rows = body.candidates.filter(c => c?.company_name).map(c => ({ search_id: searchId, company_name: String(c.company_name).trim(), website_url: c.website_url || null, contact_phone: c.contact_phone || null, source: c.source || null, source_url: c.source_url || null, score: Number.isFinite(Number(c.score)) ? Number(c.score) : null, analysis: c.analysis && typeof c.analysis === 'object' ? c.analysis : {}, status: c.analysis ? 'analyzed' : 'new' }));
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
    try {
      await assertLeadAccess(db, leadId, user);
    } catch (e) {
      return { status: e.status || 403, body: { error: e.message } };
    }
    const waiting = Boolean(body.requires_human) || APPROVABLE.has(taskType);
    const { data, error } = await db.from('sales_agent_tasks').insert({ lead_id: leadId, task_type: taskType, status: waiting ? 'waiting_approval' : 'pending', requires_human: waiting, payload: body.payload && typeof body.payload === 'object' ? body.payload : {} }).select().single();
    if (error) return { status: 500, body: { error: 'Could not create sales agent task' } };
    return { status: 201, body: { task: data } };
  }

  if (path === '/api/prospecting/tasks' && method === 'GET') {
    let query = db.from('sales_agent_tasks').select('id,lead_id,task_type,status,requires_human,payload,result,scheduled_at,completed_at,created_at').order('created_at', { ascending: false }).limit(100);
    if (!MANAGER_ROLES.has(user.role)) {
      const { data: ownedLeads, error: leadError } = await db.from('leads').select('id').eq('owner_id', user.id);
      if (leadError) return { status: 500, body: { error: 'Could not load owned leads' } };
      const leadIds = (ownedLeads || []).map(row => row.id);
      if (!leadIds.length) return { status: 200, body: { tasks: [] } };
      query = query.in('lead_id', leadIds);
    }
    const { data, error } = await query;
    if (error) return { status: 500, body: { error: 'Could not load sales agent tasks' } };
    return { status: 200, body: { tasks: data || [] } };
  }

  const approvalMatch = path.match(/^\/api\/prospecting\/task\/([^/]+)\/(approve|reject)$/);
  if (approvalMatch && method === 'POST') {
    const taskId = approvalMatch[1];
    const action = approvalMatch[2];
    let task;
    try {
      task = await assertTaskAccess(db, taskId, user);
    } catch (e) {
      return { status: e.status || 403, body: { error: e.message } };
    }
    if (!task) return { status: 404, body: { error: 'Task not found' } };
    if (!task.requires_human || task.status !== 'waiting_approval') return { status: 409, body: { error: 'Task is not awaiting approval' } };

    if (action === 'reject') {
      const { data: updated, error: updateError } = await db.from('sales_agent_tasks').update({ status: 'cancelled', result: { ...task.result, decision: 'rejected', rejected_by: user.id, rejected_at: new Date().toISOString() }, completed_at: new Date().toISOString() }).eq('id', taskId).select().single();
      if (updateError) return { status: 500, body: { error: 'Could not reject task' } };
      return { status: 200, body: { task: updated, action: 'rejected' } };
    }

    if (task.task_type === 'start_service') {
      try {
        const delivery = await startApprovedService({ taskId, userId: user.id });
        const { data: updated } = await db.from('sales_agent_tasks').select('*').eq('id', taskId).single();
        const { data: reviewTask, error: reviewError } = await db.from('sales_agent_tasks').insert({
          lead_id: task.lead_id,
          task_type: 'review_service',
          status: 'waiting_approval',
          requires_human: true,
          payload: {
            parent_task_id: task.id,
            source: 'approved_start_service',
            deal_id: delivery.deal.id,
            website_project_id: delivery.websiteProject?.id || null,
            delivery_id: delivery.delivery.id
          }
        }).select().single();
        if (reviewError) return { status: 500, body: { error: 'Service started, but review task could not be created' } };
        return { status: 200, body: { task: updated, next_task: reviewTask, delivery, action: 'service_started' } };
      } catch (serviceError) {
        return { status: 422, body: { error: serviceError.message } };
      }
    }

    const nextStatus = task.task_type === 'send_outreach' ? 'completed' : 'pending';
    const { data: updated, error: updateError } = await db.from('sales_agent_tasks').update({ status: nextStatus, requires_human: false, result: { ...task.result, decision: 'approved', approved_by: user.id, approved_at: new Date().toISOString() }, completed_at: nextStatus === 'completed' ? new Date().toISOString() : null }).eq('id', taskId).select().single();
    if (updateError) return { status: 500, body: { error: 'Could not approve task' } };

    return { status: 200, body: { task: updated, next_task: null, action: 'approved' } };
  }

  return null;
}