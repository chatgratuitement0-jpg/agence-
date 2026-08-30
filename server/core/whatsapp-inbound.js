import crypto from 'node:crypto';
import { getAdminDb } from './db.js';
import { OpenAIProvider } from '../providers/openai.js';

const ai = new OpenAIProvider();

export function verifyWhatsAppSignature(rawBody, signature, appSecret) {
  if (!rawBody || !signature || !appSecret) return false;
  const expected = `sha256=${crypto.createHmac('sha256', appSecret).update(rawBody).digest('hex')}`;
  const a = Buffer.from(expected);
  const b = Buffer.from(String(signature));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

export function verifyWhatsAppChallenge(url, verifyToken) {
  const parsed = new URL(url, 'http://localhost');
  return parsed.searchParams.get('hub.mode') === 'subscribe'
    && parsed.searchParams.get('hub.verify_token') === verifyToken
    ? parsed.searchParams.get('hub.challenge')
    : null;
}

export async function processWhatsAppInbound({ rawBody, userAgent = '' }) {
  const db = getAdminDb();
  const payload = JSON.parse(rawBody);
  const entries = Array.isArray(payload.entry) ? payload.entry : [];
  let processed = 0;
  let unmatched = 0;

  for (const entry of entries) {
    for (const change of entry?.changes || []) {
      const value = change?.value || {};
      for (const incoming of value.messages || []) {
        if (incoming?.type !== 'text') continue;
        const phone = String(incoming.from || '').trim();
        const text = String(incoming.text?.body || '').trim();
        if (!phone || !text) continue;

        const { data: company } = await db
          .from('companies')
          .select('id,name,phone')
          .eq('phone', phone)
          .maybeSingle();

        let lead = null;
        if (company) {
          const { data } = await db
            .from('leads')
            .select('id,name,owner_id,company_id')
            .eq('company_id', company.id)
            .order('created_at', { ascending: true })
            .limit(1)
            .maybeSingle();
          lead = data;
        }

        if (!lead) {
          unmatched += 1;
          continue;
        }

        let conversation;
        const { data: existingConversation } = await db
          .from('conversations')
          .select('*')
          .eq('lead_id', lead.id)
          .eq('channel', 'whatsapp')
          .in('status', ['active', 'waiting', 'human_required'])
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle();

        if (existingConversation) {
          conversation = existingConversation;
        } else {
          const { data: createdConversation, error } = await db
            .from('conversations')
            .insert({ lead_id: lead.id, channel: 'whatsapp', status: 'active', assigned_to: lead.owner_id })
            .select('*')
            .single();
          if (error) throw new Error(error.message);
          conversation = createdConversation;
        }

        const { error: messageError } = await db.from('messages').insert({
          conversation_id: conversation.id,
          sender_type: 'lead',
          message: text,
          channel: 'whatsapp',
          ai_generated: false
        });
        if (messageError) throw new Error(messageError.message);

        await db.from('conversations').update({
          last_message_at: new Date().toISOString(),
          status: 'active'
        }).eq('id', conversation.id);

        const { data: history } = await db
          .from('messages')
          .select('sender_type,message,created_at')
          .eq('conversation_id', conversation.id)
          .order('created_at', { ascending: false })
          .limit(20);

        let decision = null;
        try {
          decision = await ai.analyze({
            channel: 'whatsapp',
            lead: { id: lead.id, name: lead.name, company: company?.name || null },
            conversation: (history || []).reverse(),
            incoming_message: text
          });
        } catch (error) {
          decision = { data: { intent: 'unclear', confidence: 0, recommended_action: 'handoff', needs_human: true, lead_score: 0, suggested_service: null, reason: error.message } };
        }

        await db.from('sales_agent_tasks').insert({
          lead_id: lead.id,
          task_type: decision.data.needs_human ? 'handoff' : 'negotiate',
          status: decision.data.needs_human ? 'waiting_approval' : 'pending',
          requires_human: Boolean(decision.data.needs_human),
          payload: { incoming_message: text, channel: 'whatsapp', user_agent: userAgent },
          result: decision.data
        });

        processed += 1;
      }
    }
  }

  return { processed, unmatched };
}
