import { getAdminDb } from './db.js';

export async function approveOutreachTask({ taskId, userId }) {
  const db = getAdminDb();
  const { data: task, error } = await db
    .from('sales_agent_tasks')
    .select('*')
    .eq('id', taskId)
    .eq('status', 'waiting_approval')
    .single();
  if (error || !task) throw new Error('Approval task not found');

  const { data: lead, error: leadError } = await db.from('leads').select('*').eq('id', task.lead_id).single();
  if (leadError || !lead) throw new Error('Lead not found');

  const draft = task.payload?.draft?.message || '';
  if (!draft) throw new Error('No outreach draft available');

  await db.from('sales_agent_tasks').update({
    status: 'completed',
    completed_at: new Date().toISOString(),
    result: { approved_by: userId, channel: task.payload?.channel || 'whatsapp', message: draft, delivery_status: 'queued_for_provider' }
  }).eq('id', taskId).eq('status', 'waiting_approval');

  return { taskId, leadId: lead.id, channel: task.payload?.channel || 'whatsapp', message: draft, deliveryStatus: 'queued_for_provider' };
}
