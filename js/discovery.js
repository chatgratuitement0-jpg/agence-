import { supabaseClient } from './db.js';
import { getCurrentUser } from './auth.js';
import { toast, loading, emptyState } from './ui.js';
import { escapeHtml, qs } from './utils.js';
import { recordActivity } from './activity.js';

const db = () => supabaseClient();
const esc = value => escapeHtml(value ?? '');

const SERVICE_RULES = {
  'Google Review QR Code': 50,
  'Website Vitrine': 1500,
  'Website Professionnel': 2500
};

function recommendService(company) {
  const hasWebsite = Boolean(String(company.website || '').trim());
  const hasSocial = Boolean(String(company.instagram || company.facebook || '').trim());
  if (!hasWebsite) return { service: 'Website Professionnel', score: 88, reason: 'No website detected.' };
  if (!hasSocial) return { service: 'Website Vitrine', score: 72, reason: 'Website exists but social presence is missing.' };
  return { service: 'Google Review QR Code', score: 64, reason: 'Digital presence exists; improve review acquisition.' };
}

async function loadCompanies() {
  const { data, error } = await db()
    .from('companies')
    .select('id,name,industry,city,country,phone,email,website,instagram,facebook,google_maps_url,source,archived_at')
    .is('archived_at', null)
    .order('updated_at', { ascending: false })
    .limit(500);
  if (error) throw error;
  return data || [];
}

async function loadExistingLeadCompanyIds() {
  const { data, error } = await db().from('leads').select('company_id').limit(1000);
  if (error) throw error;
  return new Set((data || []).map(row => row.company_id).filter(Boolean));
}

async function createLead(company, recommendation) {
  const user = await getCurrentUser();
  if (!user?.id) throw new Error('Authentication required.');

  const existing = await db()
    .from('leads')
    .select('id,name,status')
    .eq('company_id', company.id)
    .neq('status', 'lost')
    .limit(1)
    .maybeSingle();
  if (existing.error) throw existing.error;
  if (existing.data) throw new Error('This company already has an active lead.');

  const { data: lead, error } = await db().from('leads').insert({
    company_id: company.id,
    name: company.name,
    status: 'new',
    score: recommendation.score,
    priority: recommendation.score >= 80 ? 'high' : recommendation.score >= 65 ? 'medium' : 'low',
    source: company.source || 'discovery',
    recommended_service: recommendation.service,
    notes: `Discovery: ${recommendation.reason}`,
    owner_id: user.id
  }).select().single();
  if (error) throw error;

  await recordActivity({
    type: 'lead_created_from_discovery',
    title: 'Lead created from Discovery',
    lead_id: lead.id,
    company_id: company.id,
    metadata: { recommended_service: recommendation.service, score: recommendation.score }
  });
  return lead;
}

function card(company, leadCompanyIds) {
  const recommendation = recommendService(company);
  const alreadyLead = leadCompanyIds.has(company.id);
  const location = [company.city, company.country].filter(Boolean).join(', ');
  return `<article class="card discovery-card"><div class="card-head"><div><span class="eyebrow">DISCOVERY</span><h3>${esc(company.name)}</h3></div><span class="badge">${recommendation.score}/100</span></div><p class="muted">${esc([company.industry, location].filter(Boolean).join(' · ') || 'Business')}</p><div class="lead-kpis"><div><span>Recommended</span><strong>${esc(recommendation.service)}</strong></div><div><span>Price</span><strong>${SERVICE_RULES[recommendation.service]} DH</strong></div><div><span>Status</span><strong>${alreadyLead ? 'Lead exists' : 'Not a lead'}</strong></div></div><p>${esc(recommendation.reason)}</p><div class="project-actions">${alreadyLead ? '<button class="btn btn-ghost" disabled>Already in Leads</button>' : `<button class="btn btn-primary" data-create-lead="${esc(company.id)}">Convert to Lead</button>`}</div></article>`;
}

export async function render() {
  const host = qs('#page');
  host.innerHTML = loading('Loading Discovery…');
  try {
    const [companies, leadCompanyIds] = await Promise.all([loadCompanies(), loadExistingLeadCompanyIds()]);
    host.innerHTML = `<div class="module-head"><div><span class="eyebrow">AI SALES / DISCOVERY</span><h2>Discovery</h2><p>Review companies already in the CRM, identify the clearest opportunity, then convert qualified companies into Leads.</p></div></div><section class="card"><div class="form-grid"><label>Search companies<input id="discovery-search" placeholder="Name, industry or city…"></label><label>Opportunity<select id="discovery-filter"><option value="all">All opportunities</option><option value="Website Professionnel">Website Professionnel</option><option value="Website Vitrine">Website Vitrine</option><option value="Google Review QR Code">Google Review QR Code</option><option value="lead">Already a lead</option></select></label></div></section><div id="discovery-grid" class="grid-2"></div>`;

    const grid = host.querySelector('#discovery-grid');
    const search = host.querySelector('#discovery-search');
    const filter = host.querySelector('#discovery-filter');

    const draw = () => {
      const term = String(search.value || '').trim().toLowerCase();
      const selected = filter.value;
      const rows = companies.filter(company => {
        const haystack = [company.name, company.industry, company.city, company.country].filter(Boolean).join(' ').toLowerCase();
        if (term && !haystack.includes(term)) return false;
        if (selected === 'lead') return leadCompanyIds.has(company.id);
        if (selected !== 'all' && selected !== recommendService(company).service) return false;
        return true;
      });
      grid.innerHTML = rows.length ? rows.map(c => card(c, leadCompanyIds)).join('') : emptyState('No companies match this Discovery filter.');
    };

    draw();
    search.addEventListener('input', draw);
    filter.addEventListener('change', draw);

    grid.addEventListener('click', async event => {
      const button = event.target.closest('[data-create-lead]');
      if (!button) return;
      const company = companies.find(item => item.id === button.dataset.createLead);
      if (!company) return;
      const recommendation = recommendService(company);
      button.disabled = true;
      button.textContent = 'Creating…';
      try {
        await createLead(company, recommendation);
        leadCompanyIds.add(company.id);
        toast(`${company.name} converted to Lead`, 'success');
        draw();
      } catch (error) {
        toast(error.message, 'error');
        button.disabled = false;
        button.textContent = 'Convert to Lead';
      }
    });
  } catch (error) {
    host.innerHTML = emptyState(error.message || 'Unable to load Discovery.');
  }
}
