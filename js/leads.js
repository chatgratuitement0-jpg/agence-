import {supabaseClient} from './db.js';
import {recordActivity} from './activity.js';
import {evaluateLead} from './ai-agent.js';
import {intelligenceForCompany} from './lead-intelligence.js';
import {toast,modal,loading,emptyState} from './ui.js';
import {getCurrentUser} from './auth.js';
import {escapeHtml,qs} from './utils.js';
import {renderLeadTimeline} from './lead-timeline.js';

const statuses=['new','qualified','interested','negotiating','payment','won','lost'];
const dealStatuses=['open','negotiating','won','lost'];
let state={page:1,pageSize:10,search:'',status:'',priority:'',sort:'updated_at',ascending:false};
const esc=v=>escapeHtml(v??'');
const searchTerm=v=>String(v||'').trim().replace(/[(),]/g,' ').replace(/[%_]/g,c=>`\\${c}`).slice(0,120);

async function companyOptions(selected=''){
  const{data,error}=await supabaseClient().from('companies').select('id,name,industry,city,website,instagram,phone,email,google_maps_url').order('name').limit(500);
  if(error)throw error;
  return(data||[]).map(c=>`<option value="${c.id}" ${c.id===selected?'selected':''}>${esc(c.name)}${c.city?' — '+esc(c.city):''}</option>`).join('');
}

async function form(lead={}){
  return `<form id="lead-form" class="form-grid"><label>Company<select name="company_id" required><option value="">Select company…</option>${await companyOptions(lead.company_id)}</select></label><label>Lead name<input name="name" required maxlength="200" value="${esc(lead.name)}"></label><label>Status<select name="status">${statuses.map(s=>`<option ${lead.status===s?'selected':''}>${s}</option>`).join('')}</select></label><label>Score<input type="number" name="score" min="0" max="100" value="${lead.score??0}"></label><label>Priority<select name="priority"><option value="low" ${lead.priority==='low'?'selected':''}>low</option><option value="medium" ${!lead.priority||lead.priority==='medium'?'selected':''}>medium</option><option value="high" ${lead.priority==='high'?'selected':''}>high</option></select></label><label>Source<input name="source" value="${esc(lead.source)}"></label><label>Recommended service<input name="recommended_service" value="${esc(lead.recommended_service)}" placeholder="Calculated by intelligence"></label><label>Owner UUID<input name="owner_id" value="${esc(lead.owner_id)}" placeholder="Optional"></label><label class="full">Notes<textarea name="notes">${esc(lead.notes)}</textarea></label><div class="form-actions"><button class="btn btn-ghost" type="button" data-close>Cancel</button><button class="btn btn-primary" type="submit">${lead.id?'Save changes':'Create lead'}</button></div></form>`;
}

async function openForm(lead={}){
  const m=modal({title:lead.id?'Edit lead':'New lead',body:await form(lead)});
  m.querySelector('form').addEventListener('submit',async e=>{
    e.preventDefault();
    const fd=new FormData(e.currentTarget);
    const db=supabaseClient();
    try{
      const company=(await db.from('companies').select('*').eq('id',fd.get('company_id')).single());
      if(company.error)throw company.error;
      const intel=intelligenceForCompany(company.data);
      const score=Math.max(0,Math.min(100,Number(fd.get('score')||intel.score)));
      const payload={company_id:fd.get('company_id'),name:String(fd.get('name')).trim(),status:fd.get('status'),score,priority:fd.get('priority')||intel.priority,source:String(fd.get('source')||'').trim()||null,recommended_service:String(fd.get('recommended_service')||intel.recommendedServices[0]||'').trim()||null,notes:String(fd.get('notes')||'').trim()||null,owner_id:String(fd.get('owner_id')||'').trim()||((await getCurrentUser())?.id||null)};
      const r=lead.id?await db.from('leads').update(payload).eq('id',lead.id).select().single():await db.from('leads').insert(payload).select().single();
      if(r.error)throw r.error;
      if(!lead.id){const opportunities=intel.opportunities;if(opportunities.length)await db.from('lead_opportunities').insert(opportunities.map(o=>({...o,lead_id:r.data.id})));}
      await recordActivity({type:lead.id?'lead_updated':'lead_created',title:lead.id?'Lead updated':'Lead created',lead_id:r.data.id,company_id:r.data.company_id,metadata:{score:payload.score,priority:payload.priority}});
      m.remove();toast(lead.id?'Lead updated':'Lead created','success');render();
    }catch(x){toast(x.message||'Unable to save lead','error');}
  });
}

async function dealOptions(){
  const db=supabaseClient();
  const r=await db.from('services').select('id,name,price,currency,active').eq('active',true).order('name').limit(100);
  if(r.error)throw r.error;
  return r.data||[];
}

async function openDealForm(lead){
  try{
    const services=await dealOptions();
    if(!services.length){toast('No active services are configured.','error');return;}
    const recommended=services.find(s=>s.name===lead.recommended_service);
    const defaultService=recommended||services[0];
    const body=`<form id="lead-deal-form" class="form-grid"><div class="full info-list"><div><span>Lead</span><strong>${esc(lead.name)}</strong></div><div><span>Company</span><strong>${esc(lead.companies?.name||'—')}</strong></div></div><label class="full">Service<select name="service_id" required>${services.map(s=>`<option value="${s.id}" data-price="${s.price}" data-currency="${esc(s.currency||'MAD')}" ${s.id===defaultService.id?'selected':''}>${esc(s.name)} — ${Number(s.price).toLocaleString()} ${esc(s.currency||'MAD')}</option>`).join('')}</select></label><label>Deal value<input name="value" type="number" min="0" step="0.01" required value="${Number(defaultService.price||0)}"></label><label>Currency<input name="currency" maxlength="3" required value="${esc(defaultService.currency||'MAD')}"></label><label>Status<select name="status">${dealStatuses.map(s=>`<option value="${s}" ${s==='open'?'selected':''}>${s}</option>`).join('')}</select></label><label>Probability %<input name="probability" type="number" min="0" max="100" step="1" value="50"></label><label>Expected close date<input name="expected_close_date" type="date"></label><label class="full">Notes<textarea name="notes" maxlength="5000" placeholder="Commercial notes…"></textarea></label><div class="form-actions"><button type="button" class="btn btn-ghost" data-close>Cancel</button><button class="btn btn-primary" type="submit">Create deal</button></div></form>`;
    const m=modal({title:'Create deal from lead',body});
    const f=m.querySelector('#lead-deal-form');
    const serviceSelect=f.querySelector('[name="service_id"]');
    const valueInput=f.querySelector('[name="value"]');
    const currencyInput=f.querySelector('[name="currency"]');
    serviceSelect.addEventListener('change',()=>{
      const option=serviceSelect.selectedOptions[0];
      if(!option?.value)return;
      valueInput.value=option.dataset.price||'0';
      currencyInput.value=option.dataset.currency||'MAD';
    });
    f.addEventListener('submit',async e=>{
      e.preventDefault();
      const fd=new FormData(f);
      const payload={lead_id:lead.id,service_id:String(fd.get('service_id')||''),value:Number(fd.get('value')),currency:String(fd.get('currency')||'MAD').trim().toUpperCase(),status:String(fd.get('status')||'open'),probability:Number(fd.get('probability')||0),expected_close_date:String(fd.get('expected_close_date')||'')||null,notes:String(fd.get('notes')||'').trim()||null};
      if(!payload.service_id||!Number.isFinite(payload.value)||payload.value<0||!Number.isInteger(payload.probability)||payload.probability<0||payload.probability>100||!/^[A-Z]{3}$/.test(payload.currency)||!dealStatuses.includes(payload.status)){toast('Check the deal fields.','error');return;}
      const selected=services.find(s=>s.id===payload.service_id);
      if(!selected){toast('Selected service is invalid.','error');return;}
      const db=supabaseClient();
      const r=await db.from('deals').insert(payload).select('id,lead_id,service_id,value,currency,status,probability,expected_close_date,services(name)').single();
      if(r.error){toast(r.error.message,'error');return;}
      await recordActivity({type:'deal_created',title:'Deal created from lead',description:`${r.data.services?.name||'Deal'} · ${lead.name}`,lead_id:lead.id,company_id:lead.company_id,metadata:{deal_id:r.data.id,service_id:r.data.service_id,value:r.data.value,currency:r.data.currency,status:r.data.status,probability:r.data.probability}});
      m.remove();
      toast('Deal created successfully','success');
      await details(lead.id);
    });
  }catch(e){toast(e.message||'Unable to open deal form','error');}
}

async function details(id){
  const db=supabaseClient();
  const l=await db.from('leads').select('*,companies(id,name,industry,city,country,website,instagram,facebook,linkedin,google_maps_url,phone,email)').eq('id',id).single();
  if(l.error){toast(l.error.message,'error');return;}
  const [o,a,c,d,w,q]=await Promise.all([db.from('lead_opportunities').select('*').eq('lead_id',id).order('created_at',{ascending:false}),db.from('activities').select('*').eq('lead_id',id).order('created_at',{ascending:false}).limit(30),db.from('conversations').select('id,channel,status,last_message_at').eq('lead_id',id).order('created_at',{ascending:false}),db.from('deals').select('id,value,currency,status,probability,expected_close_date,service_id,services(name)').eq('lead_id',id).order('created_at',{ascending:false}),db.from('website_projects').select('id,status,preview_url,updated_at,website_templates(name)').eq('lead_id',id).order('updated_at',{ascending:false}),db.from('qr_projects').select('id,status,destination_url,updated_at,qr_templates(name)').eq('lead_id',id).order('updated_at',{ascending:false})]);
  const x=l.data;
  const deals=d.data||[];
  const body=`<div class="detail-grid"><section><span class="eyebrow">LEAD</span><div class="project-actions"><button class="btn btn-ghost" id="evaluate-ai">Evaluate with AI engine</button><button class="btn btn-primary" id="create-deal">+ Create deal</button></div><h2>${esc(x.name)}</h2><div class="lead-kpis"><div><span>Score</span><strong>${x.score}</strong></div><div><span>Priority</span><strong>${esc(x.priority)}</strong></div><div><span>Status</span><strong>${esc(x.status)}</strong></div></div><div class="info-list"><div><span>Company</span><strong>${esc(x.companies?.name)}</strong></div><div><span>Recommended service</span><strong>${esc(x.recommended_service||'—')}</strong></div><div><span>Source</span><strong>${esc(x.source||'—')}</strong></div><div><span>Owner</span><strong>${esc(x.owner_id||'Unassigned')}</strong></div></div><p>${esc(x.notes||'No notes')}</p></section><section><span class="eyebrow">OPPORTUNITIES</span><div class="mini-list">${(o.data||[]).map(z=>`<div class="list-row"><span><b>${esc(z.title)}</b><small>${esc(z.description)}</small></span><em>${esc(z.severity)}</em></div>`).join('')||emptyState('No detected opportunities','Run intelligence after company data changes.')}</div><span class="eyebrow">CONVERSATIONS</span>${(c.data||[]).map(z=>`<div class="list-row"><span>${esc(z.channel)}</span><em>${esc(z.status)}</em></div>`).join('')||'<p class="muted">No conversations.</p>'}<div class="project-actions"><span class="eyebrow">DEALS</span><button class="btn btn-primary" id="create-deal-inline">+ Create deal</button></div>${deals.map(z=>`<div class="list-row"><span><b>${esc(z.services?.name||'Deal')}</b><small>${esc(z.status)} · ${Number(z.probability||0)}% probability</small></span><em>${Number(z.value).toLocaleString()} ${esc(z.currency)}</em></div>`).join('')||'<p class="muted">No deals yet. Create the first deal from this lead.</p>'}</section><section class="full"><span class="eyebrow">WEBSITE PROJECTS</span>${(w.data||[]).map(z=>`<div class="list-row"><span><b>${esc(z.website_templates?.name||'Website')}</b><small>${esc(z.status)}</small></span><em>${z.preview_url?'Preview ready':'—'}</em></div>`).join('')||'<p class="muted">No website projects.</p>'}<span class="eyebrow">QR PROJECTS</span>${(q.data||[]).map(z=>`<div class="list-row"><span><b>${esc(z.qr_templates?.name||'QR')}</b><small>${esc(z.status)}</small></span><em>QR</em></div>`).join('')||'<p class="muted">No QR projects.</p>'}</section><section class="full"><span class="eyebrow">RELATIONSHIP TIMELINE</span><div id="lead-unified-timeline"></div></section></div>`;
  const m=modal({title:'Lead details',body});
  const create=()=>openDealForm(x);
  m.querySelector('#create-deal')?.addEventListener('click',create);
  m.querySelector('#create-deal-inline')?.addEventListener('click',create);
  m.querySelector('#evaluate-ai')?.addEventListener('click',async()=>{const b=m.querySelector('#evaluate-ai');b.disabled=true;b.textContent='Evaluating…';try{const d=await evaluateLead(id);toast(`Decision: ${d.action} · confidence ${d.confidence}%`,'success');b.textContent='Evaluation recorded';}catch(e){toast(e.message,'error');b.disabled=false;b.textContent='Evaluate with AI engine';}});
  renderLeadTimeline(m.querySelector('#lead-unified-timeline'),id);
}

export async function changeLeadStatus(id,newStatus){
  const db=supabaseClient();
  const{data:old,error}=await db.from('leads').select('status,company_id,name').eq('id',id).single();
  if(error)throw error;
  if(!statuses.includes(newStatus))throw new Error('Invalid lead status.');
  if(old.status===newStatus)return;
  const r=await db.from('leads').update({status:newStatus}).eq('id',id).select().single();
  if(r.error)throw r.error;
  await recordActivity({type:'lead_status_changed',title:'Lead status changed',description:`${old.name}: ${old.status} → ${newStatus}`,lead_id:id,company_id:old.company_id,metadata:{old_status:old.status,new_status:newStatus}});
  toast('Lead status updated','success');render();
}

export async function render(){
  const host=qs('#page');host.innerHTML=loading('Loading leads…');
  const db=supabaseClient();
  let q=db.from('leads').select('id,name,status,score,priority,source,recommended_service,owner_id,updated_at,created_at,companies(name,industry,city,country,website,instagram,phone,email)',{count:'exact'});
  if(state.status)q=q.eq('status',state.status);
  if(state.priority)q=q.eq('priority',state.priority);
  if(state.search){const s=searchTerm(state.search);q=q.or(`name.ilike.%${s}%,source.ilike.%${s}%,recommended_service.ilike.%${s}%`);}
  q=q.order(state.sort,{ascending:state.ascending}).range((state.page-1)*state.pageSize,state.page*state.pageSize-1);
  const{data,error,count}=await q;
  if(error){host.innerHTML=emptyState('Unable to load leads',error.message);return;}
  const rows=data||[];
  host.innerHTML=`<div class="module-head"><div><span class="eyebrow">CRM / LEADS</span><h2>Leads</h2><p>Qualification, scoring and sales readiness from live Supabase records.</p></div><button class="btn btn-primary" id="new-lead">+ New lead</button></div><section class="toolbar"><input id="lead-search" placeholder="Search lead, source, service…" value="${esc(state.search)}"><select id="status-filter"><option value="">All statuses</option>${statuses.map(s=>`<option ${state.status===s?'selected':''}>${s}</option>`).join('')}</select><select id="priority-filter"><option value="">All priorities</option>${['low','medium','high'].map(s=>`<option ${state.priority===s?'selected':''}>${s}</option>`).join('')}</select></section><section class="table-card"><table><thead><tr><th>Lead</th><th>Company</th><th>Status</th><th>Score</th><th>Priority</th><th>Service</th><th></th></tr></thead><tbody>${rows.map(x=>`<tr><td><button class="link-btn" data-view="${x.id}">${esc(x.name)}</button></td><td>${esc(x.companies?.name||'—')}</td><td><span class="badge">${esc(x.status)}</span></td><td>${x.score}</td><td>${esc(x.priority)}</td><td>${esc(x.recommended_service||'—')}</td><td><button class="icon-btn" data-view="${x.id}">→</button></td></tr>`).join('')||`<tr><td colspan="7">${emptyState('No leads','Create a lead to start qualification.')}</td></tr>`}</tbody></table></section><div class="pagination"><span>${count||0} leads</span><div><button class="btn btn-ghost" id="prev" ${state.page<=1?'disabled':''}>Previous</button><span>Page ${state.page}</span><button class="btn btn-ghost" id="next" ${(state.page*state.pageSize)>=(count||0)?'disabled':''}>Next</button></div></div>`;
  qs('#new-lead').onclick=()=>openForm();
  qs('#lead-search').onchange=e=>{state.search=e.target.value;state.page=1;render();};
  qs('#status-filter').onchange=e=>{state.status=e.target.value;state.page=1;render();};
  qs('#priority-filter').onchange=e=>{state.priority=e.target.value;state.page=1;render();};
  qs('#prev').onclick=()=>{state.page--;render();};
  qs('#next').onclick=()=>{state.page++;render();};
  host.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>details(b.dataset.view));
}

export async function globalSearch(term){
  const s=searchTerm(term);if(!s)return[];const db=supabaseClient();
  const [c,l,conv,d,w,q,i]=await Promise.all([
    db.from('companies').select('id,name,industry,city').or(`name.ilike.%${s}%,industry.ilike.%${s}%,city.ilike.%${s}%`).limit(5),
    db.from('leads').select('id,name,status,companies(name)').or(`name.ilike.%${s}%,source.ilike.%${s}%,recommended_service.ilike.%${s}%`).limit(5),
    db.from('conversations').select('id,subject,status,channel,leads(name)').or(`subject.ilike.%${s}%,status.ilike.%${s}%,channel.ilike.%${s}%`).limit(5),
    db.from('deals').select('id,value,currency,status,services(name),leads(name,companies(name))').or(`status.ilike.%${s}%`).limit(5),
    db.from('website_projects').select('id,status,preview_url,companies(name)').or(`status.ilike.%${s}%,preview_url.ilike.%${s}%`).limit(5),
    db.from('qr_projects').select('id,status,branding,destination_url,companies(name)').or(`status.ilike.%${s}%,destination_url.ilike.%${s}%`).limit(5),
    db.from('invoices').select('id,invoice_number,status,total,currency,companies(name)').or(`invoice_number.ilike.%${s}%,status.ilike.%${s}%`).limit(5)
  ]);
  return [
    {type:'Companies',items:c.data||[],error:c.error},
    {type:'Leads',items:l.data||[],error:l.error},
    {type:'Conversations',items:(conv.data||[]).map(x=>({...x,name:x.subject||x.leads?.name||`Conversation ${x.id.slice(0,8)}`})),error:conv.error},
    {type:'Deals',items:(d.data||[]).map(x=>({...x,name:`${x.services?.name||'Deal'} · ${x.leads?.companies?.name||x.leads?.name||x.id.slice(0,8)}`})),error:d.error},
    {type:'Website Projects',items:(w.data||[]).map(x=>({...x,name:x.companies?.name||`Website ${x.id.slice(0,8)}`})),error:w.error},
    {type:'QR Projects',items:(q.data||[]).map(x=>({...x,name:x.branding?.title||x.companies?.name||`QR ${x.id.slice(0,8)}`})),error:q.error},
    {type:'Invoices',items:(i.data||[]).map(x=>({...x,name:`${x.invoice_number} · ${x.companies?.name||''}`})),error:i.error}
  ];
}
