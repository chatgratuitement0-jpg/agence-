import { getAdminDb } from './db.js';
import { OpenAIProvider } from '../providers/openai.js';
import { WhatsAppProvider } from '../providers/whatsapp.js';

const ai = new OpenAIProvider();
const whatsapp = new WhatsAppProvider();

export async function handleSalesConversation({ leadId, userId }) {
  const db = getAdminDb();

  const { data: lead, error: leadError } = await db
    .from('leads')
    .select('id,name,owner_id,company_id,phone')
    .eq('id', leadId)
    .single();
  if (leadError || !lead) throw new Error('Lead not found');
  if (lead.owner_id !== userId) throw new Error('Not authorized');

  const { data: conversation } = await db
    .from('conversations')
    .select('id,status,channel')
    .eq('lead_id', leadId)
    .eq('channel', 'whatsapp')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!conversation) throw new Error('WhatsApp conversation not found');

  const { data: history } = await db
    .from('messages')
    .select('sender_type,message,created_at')
    .eq('conversation_id', conversation.id)
    .order('created_at', { ascending: true })
    .limit(30);

  const decision = await ai.analyze({
    channel: 'whatsapp',
    lead: { id: lead.id, name: lead.name },
    conversation: history || []
  });

  if (decision.data?.needs_human || decision.data?.recommended_action === 'handoff') {
    await db.from('conversations').update({ status: 'human_required' }).eq('id', conversation.id);
    await db.from('sales_agent_tasks').insert({
      lead_id: lead.id,
      task_type: 'handoff',
      status: 'waiting_approval',
      requires_human: true,
      payload: { reason: decision.data?.reason || 'AI requested human review', channel: 'whatsapp' },
      result: decision.data || {}
    });
    return { action: 'handoff', decision: decision.data };
  }

  const reply = decision.data?.suggested_reply || decision.data?.reply || '';
  if (!reply) return { action: 'no_reply', decision: decision.data };
  if (!lead.phone) throw new Error('Lead has no WhatsApp phone number');

  const sent = await whatsapp.send({ to: lead.phone, text: reply });
  const { error: messageError } = await db.from('messages').insert({
    conversation_id: conversation.id,
    sender_type: 'ai',
    message: reply,
    channel: 'whatsapp',
    ai_generated: true,
    metadata: { provider: sent.provider, message_id: sent.message_id }
  });
  if (messageError) throw new Error(messageError.message);

  await db.from('conversations').update({
    status: 'active',
    last_message_at: new Date().toISOString()
  }).eq('id', conversation.id);

  return { action: 'replied', reply, provider: sent };
}
