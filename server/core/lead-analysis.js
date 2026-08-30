import { OpenAIProvider } from '../providers/openai.js';
import { getAdminDb } from './db.js';

const ai = new OpenAIProvider();

export async function analyzeProspect({ candidateId, userId }) {
  const db = getAdminDb();
  const { data: candidate, error } = await db
    .from('prospect_candidates')
    .select('*, prospecting_searches!inner(created_by)')
    .eq('id', candidateId)
    .eq('prospecting_searches.created_by', userId)
    .single();

  if (error || !candidate) throw new Error('Prospect candidate not found');

  const prompt = `Analyze this business prospect for an AI agency. Return concise JSON with: fit_score (0-100), detected_needs (array), recommended_service (one of Website, AI Automation, AI Sales Agent), reasons (array), outreach_angle (string), priority (Hot/Warm/Cold). Business: ${candidate.company_name}. Website: ${candidate.website_url || 'none'}. Phone: ${candidate.contact_phone || 'none'}. Existing data: ${JSON.stringify(candidate.analysis || {})}`;

  const result = await ai.generate({
    messages: [
      { role: 'system', content: 'You are a B2B sales intelligence analyst. Output valid JSON only.' },
      { role: 'user', content: prompt }
    ],
    temperature: 0.2,
    maxTokens: 700
  });

  const raw = result?.text ?? result?.content ?? '';
  let analysis;
  try {
    analysis = raw ? JSON.parse(raw) : {};
  } catch {
    throw new Error('AI returned invalid analysis JSON');
  }

  const score = Number(analysis.fit_score);
  const { data: updated, error: updateError } = await db
    .from('prospect_candidates')
    .update({ analysis, score: Number.isFinite(score) ? Math.max(0, Math.min(100, score)) : candidate.score, status: 'analyzed', updated_at: new Date().toISOString() })
    .eq('id', candidateId)
    .select()
    .single();

  if (updateError) throw new Error(updateError.message);
  return updated;
}