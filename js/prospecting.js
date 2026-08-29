import {supabaseClient} from './db.js';
import {getCurrentUser} from './auth.js';
import {intelligenceForCompany} from './lead-intelligence.js';
import {toast,loading,emptyState,modal} from './ui.js';
import {escapeHtml,qs,qsa} from './utils.js';
import {recordActivity} from './activity.js';

const db=()=>supabaseClient();
const esc=v=>escapeHtml(v??'');

async function createSearch({query,targetIndustry,targetCity}){
  const user=await getCurrentUser();
  if(!user)throw new Error('Authentication required.');
  const r=await db().from('prospecting_searches').insert({created_by:user.id,query,target_industry:targetIndustry||null,target_city:targetCity||null,status:'pending',metadata:{mode:'provider_pending',created_from:'discovery'}}).select().single();
  if(r.error)throw r.error;
  await recordActivity({type:'prospecting_search_created',title:'Prospecting search created',metadata:{search_id:r.data.id,query,targetIndustry,targetCity}});
  return r.data;
}

async function importCandidates(searchId,raw){
  const lines=String(raw||'').split(/\n+/).map(x=>x.trim()).filter(Boolean);
  const rows=[];
  for(const line of lines){
    const parts=line.split('|').map(x=>x.trim());
    const [company_name,website_url,contact_phone,source_url]=parts;
    if(!company_name)continue;
    rows.push({search_id:searchId,company_name,website_url:website_url||null,contact_phone:contact_phone||null,source:'manual_import',source_url:source_url||null,status:'new'});
  }
  if(!rows.length)throw new Error('Add at least one company. Format: Company | Website | Phone | Source URL');
  const r=await db().from('prospect_candidates').insert(rows).select();
  if(r.error)throw r.error;
  await db().from('prospecting_searches').update({status:'completed',completed_at:new Date().toISOString()}).eq('id',searchId);
  return r.data||[];
}

async function analyzeCandidate(candidate){
  const company={name:candidate.company_name,website:candidate.website_url,phone:candidate.contact_phone};
  const intel=intelligenceForCompany(company);
  const analysis={score:intel.score,priority:intel.priority,opportunities:intel.opportunities,recommended_services:intel.recommendedServices,summary:`${candidate.company_name} has ${intel.opportunities.length} detected opportunity signal(s).`,next_step:intel.recommendedServices[0]?'Offer '+intel.recommendedServices[0]:'Qualify the business before outreach.'};
  const r=await db().from('prospect_candidates').update({status:'analyzed',score:intel.score,analysis,updated_at:new Date().toISOString()}).eq('id',candidate.id).select().single();
  if(r.error)throw r.error;
  await db().from('sales_agent_tasks').insert({lead_id:candidate.lead_id||null,task_type:'analyze',status:'completed',requires_human:false,payload:{prospect_candidate_id:candidate.id},result:analysis,completed_at:new Date().toISOString()});
  return r.data;
}

function searchModal(){
  const m=modal({title:'New prospecting search',body:`<form id="prospecting-form" class="form-grid"><label>What should the AI find?<input name="query" required placeholder="e.g. restaurants without a professional website"></label><label>Industry<input name="industry" placeholder="Restaurants"></label><label>City<input name="city" placeholder="Rabat"></label><div class="alert alert-warn full">The search-provider connector is not configured yet. This creates the search job now; once a provider is connected, the same job will be populated automatically.</div><div class="form-actions"><button type="button" class="btn btn-ghost" data-close>Cancel</button><button class="btn btn-primary">Create search</button></div></form>`});
  m.querySelector('form').onsubmit=async e=>{e.preventDefault();const b=e.currentTarget.querySelector('button.btn-primary');b.disabled=true;b.textContent='Creating…';try{const fd=new FormData(e.currentTarget);await createSearch({query:String(fd.get('query')).trim(),targetIndustry:String(fd.get('industry')).trim(),targetCity:String(fd.get('city')).trim()});toast('Prospecting search created','success');m.remove();render()}catch(x){toast(x.message,'error');b.disabled=false;b.textContent='Create search'}};
}

function importModal(searchId){
  const m=modal({title:'Import discovered companies',body:`<p class="muted">Paste one company per line. Use:</p><pre>Company | Website | Phone | Source URL</pre><textarea id="candidate-input" rows="10" placeholder="Example Business | https://example.com | +212... | https://source.example"></textarea><div class="form-actions"><button class="btn btn-ghost" data-close>Cancel</button><button class="btn btn-primary" id="import-candidates">Import candidates</button></div>`});
  m.querySelector('#import-candidates').onclick=async()=>{const b=m.querySelector('#import-candidates');b.disabled=true;b.textContent='Importing…';try{const rows=await importCandidates(searchId,m.querySelector('#candidate-input').value);toast(`${rows.length} candidate(s) imported`,'success');m.remove();render()}catch(e){toast(e.message,'error');b.disabled=false;b.textContent='Import candidates'}};
}

function candidateCard(c){const a=c.analysis||{};return `<article class="card"><div class="card-head"><div><span class="eyebrow">PROSPECT</span><h3>${esc(c.company_name)}</h3></div><span class="badge">${esc(c.status)}</span></div><p class="muted">${esc(c.website_url||c.source_url||'No source URL')} ${c.contact_phone?' · '+esc(c.contact_phone):''}</p><div class="lead-kpis"><div><span>Score</span><strong>${c.score==null?'—':Number(c.score)}</strong></div><div><span>Priority</span><strong>${esc(a.priority||'—')}</strong></div><div><span>Service</span><strong>${esc((a.recommended_services||[])[0]||'—')}</strong></div></div><p>${esc(a.summary||'Not analyzed yet.')}</p><div class="project-actions"><button class="btn btn-ghost" data-analyze="${c.id}" ${c.status==='analyzed'?'disabled':''}>${c.status==='analyzed'?'Analyzed':'Analyze'}</button>${c.status==='analyzed'?`<button class="btn btn-primary" data-draft="${c.id}">Prepare outreach</button>`:''}</div></article>`}

async function prepareOutreach(candidate){
  const user=await getCurrentUser();
  const service=(candidate.analysis?.recommended_services||[])[0]||'digital service';
  const draft=`Bonjour ${candidate.company_name},\n\nJ’ai découvert votre activité et j’ai remarqué une opportunité qui pourrait vous aider à améliorer votre présence en ligne. Je pense notamment à ${service}.\n\nSi vous voulez, je peux vous montrer rapidement ce que je proposerais pour votre activité, sans engagement.`;
  const task=await db().from('sales_agent_tasks').insert({lead_id:candidate.lead_id||null,task_type:'draft_outreach',status:'waiting_approval',requires_human:true,payload:{prospect_candidate_id:candidate.id,channel:'whatsapp'},result:{draft,service},created_at:new Date().toISOString()}).select().single();
  if(task.error)throw task.error;
  await db().from('prospect_candidates').update({status:'approved',updated_at:new Date().toISOString()}).eq('id',candidate.id);
  await db().from('notifications').insert({user_id:user.id,type:'prospecting_outreach_ready',title:'Outreach draft ready',message:`Draft prepared for ${candidate.company_name}. Human approval is required before external sending.`,source_type:'sales_agent_task',source_id:task.data.id});
  return draft;
}

export async function render(){
  const host=qs('#page');host.innerHTML=loading('Loading AI Prospecting…');
  try{
    const [searches,candidates]=await Promise.all([
      db().from('prospecting_searches').select('*').order('created_at',{ascending:false}).limit(20),
      db().from('prospect_candidates').select('*').order('created_at',{ascending:false}).limit(50)
    ]);
    if(searches.error)throw searches.error;if(candidates.error)throw candidates.error;
    const ss=searches.data||[], cs=candidates.data||[];
    host.innerHTML=`<div class="module-head"><div><span class="eyebrow">AI SALES / PROSPECTING</span><h2>AI Prospecting</h2><p>Find targets, analyze opportunities, prepare personalized outreach, then hand control back to you before external sending.</p></div><button class="btn btn-primary" id="new-search">+ New search</button></div><div class="metrics metrics-compact"><article class="metric-card"><span>Search jobs</span><strong>${ss.length}</strong><small>Database-backed</small></article><article class="metric-card"><span>Prospects</span><strong>${cs.length}</strong><small>Candidate records</small></article><article class="metric-card"><span>Analyzed</span><strong>${cs.filter(x=>x.status==='analyzed'||x.status==='approved').length}</strong><small>Intelligence ready</small></article><article class="metric-card"><span>Outreach approval</span><strong>${cs.filter(x=>x.status==='approved').length}</strong><small>Human approval required</small></article></div><section class="card"><div class="card-head"><div><span class="eyebrow">SEARCH QUEUE</span><h3>Prospecting searches</h3></div></div><div class="mini-list">${ss.map(s=>`<div class="list-row"><span><b>${esc(s.query)}</b><small>${esc([s.target_industry,s.target_city].filter(Boolean).join(' · ')||'Any market')}</small></span><em>${esc(s.status)}</em><button class="btn btn-ghost" data-import="${s.id}">Import results</button></div>`).join('')||'<p class="muted">No searches yet. Create your first target search.</p>'}</div></section><section class="template-grid">${cs.map(candidateCard).join('')||emptyState('No prospects yet','Create a search, then import discovered companies. The external search connector will populate this automatically once configured.')}</section>`;
    qs('#new-search').onclick=searchModal;
    qsa('[data-import]').forEach(b=>b.onclick=()=>importModal(b.dataset.import));
    qsa('[data-analyze]').forEach(b=>b.onclick=async()=>{b.disabled=true;b.textContent='Analyzing…';try{const r=await db().from('prospect_candidates').select('*').eq('id',b.dataset.analyze).single();if(r.error)throw r.error;await analyzeCandidate(r.data);toast('Prospect analyzed','success');render()}catch(e){toast(e.message,'error');b.disabled=false;b.textContent='Analyze'}});
    qsa('[data-draft]').forEach(b=>b.onclick=async()=>{try{const r=await db().from('prospect_candidates').select('*').eq('id',b.dataset.draft).single();if(r.error)throw r.error;const draft=await prepareOutreach(r.data);const m=modal({title:'Outreach draft — approval required',body:`<div class="alert alert-warn">This draft is not sent. You must approve the message before any external WhatsApp action.</div><textarea id="outreach-draft" rows="10">${esc(draft)}</textarea><div class="form-actions"><button class="btn btn-ghost" data-close>Close</button><button class="btn btn-primary" data-copy>Copy draft</button></div>`});m.querySelector('[data-copy]').onclick=async()=>{await navigator.clipboard.writeText(m.querySelector('#outreach-draft').value);toast('Draft copied','success')}}catch(e){toast(e.message,'error')}});
  }catch(e){host.innerHTML=emptyState('AI Prospecting unavailable',e.message)}
}
