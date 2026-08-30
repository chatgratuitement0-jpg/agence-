import { getAdminDb } from './db.js';
import { analyzeProspect } from './lead-analysis.js';
import { createOutreachDraft } from './outreach-agent.js';

function priorityFromAnalysis(analysis, score) {
  const priority = String(analysis?.priority || '').toLowerCase();
  if (priority === 'hot' || score >= 80) return 'high';
  if (priority === 'warm' || score >= 60) return 'medium';
  return 'low';
}

async function ensureCompanyAndLead({ db, candidate, analysis, score, userId }) {
  let company = null;
  const { data: existingCompany } = await db
    .from('companies')
    .select('*')
    .eq('name', candidate.company_name)
    .maybeSingle();

  if (existingCompany) {
    company = existingCompany;
  } else {
    const companyPayload = {
      name: candidate.company_name,
      website: candidate.website_url || null,
      phone: candidate.contact_phone || null,
      google_maps_url: candidate.source_url || null,
      source: candidate.source || 'google_places',
      address: analysis?.address || null,
      country: 'Morocco'
    };
    const { data: createdCompany, error: companyError } = await db
      .from('companies')
      .insert(companyPayload)
      .select('*')
      .single();
    if (companyError) throw new Error(`Could not create company: ${companyError.message}`);
    company = createdCompany;
  }

  const { data: existingLead } = await db
    .from('leads')
    .select('*')
    .eq('company_id', company.id)
    .eq('owner_id', userId)
    .maybeSingle();

  if (existingLead) {
    const { data: updatedLead, error: leadUpdateError } = await db
      .from('leads')
      .update({
        score: Math.round(score),
        priority: priorityFromAnalysis(analysis, score),
        recommended_service: analysis?.recommended_service || existingLead.recommended_service,
        notes: JSON.stringify(analysis || {})
      })
      .eq('id', existingLead.id)
      .select('*')
      .single();
    if (leadUpdateError) throw new Error(`Could not update lead: ${leadUpdateError.message}`);
    return updatedLead;
  }

  const { data: lead, error: leadError } = await db
    .from('leads')
    .insert({
      company_id: company.id,
      name: candidate.company_name,
      status: 'qualified',
      score: Math.round(score),
      priority: priorityFromAnalysis(analysis, score),
      source: candidate.source || 'google_places',
      recommended_service: analysis?.recommended_service || null,
      notes: JSON.stringify(analysis || {}),
      owner_id: userId
    })
    .select('*')
    .single();

  if (leadError) throw new Error(`Could not create lead: ${leadError.message}`);
  return lead;
}

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
        const lead = await ensureCompanyAndLead({
          db,
          candidate: analyzed,
          analysis: analyzed.analysis || {},
          score,
          userId
        });

        await db
          .from('prospect_candidates')
          .update({ lead_id: lead.id, company_id: lead.company_id, status: 'qualified', updated_at: new Date().toISOString() })
          .eq('id', analyzed.id);

        const task = await createOutreachDraft({ candidateId: analyzed.id, userId, channel: 'whatsapp' });
        results.push({ candidateId: analyzed.id, leadId: lead.id, status: 'outreach_waiting_approval', taskId: task.id });
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
