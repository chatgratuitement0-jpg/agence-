import { OpenAIProvider } from '../providers/openai.js';
import { getAdminDb } from './db.js';

const ai = new OpenAIProvider();

export async function createOutreachDraft({ candidateId, userId, channel = 'whatsapp' }) {
  const db = getAdminDb();
  const { data: candidate, error } = await db.from('prospect_candidates').select('*').eq('id', candidateId).single();
  if (error || !candidate) throw new Error('Prospect candidate not found');

  const analysis = candidate.analysis || {};
  const prompt = `Create one concise, personalized B2B outreach message for ${channel}. Do not claim facts that are not provided. Goal: start a conversation, not pressure a sale. Business: ${candidate.company_name}. Website: ${candidate.website_url || 'none'}. Analysis: ${JSON.stringify(analysis)}. Recommended service: ${analysis.recommended_service || 'not specified'}. Outreach angle: ${analysis.outreach_angle || 'not specified'}. Return JSON only: {"message":"...","reason":"..."}`;

  const result = await ai.generate({
    messages: [
      { role: 'system', content: 'You are a professional B2B outreach copywriter. Output valid JSON only.' },
      { role: 'user', content: prompt }
    ],
    temperature: 0.4,
    maxTokens: 500
  });

  const draft = result?.content ? JSON.parse(result.content) : {};
  const leadId = candidate.lead_id;
  if (!leadId) throw new Error('Candidate must be linked to a lead before outreach drafting');

  const { data: task, error: taskError } = await db.from('sales_agent_tasks').insert({
    lead_id: leadId,
    task_type: 'send_outreach',
    status: 'waiting_approval',
    requires_human: true,
    payload: { channel, candidate_id: candidateId, draft },
    result: {}
  }).select().single();

  if (taskError) throw new Error(taskError.message);
  await db.from('prospect_candidates').update({ status: 'approved', updated_at: new Date().toISOString() }).eq('id', candidateId);
  return task;
}
