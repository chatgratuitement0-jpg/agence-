import { supabaseClient } from './db.js';
import { getCurrentUser, getCurrentSession } from './auth.js';
import { toast, loading, emptyState, modal } from './ui.js';
import { escapeHtml, qs, qsa } from './utils.js';
import { recordActivity } from './activity.js';

const db = () => supabaseClient();
const esc = v => escapeHtml(v ?? '');

const INTERNAL_TEST_PROSPECTS = [
  { company_name: 'Atlas Café Rabat', score: 82, service: 'Google Review QR Code' },
  { company_name: 'Rabat Garden Restaurant', score: 74, service: 'Vitrine Website' },
  { company_name: 'Ocean View Café', score: 68, service: 'Professional Website' },
  { company_name: 'Medina Food House', score: 61, service: 'Vitrine Website' },
  { company_name: 'Rabat Lounge', score: 55, service: 'Google Review QR Code' }
];

async function apiSearch({ query, targetIndustry, targetCity }) {
  const user = await getCurrentUser();
  if (!user?.id) throw new Error('Authentication required.');

  // Internal CRM test mode: create the search and candidates directly in Supabase.
  // This intentionally avoids external Google/AI providers until integrations are enabled.
  const { data: search, error: searchError } = await db()
    .from('prospecting_searches')
    .insert({
      created_by: user.id,
      query: query.trim(),
      target_city: targetCity || null,
      target_industry: targetIndustry || null,
      status: 'running',
      metadata: { mode: 'internal_test' }
    })
    .select()
    .single();

  if (searchError) throw new Error(searchError.message);

  const candidates = INTERNAL_TEST_PROSPECTS.map(candidate => ({
    search_id: search.id,
    company_name: candidate.company_name,
    website_url: null,
    contact_phone: null,
    source: 'internal_test',
    source_url: null,
    score: candidate.score,
    analysis: {
      priority: candidate.score >= 80 ? 'hot' : candidate.score >= 65 ? 'warm' : 'cold',
      recommended_services: [candidate.service],
      address: targetCity || 'Morocco',
      test_mode: true
    },
    status: 'new'
  }));

  const { error: candidateError } = await db().from('prospect_candidates').insert(candidates);
  if (candidateError) {
    await db().from('prospecting_searches').update({ status: 'failed', metadata: { mode: 'internal_test', error: candidateError.message } }).eq('id', search.id);
    throw new Error(candidateError.message);
  }

  const { error: completeError } = await db().from('prospecting_searches').update({
    status: 'completed',
    completed_at: new Date().toISOString(),
    metadata: { mode: 'internal_test', provider: 'internal_test', count: candidates.length }
  }).eq('id', search.id);

  if (completeError) throw new Error(completeError.message);
  return search;
}

async function importCandidates(searchId, raw) {
  const rows = String(raw || '').split(/\n+/).map(x => x.trim()).filter(Boolean).map(line => {
    const [company_name, website_url, contact_phone, source_url] = line.split('|').map(x => x.trim());
    return company_name ? { search_id: searchId, company_name, website_url: website_url || null, contact_phone: contact_phone || null, source_url: source_url || null, source: 'manual_import', status: 'new' } : null;
  }).filter(Boolean);
  if (!rows.length) throw new Error('Add at least one company.');
  const r = await db().from('prospect_candidates').insert(rows).select();
  if (r.error) throw r.error;
  return r.data || [];
}

async function analyzeCandidate(candidate) {
  const score = candidate.website_url ? 70 : 45;
  const priority = score >= 70 ? 'Hot' : score >= 50 ? 'Warm' : 'Cold';
  const recommended = candidate.website_url ? 'AI Automation' : 'Website';
  const analysis = { score, priority, opportunities: ['digital presence'], recommended_services: [recommended], summary: `${candidate.company_name} has a potential ${recommended} opportunity.`, next_step: `Prepare a ${recommended} offer.` };
  const r = await db().from('prospect_candidates').update({ status: 'analyzed', score, analysis, updated_at: new Date().toISOString() }).eq('id', candidate.id).select().single();
  if (r.error) throw r.error;
  await db().from('sales_agent_tasks').insert({ lead_id: candidate.lead_id || null, task_type: 'analyze', status: 'completed', requires_human: false, payload: { prospect_candidate_id: candidate.id }, result: analysis, completed_at: new Date().toISOString() });
  return r.data;
}

async function prepareOutreach(candidate) {
  const service = (candidate.analysis?.recommended_services || [])[0] || 'digital service';
  const draft = `Bonjour,\n\nJ’ai découvert ${candidate.company_name} et je pense qu’il y a une opportunité intéressante autour de ${service}.\n\nSi vous êtes ouvert à l’idée, je peux vous montrer concrètement ce que je proposerais pour votre activité.\n\nBonne journée.`;
  const r = await db().from('sales_agent_tasks').insert({ lead_id: candidate.lead_id || null, task_type: 'send_outreach', status: 'waiting_approval', requires_human: true, payload: { prospect_candidate_id: candidate.id, channel: 'whatsapp', draft: { message: draft } } }).select().single();
  if (r.error) throw r.error;
  const user = await getCurrentUser();
  if (user) await db().from('notifications').insert({ user_id: user.id, type: 'prospecting_outreach_ready', title: 'Outreach draft ready', message: `Draft prepared for ${candidate.company_name}. Approval required.`, source_type: 'sales_agent_task', source_id: r.data.id });
  return { draft, task: r.data };
}

function searchModal() {
  const m = modal({ title: 'New prospecting search', body: `<form id="prospecting-form" class="form-grid"><label>What should the AI find?<input name="query" required placeholder="e.g. restaurants that need a professional website"></label><label>Industry<input name="industry" placeholder="Restaurants"></label><label>City<input name="city" placeholder="Rabat"></label><div class="alert alert-warn full">Internal test mode is active. No external provider or WhatsApp message is used. Candidates will be created in the CRM for workflow testing.</div><div class="form-actions"><button type="button" class="btn btn-ghost" data-close>Cancel</button><button class="btn btn-primary">Find prospects</button></div></form>` });
  m.querySelector('form').onsubmit = async e => { e.preventDefault(); const b = e.currentTarget.querySelector('.btn-primary'); b.disabled = true; b.textContent = 'Searching…'; try { const fd = new FormData(e.currentTarget); const search = await apiSearch({ query: String(fd.get('query')).trim(), targetIndustry: String(fd.get('industry')).trim(), targetCity: String(fd.get('city')).trim() }); await recordActivity({ type: 'prospecting_search_started', title: 'AI prospecting search started', metadata: { search_id: search.id, mode: 'internal_test' } }); toast('Prospecting search completed', 'success'); m.remove(); render(); } catch (x) { toast(x.message, 'error'); b.disabled = false; b.textContent = 'Find prospects'; } };
}

function importModal(searchId) {
  const m = modal({ title: 'Import discovered companies', body: `<p class="muted">One company per line: Company | Website | Phone | Source URL</p><textarea id="candidate-input" rows="10" placeholder="Example Business | https://example.com | +212... | https://source.example"></textarea><div class="form-actions"><button class="btn btn-ghost" data-close>Cancel</button><button class="btn btn-primary" id="import-candidates">Import candidates</button></div>` });
  m.querySelector('#import-candidates').onclick = async () => { const b = m.querySelector('#import-candidates'); b.disabled = true; try { const rows = await importCandidates(searchId, m.querySelector('#candidate-input').value); toast(`${rows.length} candidate(s) imported`, 'success'); m.remove(); render(); } catch (e) { toast(e.message, 'error'); b.disabled = false; } };
}

function candidateCard(c) {
  const a = c.analysis || {};
  return `<article class="card"><div class="card-head"><div><span class="eyebrow">PROSPECT</span><h3>${esc(c.company_name)}</h3></div><span class="badge">${esc(c.status)}</span></div><p class="muted">${esc(c.website_url || 'No website')} ${c.contact_phone ? ' · ' + esc(c.contact_phone) : ''}</p><div class="lead-kpis"><div><span>Score</span><strong>${c.score == null ? '—' : Number(c.score)}</strong></div><div><span>Priority</span><strong>${esc(a.priority || '—')}</strong></div><div><span>Service</span><strong>${esc((a.recommended_services || [])[0] || '—')}</strong></div></div><p>${esc(a.summary || 'Not analyzed yet.')}</p><div class="project-actions"><button class="btn btn-ghost" data-analyze="${c.id}" ${c.status === 'analyzed' ? 'disabled' : ''}>${c.status === 'analyzed' ? 'Analyzed' : 'Analyze'}</button>${c.status === 'analyzed' ? `<button class="btn btn-primary" data-draft="${c.id}">Prepare outreach</button>` : ''}</div></article>`;
}

export async function render() {
  const host = qs('#page'); host.innerHTML = loading('Loading AI Prospecting…');
  try {
    const [searches, candidates] = await Promise.all([
      db().from('prospecting_searches').select('*').order('created_at', { ascending: false }).limit(20),
      db().from('prospect_candidates').select('*').order('created_at', { ascending: false }).limit(50)
    ]);
    if (searches.error) throw searches.error; if (candidates.error) throw candidates.error;
    const ss = searches.data || [], cs = candidates.data || [];
    host.innerHTML = `<div class="module-head"><div><span class="eyebrow">AI SALES / PROSPECTING</span><h2>AI Prospecting</h2><p>Tell the agent what kind of businesses you want. It discovers, analyzes, qualifies and prepares outreach for your approval.</p></div><button class="btn btn-primary" id="new-search">+ Find prospects</button></div><div class="metrics metrics-compact"><article class="metric-card"><span>Searches</span><strong>${ss.length}</strong><small>Database-backed</small></article><article class="metric-card"><span>Prospects</span><strong>${cs.length}</strong><small>Candidate records</small></article><article class="metric-card"><span>Analyzed</span><strong>${cs.filter(x => ['analyzed','approved'].includes(x.status)).length}</strong><small>AI intelligence</small></article><article class="metric-card"><span>Approval queue</span><strong>${cs.filter(x => x.status === 'approved').length}</strong><small>Human approval</small></article></div><section class="card"><div class="card-head"><div><span class="eyebrow">SEARCH QUEUE</span><h3>Prospecting searches</h3></div></div><div class="mini-list">${ss.map(s => `<div class="list-row"><span><b>${esc(s.query)}</b><small>${esc([s.target_industry, s.target_city].filter(Boolean).join(' · ') || 'Any market')}</small></span><em>${esc(s.status)}</em><button class="btn btn-ghost" data-import="${s.id}">Import</button></div>`).join('') || '<p class="muted">No searches yet.</p>'}</div></section><section class="template-grid">${cs.map(candidateCard).join('') || emptyState('No prospects yet', 'Click Find prospects to start an AI discovery search.')}</section>`;
    qs('#new-search').onclick = searchModal;
    qsa('[data-import]').forEach(b => b.onclick = () => importModal(b.dataset.import));
    qsa('[data-analyze]').forEach(b => b.onclick = async () => { b.disabled = true; b.textContent = 'Analyzing…'; try { const r = await db().from('prospect_candidates').select('*').eq('id', b.dataset.analyze).single(); if (r.error) throw r.error; await analyzeCandidate(r.data); toast('Prospect analyzed', 'success'); render(); } catch (e) { toast(e.message, 'error'); b.disabled = false; b.textContent = 'Analyze'; } });
    qsa('[data-draft]').forEach(b => b.onclick = async () => { try { const r = await db().from('prospect_candidates').select('*').eq('id', b.dataset.draft).single(); if (r.error) throw r.error; const { draft } = await prepareOutreach(r.data); const m = modal({ title: 'Outreach draft — approval required', body: `<div class="alert alert-warn">This message is NOT sent. Approval is required before any external WhatsApp action.</div><textarea id="outreach-draft" rows="10">${esc(draft)}</textarea><div class="form-actions"><button class="btn btn-ghost" data-close>Close</button><button class="btn btn-primary" data-copy>Copy draft</button></div>` }); m.querySelector('[data-copy]').onclick = async () => { await navigator.clipboard.writeText(m.querySelector('#outreach-draft').value); toast('Draft copied', 'success'); }; } catch (e) { toast(e.message, 'error'); } });
  } catch (e) { host.innerHTML = emptyState('AI Prospecting unavailable', e.message); }
}
