import { getAdminDb } from './db.js';
import { analyzeProspect } from './lead-analysis.js';
import { createOutreachDraft } from './outreach-agent.js';

export async function processDiscoveredProspects({ searchId, userId }) {
  const db = getAdminDb();
  const { data: candidates, error } = await db
    .from('prospect_candidates')
    .select('*')
    .eq('search_id', searchId)
    .in('status', ['new', 'analyzed']);

  if (error) throw new Error(error.message);

  const results = [];
  for (const candidate of candidates || []) {
    try {
      const analyzed = candidate.status === 'analyzed'
        ? candidate
        : await analyzeProspect({ candidateId: candidate.id, userId });

      const score = Number(analyzed.score || 0);
      if (score >= 60 && analyzed.lead_id) {
        const task = await createOutreachDraft({ candidateId: analyzed.id, userId, channel: 'whatsapp' });
        results.push({ candidateId: analyzed.id, status: 'outreach_waiting_approval', taskId: task.id });
      } else {
        results.push({ candidateId: analyzed.id, status: 'analyzed_not_qualified', score });
      }
    } catch (error) {
      await db.from('prospect_candidates').update({ status: 'rejected', analysis: { error: error.message }, updated_at: new Date().toISOString() }).eq('id', candidate.id);
      results.push({ candidateId: candidate.id, status: 'failed', error: error.message });
    }
  }

  return results;
}
