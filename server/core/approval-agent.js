import { getAdminDb } from './db.js';

export async function approveOutreachTask({ taskId, userId }) {
  const db = getAdminDb();
  const { data: task, error } = await db
    .from('sales_agent_tasks')
    .select('*')
    .eq('id', taskId)
    .single();

  if (error || !task) throw new Error('Outreach task not found');
  if (task.status !== 'waiting_approval') throw new Error('Task is no longer awaiting approval');

  const { data: lead, error: leadError } = await db
    .from('leads')
    .select('id,owner_id,company_id,phone')
    .eq('id', task.lead_id)
    .single();

  if (leadError || !lead) throw new Error('Lead not found');
  if (lead.owner_id !== userId) throw new Error('Not authorized to approve this task');

  const { data: updated, error: updateError } = await db
    .from('sales_agent_tasks')
    .update({
      status: 'queued_for_provider',
      result: { approved_by: userId, approved_at: new Date().toISOString() }
    })
    .eq('id', taskId)
    .eq('status', 'waiting_approval')
    .select('*')
    .single();

  if (updateError) throw new Error(updateError.message);
  return updated;
}
