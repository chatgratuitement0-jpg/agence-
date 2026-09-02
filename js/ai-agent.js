import {supabaseClient} from './db.js';
import {getCurrentUser} from './auth.js';
import {toast,emptyState,loading,modal} from './ui.js';
import {escapeHtml,qs,qsa} from './utils.js';
import {recordActivity} from './activity.js';

const db=()=>supabaseClient();
const ACTIONS=['qualify_lead','update_lead_status','update_lead_score','recommend_service'];
const STATUSES=['pending','approved','rejected','executed','cancelled'];
const safe=v=>escapeHtml(v??'');
const pct=v=>v==null?'—':`${Math.round(Number(v)*100)}%`;

async function loadAgents(){
 const r=await db().from('ai_agents').select('id,name,status,enabled,default_mode,confidence_threshold,handoff_threshold,configuration,created_by,created_at,updated_at').order('updated_at',{ascending:false});
 if(r.error)throw r.error; return r.data||[];
}

async function saveAgent(data,id){
 const u=await getCurrentUser(); if(!u)throw new Error('Authentication required.');
 const payload={...data,created_by:id?data.created_by||u.id:u.id};
 const r=id?await db().from('ai_agents').update(payload).eq('id',id).select().single():await db().from('ai_agents').insert(payload).select().single();
 if(r.error)throw r.error; return r.data;
}

function agentForm(agent={}){
 const m=modal({title:agent.id?'Edit AI agent':'New AI agent',body:`<form class="form-grid" id="agent-form">
 <label>Name<input name="name" required maxlength="80" value="${safe(agent.name||'Sales Agent')}"></label>
 <label>Status<select name="status">${['active','paused','disabled'].map(x=>`<option value="${x}" ${agent.status===x?'selected':''}>${x}</option>`).join('')}</select></label>
 <label>Default mode<select name="default_mode">${['manual','ai_draft','assisted','automation_ready'].map(x=>`<option value="${x}" ${agent.default_mode===x?'selected':''}>${x}</option>`).join('')}</select></label>
 <label>Confidence threshold<input type="number" name="confidence_threshold" min="0" max="100" value="${Number(agent.confidence_threshold??70)}"></label>
 <label>Human handoff threshold<input type="number" name="handoff_threshold" min="0" max="100" value="${Number(agent.handoff_threshold??45)}"></label>
 <label>Enabled<select name="enabled"><option value="true" ${agent.enabled!==false?'selected':''}>Yes</option><option value="false" ${agent.enabled===false?'selected':''}>No</option></select></label>
 <label class="full">Configuration JSON<textarea name="configuration">${safe(JSON.stringify(agent.configuration||{},null,2))}</textarea></label>
 <div class="form-actions"><button type="button" class="btn btn-ghost" data-close>Cancel</button><button class="btn btn-primary">Save agent</button></div></form>`});
 m.querySelector('form').onsubmit=async e=>{e.preventDefault();const b=e.currentTarget.querySelector('.btn-primary');b.disabled=true;b.textContent='Saving…';try{const f=new FormData(e.currentTarget);let configuration={};try{configuration=JSON.parse(f.get('configuration')||'{}')}catch{throw new Error('Configuration must be valid JSON.')}await saveAgent({name:String(f.get('name')).trim(),status:f.get('status'),default_mode:f.get('default_mode'),enabled:f.get('enabled')==='true',confidence_threshold:Number(f.get('confidence_threshold')),handoff_threshold:Number(f.get('handoff_threshold')),configuration,created_by:agent.created_by},agent.id);toast('AI agent saved','success');m.remove();renderAgentCenter()}catch(x){toast(x.message,'error');b.disabled=false;b.textContent='Save agent'}};
}

async function decisions(status='all'){
 let q=db().from('ai_decisions').select('id,lead_id,action,confidence,approval_status,reasoning,action_payload,created_at,updated_at,leads(id,name,company_id,companies(name))').order('created_at',{ascending:false}).limit(100);
 if(status!=='all')q=q.eq('approval_status',status); const r=await q; if(r.error)throw r.error; return r.data||[];
}

function decisionCard(d){
 const lead=d.leads; const payload=d.action_payload||{};
 return `<article class="card ai-decision-card"><div class="card-head"><div><span class="eyebrow">AI DECISION</span><h3>${safe(d.action||'—')}</h3><p class="muted">${safe(lead?.name||'Lead')} · ${safe(lead?.companies?.name||'Company')}</p></div><span class="badge">${safe(d.approval_status)}</span></div>
 <div class="lead-kpis"><div><span>Confidence</span><strong>${pct(d.confidence)}</strong></div><div><span>Action</span><strong>${safe(d.action)}</strong></div><div><span>Created</span><strong>${new Date(d.created_at).toLocaleString()}</strong></div></div>
 <p>${safe(d.reasoning||'No reasoning recorded.')}</p>
 <details><summary>Action payload</summary><pre>${safe(JSON.stringify(payload,null,2))}</pre></details>
 <div class="project-actions">${d.approval_status==='pending'?`<button class="btn btn-primary" data-approve="${d.id}" data-value="true">Approve</button><button class="btn btn-ghost" data-approve="${d.id}" data-value="false">Reject</button>`:''}${d.approval_status==='approved'?`<button class="btn btn-primary" data-execute="${d.id}">Execute</button>`:''}</div></article>`;
}

async function approve(id,approved){
 const r=await db().rpc('approve_ai_decision',{p_decision_id:id,p_approved:approved}); if(r.error)throw r.error;
 await recordActivity({type:approved?'ai_decision_approved':'ai_decision_rejected',title:approved?'AI decision approved':'AI decision rejected',metadata:{decision_id:id}});
}
async function execute(id){
 const r=await db().rpc('execute_ai_decision',{p_decision_id:id}); if(r.error)throw r.error;
 await recordActivity({type:'ai_decision_executed',title:'AI decision executed',metadata:{decision_id:id}});
}

async function renderDecisions(){
 const host=qs('#decision-list');host.innerHTML=loading('Loading decisions…');
 try{
  const status=qs('#decision-filter')?.value||'all';const rows=await decisions(status);
  host.innerHTML=rows.map(decisionCard).join('')||emptyState('No AI decisions','Create a decision from a Lead or wait for an internal AI workflow.');
  qsa('[data-approve]').forEach(b=>b.onclick=async()=>{b.disabled=true;try{await approve(b.dataset.approve,b.dataset.value==='true');toast(b.dataset.value==='true'?'Decision approved':'Decision rejected','success');await renderDecisions();await refreshPending()}catch(e){toast(e.message,'error');b.disabled=false}});
  qsa('[data-execute]').forEach(b=>b.onclick=async()=>{b.disabled=true;b.textContent='Executing…';try{await execute(b.dataset.execute);toast('Decision executed successfully','success');await renderDecisions();await refreshPending()}catch(e){toast(e.message,'error');b.disabled=false;b.textContent='Execute'}});
 }catch(e){host.innerHTML=emptyState('Decision log unavailable',e.message)}
}

async function refreshPending(){
 const r=await db().from('ai_decisions').select('id',{count:'exact',head:true}).eq('approval_status','pending');
 const el=qs('#pending-decisions');if(el)el.textContent=r.error?'0':String(r.count||0);
}

async function renderAgentCenter(){
 const host=qs('#page');host.innerHTML=loading('Loading AI Agent…');
 try{
  const agents=await loadAgents();
  host.innerHTML=`<div class="module-head"><div><span class="eyebrow">AI / AGENT CORE</span><h2>AI Agent</h2><p>Human-controlled AI action center. Every database action is created as a decision, reviewed, then executed through secure RPCs.</p></div><button class="btn btn-primary" id="new-agent">+ New agent</button></div>
  <div class="metrics metrics-compact"><article class="metric-card"><span>Active agents</span><strong>${agents.filter(a=>a.enabled&&a.status==='active').length}</strong><small>Live database</small></article><article class="metric-card"><span>Pending decisions</span><strong id="pending-decisions">0</strong><small>Awaiting approval</small></article><article class="metric-card"><span>Supported actions</span><strong>${ACTIONS.length}</strong><small>Server-validated</small></article></div>
  <section class="template-grid">${agents.map(a=>`<article class="card"><div class="card-head"><div><span class="eyebrow">AGENT</span><h3>${safe(a.name)}</h3></div><span class="badge">${safe(a.status)}</span></div><div class="info-list"><div><span>Enabled</span><strong>${a.enabled?'Yes':'No'}</strong></div><div><span>Mode</span><strong>${safe(a.default_mode)}</strong></div><div><span>Confidence threshold</span><strong>${Number(a.confidence_threshold)}%</strong></div><div><span>Handoff threshold</span><strong>${Number(a.handoff_threshold)}%</strong></div></div><div class="project-actions"><button class="btn btn-ghost" data-edit-agent="${a.id}">Edit</button></div></article>`).join('')||emptyState('No AI agents','Create an agent configuration before enabling AI workflows.')}</section>
  <section class="card"><div class="card-head"><div><span class="eyebrow">DECISION CENTER</span><h3>Review AI actions</h3></div><select id="decision-filter"><option value="all">All statuses</option>${STATUSES.map(s=>`<option value="${s}">${s}</option>`).join('')}</select></div><div id="decision-list"></div></section>`;
  qs('#new-agent').onclick=()=>agentForm();
  qsa('[data-edit-agent]').forEach(b=>b.onclick=async()=>{const r=await db().from('ai_agents').select('*').eq('id',b.dataset.editAgent).single();if(r.error)return toast(r.error.message,'error');agentForm(r.data)});
  qs('#decision-filter').onchange=renderDecisions;
  await refreshPending();await renderDecisions();
 }catch(e){host.innerHTML=emptyState('AI Agent unavailable',e.message)}
}

export async function render(){await renderAgentCenter()}
