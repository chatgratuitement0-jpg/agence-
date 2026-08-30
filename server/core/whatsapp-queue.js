import { getAdminDb } from './db.js';
import { WhatsAppProvider } from '../providers/whatsapp.js';

const whatsapp = new WhatsAppProvider();

export async function sendApprovedOutreach({ taskId, userId }) {
  const db = getAdminDb();
  const { data: task, error } = await db.from('sales_agent_tasks').select('*').eq('id', taskId).single();
  if (error || !task) throw new Error('Task not found');
  if (task.status !== 'queued_for_provider') throw new Error('Task is not queued for WhatsApp');

  const { data: lead, error: leadError } = await db.from('leads').select('id,owner_id,phone,conversation_id').eq('id', task.lead_id).single();
  if (leadError || !lead) throw new Error('Lead not found');
  if (lead.owner_id !== userId) throw new Error('Not authorized');
  if (!lead.phone) throw new Error('Lead has no WhatsApp phone number');

  const text = task.payload?.draft?.message || task.payload?.draft?.text;
  if (!text) throw new Error('Approved task has no message draft');

  const result = await whatsapp.send({ to: lead.phone, text });

  const { data: updated, error: updateError } = await db.from('sales_agent_tasks').update({
    status: 'completed',
    completed_at: new Date().toISOString(),
    result: { ...result, sent_at: new Date().toISOString() }
  }).eq('id', taskId).eq('status', 'queued_for_provider').select('*').single();

  if (updateError) throw new Error(updateError.message);
  return updated;
}
