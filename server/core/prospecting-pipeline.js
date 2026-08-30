import { getAdminDb } from './db.js';
import { analyzeProspect } from './lead-analysis.js';
import { createOutreachDraft } from './outreach-agent.js';

export async function processDiscoveredProspects({ searchId, userId }) {
  const db = getAdminDb();
  const { data: candidates, error } = await db
    .from('prospect_candidates')
    .select('*')
    .eq('search_id', searchId)
    .eq('status', 'new');

  if (error) throw new Error(error.message);

  const results = [];
  for (const candidate of candidates || []) {
    try {
      const analyzed = await analyzeProspect({ candidateId: candidate.id, userId });
      const score = Number(analyzed.score || 0);

      if (score >= 60) {
        if (analyzed.lead_id) {
          const task = await createOutreachDraft({ candidateId: analyzed.id, userId, channel: 'whatsapp' });
          results.push({ candidateId: analyzed.id, status: 'outreach_waiting_approval', taskId: task.id });
        } else {
          const { data: task, error: taskError } = await db.from('sales_agent_tasks').insert({
            lead_id: null,
            task_type: 'qualify_prospect',
            status: 'waiting_approval',
            requires_human: true,
            payload: { prospect_candidate_id: analyzed.id, reason: 'Qualified prospect needs lead creation before outreach.' },
            result: { score, analysis: analyzed.analysis || {} }
          }).select().single();
          if (taskError) throw new Error(taskError.message);
          results.push({ candidateId: analyzed.id, status: 'qualified_waiting_lead_approval', taskId: task.id, score });
        }
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
