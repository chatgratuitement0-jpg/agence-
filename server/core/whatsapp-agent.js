import { OpenAIProvider } from '../providers/openai.js';
import { getAdminDb } from './db.js';

const ai = new OpenAIProvider();

export async function handleIncomingSalesMessage({ leadId, message, userId }) {
  const db = getAdminDb();
  const { data: lead, error } = await db.from('leads').select('*').eq('id', leadId).single();
  if (error || !lead) throw new Error('Lead not found');

  const { data: history } = await db
    .from('messages')
    .select('role,content,created_at')
    .eq('conversation_id', lead.conversation_id)
    .order('created_at', { ascending: true })
    .limit(30);

  const prompt = `You are an AI sales agent for an AI agency. Respond to the prospect professionally and naturally. Never invent pricing, capabilities, commitments, or facts. If the prospect asks for a decision/commitment outside the configured offer, mark needs_human=true. Detect intent: interested, objection, negotiation, not_interested, ready_to_buy, unclear. Return JSON only: {"reply":"...","intent":"...","needs_human":true|false,"reason":"...","next_action":"..."}. Prospect: ${lead.name || 'Unknown'}. Company: ${lead.company_name || 'Unknown'}. Recent conversation: ${JSON.stringify(history || [])}. New message: ${message}`;

  const result = await ai.generate({
    messages: [
      { role: 'system', content: 'You are a careful B2B WhatsApp sales agent. Output valid JSON only.' },
      { role: 'user', content: prompt }
    ],
    temperature: 0.3,
    maxTokens: 700
  });

  const decision = result?.content ? JSON.parse(result.content) : {};
  const taskType = decision.needs_human ? 'handoff' : 'negotiate';

  await db.from('sales_agent_tasks').insert({
    lead_id: leadId,
    task_type: taskType,
    status: decision.needs_human ? 'waiting_approval' : 'completed',
    requires_human: Boolean(decision.needs_human),
    payload: { incoming_message: message, user_id: userId },
    result: decision
  });

  return decision;
}
