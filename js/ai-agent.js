import {supabaseClient} from './db.js';
import {getCurrentUser} from './auth.js';
import {toast,emptyState,loading,modal} from './ui.js';
import {escapeHtml,qs,qsa} from './utils.js';
import {recordActivity} from './activity.js';
const db=()=>supabaseClient();
const ACTIONS=['qualify_lead','update_lead_status','update_lead_score','recommend_service'];
const STATUSES=['pending','approved','rejected','executed','cancelled'];
const SERVICES=['Google Review QR Code','Website Vitrine','Website Professionnel'];
const safe=v=>escapeHtml(v??'');
const pct=v=>v==null?'—':`${Math.round(Number(v)*100)}%`;

function infer(lead,company,conversation,knowledge=[]){
  let score=Number(lead.score||0),reasons=[];
  if(company?.website){score+=8;reasons.push('Website is present.')}else{score-=8;reasons.push('No website recorded.');}
  if(company?.email||company?.phone){score+=6;reasons.push('Direct contact is available.');}
  if(lead.status==='interested'){score+=15;reasons.push('Lead is interested.');}
  if(lead.status==='qualified'){score+=10;reasons.push('Lead is qualified.');}
  if(lead.priority==='high'){score+=10;reasons.push('High priority.');}
  if(conversation?.status==='handoff'){score-=20;reasons.push('Human handoff is active.');}
  const knowledgeText=knowledge.map(k=>`${k.title} ${k.category} ${k.content}`).join(' ').toLowerCase();
  if(knowledgeText.includes('google review qr code')&&(!company?.website || company?.google_maps_url)){reasons.push('Approved service knowledge confirms the Review QR offer is available.');}
  score=Math.max(0,Math.min(100,score));
  const action=lead.status==='negotiating'||lead.status==='payment'||score>=70?'qualify_lead':'qualify_lead';
  return{score,action,reasons};
}

async function loadKnowledge(limit=30){
  const r=await db().from('ai_knowledge').select('id,title,category,content').eq('is_active',true).order('updated_at',{ascending:false}).limit(limit);
  if(r.error)throw r.error;
  return r.data||[];
}

export async function evaluateLead(leadId,{createLog=true}={}){
  const r=await db().from('leads').select('id,name,status,score,priority,recommended_service,company_id,companies(id,name,industry,city,website,email,phone,google_maps_url)').eq('id',leadId).single();
  if(r.error)throw r.error;
  const [cr,knowledge]=await Promise.all([
    db().from('conversations').select('id,status').eq('lead_id',leadId).order('updated_at',{ascending:false}).limit(1).maybeSingle(),
    loadKnowledge()
  ]);
  if(cr.error)throw cr.error;
  const x=infer(r.data,r.data.companies,cr.data,knowledge);
  const confidence=Math.max(.5,Math.min(.99,.6+Math.abs(x.score-50)*.007));
  const knowledgeRefs=knowledge.slice(0,10).map(k=>({id:k.id,title:k.title,category:k.category}));
  const reasoning=`Deterministic-safe evaluation using ${knowledge.length} active knowledge item(s): ${x.reasons.join(' ')} Action requires human approval before execution.`;
  if(!createLog)return{...x,confidence,reasoning,knowledgeRefs};
  const d=await db().rpc('create_ai_decision',{p_lead_id:leadId,p_action:x.action,p_confidence:confidence,p_reasoning:reasoning,p_payload:{score:x.score,recommended_service:r.data.recommended_service||SERVICES[0],engine:'deterministic-safe-v3',conversation_id:cr.data?.id||null,knowledge_refs:knowledgeRefs}});
  if(d.error)throw d.error;
  const decisionId=d.data?.id||d.data;
  await recordActivity({type:'ai_decision_created',title:'AI decision created from lead evaluation',lead_id:leadId,company_id:r.data.company_id,metadata:{decision_id:decisionId,action:x.action,confidence,knowledge_count:knowledge.length}});
  return{id:decisionId,lead_id:leadId,action:x.action,confidence,score:x.score,reasoning,approval_status:'pending',knowledgeRefs};
}

async function loadAgents(){const r=await db().from('ai_agents').select('id,name,status,enabled,default_mode,confidence_threshold,handoff_threshold,configuration,created_by,created_at,updated_at').order('updated_at',{ascending:false});if(r.error)throw r.error;return r.data||[]}
async function saveAgent(data,id){const u=await getCurrentUser();if(!u)throw new Error('Authentication required.');const r=id?await db().from('ai_agents').update(data).eq('id',id).select().single():await db().from('ai_agents').insert({...data,created_by:u.id}).select().single();if(r.error)throw r.error;return r.data}
function agentForm(agent={}){const m=modal({title:agent.id?'Edit AI agent':'New AI agent',body:`<form class="form-grid" id="agent-form"><label>Name<input name="name" required maxlength="80" value="${safe(agent.name||'Sales Agent')}"></label><label>Status<select name="status">${['active','paused','disabled'].map(x=>`<option ${agent.status===x?'selected':''}>${x}</option>`).join('')}</select></label><label>Default mode<select name="default_mode">${['manual','ai_draft','assisted','automation_ready'].map(x=>`<option ${agent.default_mode===x?'selected':''}>${x}</option>`).join('')}</select></label><label>Confidence threshold<input type="number" name="confidence_threshold" min="0" max="100" value="${Number(agent.confidence_threshold??70)}"></label><label>Human handoff threshold<input type="number" name="handoff_threshold" min="0" max="100" value="${Number(agent.handoff_threshold??45)}"></label><label>Enabled<select name="enabled"><option value="true" ${agent.enabled!==false?'selected':''}>Yes</option><option value="false" ${agent.enabled===false?'selected':''}>No</option></select></label><label class="full">Configuration JSON<textarea name="configuration">${safe(JSON.stringify(agent.configuration||{},null,2))}</textarea></label><div class="form-actions"><button type="button" class="btn btn-ghost" data-close>Cancel</button><button class="btn btn-primary">Save agent</button></div></form>`});m.querySelector('form').onsubmit=async e=>{e.preventDefault();const b=e.currentTarget.querySelector('.btn-primary');b.disabled=true;try{const f=new FormData(e.currentTarget);let configuration={};try{configuration=JSON.parse(f.get('configuration')||'{}')}catch{throw new Error('Configuration must be valid JSON.')}await saveAgent({name:String(f.get('name')).trim(),status:f.get('status'),default_mode:f.get('default_mode'),enabled:f.get('enabled')==='true',confidence_threshold:Number(f.get('confidence_threshold')),handoff_threshold:Number(f.get('handoff_threshold')),configuration},agent.id);toast('AI agent saved','success');m.remove();renderAgentCenter()}catch(x){toast(x.message,'error');b.disabled=false}}}
async function decisions(status='all'){let q=db().from('ai_decisions').select('id,lead_id,action,confidence,approval_status,reasoning,action_payload,created_at,updated_at,leads(id,name,company_id,companies(name))').order('created_at',{ascending:false}).limit(100);if(status!=='all')q=q.eq('approval_status',status);const r=await q;if(r.error)throw r.error;return r.data||[]}
function decisionCard(d){const lead=d.leads,p=d.action_payload||{},refs=Array.isArray(p.knowledge_refs)?p.knowledge_refs:[];return`<article class="card ai-decision-card"><div class="card-head"><div><span class="eyebrow">AI DECISION</span><h3>${safe(d.action)}</h3><p class="muted">${safe(lead?.name||'Lead')} · ${safe(lead?.companies?.name||'Company')}</p></div><span class="badge">${safe(d.approval_status)}</span></div><div class="lead-kpis"><div><span>Confidence</span><strong>${pct(d.confidence)}</strong></div><div><span>Action</span><strong>${safe(d.action)}</strong></div><div><span>Knowledge</span><strong>${refs.length}</strong></div></div><p>${safe(d.reasoning||'No reasoning recorded.')}</p>${refs.length?`<details><summary>Knowledge used</summary><div class="mini-list">${refs.map(k=>`<div class="list-row"><span><b>${safe(k.title)}</b><small>${safe(k.category)}</small></span></div>`).join('')}</div></details>`:''}<details><summary>Action payload</summary><pre>${safe(JSON.stringify(p,null,2))}</pre></details><div class="project-actions">${d.approval_status==='pending'?`<button class="btn btn-primary" data-approve="${d.id}" data-value="true">Approve</button><button class="btn btn-ghost" data-approve="${d.id}" data-value="false">Reject</button>`:''}${d.approval_status==='approved'?`<button class="btn btn-primary" data-execute="${d.id}">Execute</button>`:''}</div></article>`}
async function approve(id,approved){const r=await db().rpc('approve_ai_decision',{p_decision_id:id,p_approved:approved});if(r.error)throw r.error;await recordActivity({type:approved?'ai_decision_approved':'ai_decision_rejected',title:approved?'AI decision approved':'AI decision rejected',metadata:{decision_id:id}})}
async function execute(id){const r=await db().rpc('execute_ai_decision',{p_decision_id:id});if(r.error)throw r.error;await recordActivity({type:'ai_decision_executed',title:'AI decision executed',metadata:{decision_id:id}})}
async function renderDecisions(){const host=qs('#decision-list');host.innerHTML=loading('Loading decisions…');try{const rows=await decisions(qs('#decision-filter')?.value||'all');host.innerHTML=rows.map(decisionCard).join('')||emptyState('No AI decisions','Evaluate a Lead to create a decision.');qsa('[data-approve]').forEach(b=>b.onclick=async()=>{b.disabled=true;try{await approve(b.dataset.approve,b.dataset.value==='true');toast('Decision updated','success');await renderDecisions();await refreshPending()}catch(e){toast(e.message,'error');b.disabled=false}});qsa('[data-execute]').forEach(b=>b.onclick=async()=>{b.disabled=true;try{await execute(b.dataset.execute);toast('Decision executed','success');await renderDecisions();await refreshPending()}catch(e){toast(e.message,'error');b.disabled=false}})}catch(e){host.innerHTML=emptyState('Decision log unavailable',e.message)}}
async function refreshPending(){const r=await db().from('ai_decisions').select('id',{count:'exact',head:true}).eq('approval_status','pending');const e=qs('#pending-decisions');if(e)e.textContent=r.error?'0':String(r.count||0)}
async function renderAgentCenter(){const host=qs('#page');host.innerHTML=loading('Loading AI Agent…');try{const agents=await loadAgents();let knowledgeCount=0;try{knowledgeCount=(await loadKnowledge(100)).length}catch{}host.innerHTML=`<div class="module-head"><div><span class="eyebrow">AI / AGENT CORE</span><h2>AI Agent</h2><p>Human-controlled AI action center. Evaluations use approved CRM knowledge and can only change CRM data after approval.</p></div><button class="btn btn-primary" id="new-agent">+ New agent</button></div><div class="metrics metrics-compact"><article class="metric-card"><span>Active agents</span><strong>${agents.filter(a=>a.enabled&&a.status==='active').length}</strong><small>Live database</small></article><article class="metric-card"><span>Active knowledge</span><strong>${knowledgeCount}</strong><small>Approved context</small></article><article class="metric-card"><span>Pending decisions</span><strong id="pending-decisions">0</strong><small>Awaiting approval</small></article><article class="metric-card"><span>Supported actions</span><strong>${ACTIONS.length}</strong><small>Server-validated</small></article></div><section class="template-grid">${agents.map(a=>`<article class="card"><div class="card-head"><div><span class="eyebrow">AGENT</span><h3>${safe(a.name)}</h3></div><span class="badge">${safe(a.status)}</span></div><div class="info-list"><div><span>Enabled</span><strong>${a.enabled?'Yes':'No'}</strong></div><div><span>Mode</span><strong>${safe(a.default_mode)}</strong></div><div><span>Confidence threshold</span><strong>${Number(a.confidence_threshold)}%</strong></div><div><span>Handoff threshold</span><strong>${Number(a.handoff_threshold)}%</strong></div></div><div class="project-actions"><button class="btn btn-ghost" data-edit-agent="${a.id}">Edit</button></div></article>`).join('')||emptyState('No AI agents','Create an agent configuration before enabling AI workflows.')}</section><section class="card"><div class="card-head"><div><span class="eyebrow">DECISION CENTER</span><h3>Review AI actions</h3></div><select id="decision-filter"><option value="all">All statuses</option>${STATUSES.map(s=>`<option value="${s}">${s}</option>`).join('')}</select></div><div id="decision-list"></div></section>`;qs('#new-agent').onclick=()=>agentForm();qsa('[data-edit-agent]').forEach(b=>b.onclick=async()=>{const r=await db().from('ai_agents').select('*').eq('id',b.dataset.editAgent).single();if(r.error)return toast(r.error.message,'error');agentForm(r.data)});qs('#decision-filter').onchange=renderDecisions;await refreshPending();await renderDecisions()}catch(e){host.innerHTML=emptyState('AI Agent unavailable',e.message)}}
export async function render(){await renderAgentCenter()}
