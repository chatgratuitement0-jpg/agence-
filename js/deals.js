import {supabaseClient} from './db.js';
import {toast,loading,emptyState,modal} from './ui.js';
import {escapeHtml,qs} from './utils.js';
import {recordActivity} from './activity.js';
import {DEFAULT_BUSINESS_DATA} from './website-generator.js';
import {validateDestinationUrl} from './qr-generator.js';

const statuses=['open','negotiating','won','lost'];
const esc=v=>escapeHtml(v??'');
const money=(v,c='MAD')=>`${Number(v||0).toLocaleString()} ${esc(c)}`;

async function loadOptions(){
  const db=supabaseClient();
  const [leads,services]=await Promise.all([
    db.from('leads').select('id,name,status,company_id,companies(id,name)').order('updated_at',{ascending:false}).limit(500),
    db.from('services').select('id,name,price,currency,active').eq('active',true).order('name').limit(100)
  ]);
  if(leads.error)throw leads.error;
  if(services.error)throw services.error;
  return {leads:leads.data||[],services:services.data||[]};
}

async function form(existing={}){
  const {leads,services}=await loadOptions();
  const service=services.find(s=>s.id===existing.service_id);
  const currentValue=existing.value??service?.price??0;
  const currentCurrency=existing.currency||service?.currency||'MAD';
  return `<form id="deal-form" class="form-grid">
    <label class="full">Lead<select name="lead_id" required><option value="">Select lead…</option>${leads.map(l=>`<option value="${l.id}" ${l.id===existing.lead_id?'selected':''}>${esc(l.name)} — ${esc(l.companies?.name||'No company')}</option>`).join('')}</select></label>
    <label>Service<select name="service_id" required><option value="">Select service…</option>${services.map(s=>`<option value="${s.id}" data-price="${s.price}" data-currency="${esc(s.currency)}" ${s.id===existing.service_id?'selected':''}>${esc(s.name)} — ${money(s.price,s.currency)}</option>`).join('')}</select></label>
    <label>Deal value<input name="value" type="number" min="0" step="0.01" required value="${Number(currentValue)}"></label>
    <label>Currency<input name="currency" maxlength="3" required value="${esc(currentCurrency)}"></label>
    <label>Status<select name="status">${statuses.map(s=>`<option value="${s}" ${s===existing.status||(!existing.id&&s==='open')?'selected':''}>${s}</option>`).join('')}</select></label>
    <label>Probability %<input name="probability" type="number" min="0" max="100" step="1" value="${existing.probability??50}"></label>
    <label>Expected close date<input name="expected_close_date" type="date" value="${esc(existing.expected_close_date||'')}"></label>
    <label class="full">Notes<textarea name="notes" maxlength="5000">${esc(existing.notes||'')}</textarea></label>
    <div class="form-actions"><button type="button" class="btn btn-ghost" data-close>Cancel</button><button class="btn btn-primary" type="submit">${existing.id?'Save changes':'Create deal'}</button></div>
  </form>`;
}

async function openForm(existing={}){
  try{
    const m=modal({title:existing.id?'Edit deal':'New deal',body:await form(existing)});
    const f=m.querySelector('#deal-form');
    const serviceSelect=f.querySelector('[name="service_id"]');
    const valueInput=f.querySelector('[name="value"]');
    const currencyInput=f.querySelector('[name="currency"]');
    serviceSelect.addEventListener('change',()=>{
      const option=serviceSelect.selectedOptions[0];
      if(!option?.value)return;
      if(!existing.id||!Number(valueInput.value))valueInput.value=option.dataset.price||'0';
      currencyInput.value=option.dataset.currency||'MAD';
    });
    f.addEventListener('submit',async e=>{
      e.preventDefault();
      const fd=new FormData(f);
      const payload={
        lead_id:String(fd.get('lead_id')||''),service_id:String(fd.get('service_id')||''),value:Number(fd.get('value')),currency:String(fd.get('currency')||'MAD').trim().toUpperCase(),status:String(fd.get('status')||'open'),probability:Number(fd.get('probability')||0),expected_close_date:String(fd.get('expected_close_date')||'')||null,notes:String(fd.get('notes')||'').trim()||null
      };
      if(!payload.lead_id||!payload.service_id||!Number.isFinite(payload.value)||payload.value<0||!Number.isInteger(payload.probability)||payload.probability<0||payload.probability>100||!/^[A-Z]{3}$/.test(payload.currency)||!statuses.includes(payload.status)){toast('Check the deal fields.','error');return;}
      const db=supabaseClient();
      const r=existing.id?await db.from('deals').update(payload).eq('id',existing.id).select('*,leads(name,company_id),services(name)').single():await db.from('deals').insert(payload).select('*,leads(name,company_id),services(name)').single();
      if(r.error)throw r.error;
      await recordActivity({type:existing.id?'deal_updated':'deal_created',title:existing.id?'Deal updated':'Deal created',description:`${r.data.services?.name||'Deal'} · ${r.data.leads?.name||''}`,lead_id:r.data.lead_id,metadata:{deal_id:r.data.id,value:r.data.value,currency:r.data.currency,status:r.data.status}});
      toast(existing.id?'Deal updated':'Deal created','success');m.remove();render();
    });
  }catch(e){toast(e.message||'Unable to open deal form','error')}
}

async function createProjectFromDeal(deal){
  const db=supabaseClient();
  const [companyRes,existingWebRes,existingQrRes]=await Promise.all([
    db.from('companies').select('id,name,industry,description,city,country,phone,email,address,website,instagram,facebook,linkedin,google_maps_url').eq('id',deal.leads?.company_id).single(),
    db.from('website_projects').select('id,status').eq('deal_id',deal.id).limit(1),
    db.from('qr_projects').select('id,status').eq('deal_id',deal.id).limit(1)
  ]);
  if(companyRes.error)throw companyRes.error;
  if((existingWebRes.data||[]).length||(existingQrRes.data||[]).length){toast('A project is already linked to this deal.','error');return;}
  const serviceName=String(deal.services?.name||'').toLowerCase();
  const company=companyRes.data||{};
  if(serviceName.includes('website')){
    const [templatesRes]=await Promise.all([db.from('website_templates').select('id,key,name,service_type').eq('active',true).order('name')]);
    if(templatesRes.error)throw templatesRes.error;
    const templates=templatesRes.data||[];
    if(!templates.length){toast('No active website templates are configured.','error');return;}
    const body=`<form id="deal-project-form" class="form-grid"><div class="full info-list"><div><span>Company</span><strong>${esc(company.name||'—')}</strong></div><div><span>Service</span><strong>${esc(deal.services?.name||'Website')}</strong></div><div><span>Deal</span><strong>${money(deal.value,deal.currency)}</strong></div></div><label class="full">Website template<select name="template_id" required>${templates.map(t=>`<option value="${t.id}">${esc(t.name)}</option>`).join('')}</select></label><label class="full">Internal notes<textarea name="notes" maxlength="5000" placeholder="Production notes…"></textarea></label><div class="form-actions"><button type="button" class="btn btn-ghost" data-close>Cancel</button><button class="btn btn-primary">Create website project</button></div></form>`;
    const m=modal({title:'Create website project from deal',body});
    m.querySelector('form').onsubmit=async e=>{
      e.preventDefault();
      const fd=new FormData(e.currentTarget);
      const data={...DEFAULT_BUSINESS_DATA,businessName:company.name||'',industry:company.industry||'',city:company.city||'',country:company.country||'',phone:company.phone||'',email:company.email||'',address:company.address||'',website:company.website||'',instagram:company.instagram||'',facebook:company.facebook||'',linkedin:company.linkedin||'',googleMapsUrl:company.google_maps_url||'',tagline:company.industry||'',heroTitle:company.name||'',heroText:company.description||''};
      const r=await db.from('website_projects').insert({lead_id:deal.lead_id,company_id:company.id,deal_id:deal.id,service_id:deal.service_id,template_id:fd.get('template_id'),status:'information_required',business_data:data,notes:String(fd.get('notes')||'').trim()||null}).select('id').single();
      if(r.error){toast(r.error.message,'error');return;}
      await recordActivity({type:'project_created',title:'Website project created from deal',lead_id:deal.lead_id,company_id:company.id,metadata:{project_id:r.data.id,deal_id:deal.id,service_id:deal.service_id}});
      toast('Website project created','success');m.remove();details(deal.id);
    };
    return;
  }
  if(serviceName.includes('qr')||serviceName.includes('review')){
    const templatesRes=await db.from('qr_templates').select('id,key,name').eq('active',true).order('name');
    if(templatesRes.error)throw templatesRes.error;
    const templates=templatesRes.data||[];
    if(!templates.length){toast('No active QR templates are configured.','error');return;}
    const body=`<form id="deal-project-form" class="form-grid"><div class="full info-list"><div><span>Company</span><strong>${esc(company.name||'—')}</strong></div><div><span>Service</span><strong>${esc(deal.services?.name||'Google Review QR')}</strong></div><div><span>Deal</span><strong>${money(deal.value,deal.currency)}</strong></div></div><label class="full">Google Review URL<input name="destination_url" type="url" required maxlength="2000" placeholder="https://search.google.com/local/writereview?…"></label><label>Template<select name="template_id" required>${templates.map(t=>`<option value="${t.id}">${esc(t.name)}</option>`).join('')}</select></label><label class="full">Internal notes<textarea name="notes" maxlength="5000" placeholder="Production notes…"></textarea></label><div class="form-actions"><button type="button" class="btn btn-ghost" data-close>Cancel</button><button class="btn btn-primary">Create QR project</button></div></form>`;
    const m=modal({title:'Create QR project from deal',body});
    m.querySelector('form').onsubmit=async e=>{
      e.preventDefault();
      const fd=new FormData(e.currentTarget);
      let url;try{url=validateDestinationUrl(fd.get('destination_url'))}catch(x){toast(x.message,'error');return;}
      const r=await db.from('qr_projects').insert({project_name:`Google Review QR — ${company.name||'Project'}`,created_by:null,lead_id:deal.lead_id,company_id:company.id,deal_id:deal.id,service_id:deal.service_id,template_id:fd.get('template_id'),destination_url:url,review_url:url,branding:{title:'Share your review',subtitle:'Scan to review our business',cta:'Scan to review',logoUrl:''},status:'draft',notes:String(fd.get('notes')||'').trim()||null}).select('id').single();
      if(r.error){toast(r.error.message,'error');return;}
      await recordActivity({type:'qr_project_created',title:'QR project created from deal',lead_id:deal.lead_id,company_id:company.id,metadata:{qr_project_id:r.data.id,deal_id:deal.id,service_id:deal.service_id}});
      toast('QR project created','success');m.remove();details(deal.id);
    };
    return;
  }
  toast('This service is not mapped to a production project yet.','error');
}

async function details(id){
  const db=supabaseClient();
  const d=await db.from('deals').select('*,leads(id,name,status,score,priority,company_id,companies(id,name,industry,city,phone,email,website)),services(id,name,price,currency)').eq('id',id).single();
  if(d.error)throw d.error;
  const [payments,websites,qrs,invoices]=await Promise.all([
    db.from('payments').select('id,amount,currency,status,payment_method,transaction_id,paid_at,milestone_type,created_at').eq('deal_id',id).order('created_at',{ascending:false}),
    db.from('website_projects').select('id,status,preview_url,client_approved_at,first_payment_at,delivery_status,updated_at').eq('deal_id',id).order('updated_at',{ascending:false}),
    db.from('qr_projects').select('id,status,destination_url,delivery_status,updated_at').eq('deal_id',id).order('updated_at',{ascending:false}),
    db.from('invoices').select('id,invoice_number,total,currency,status,due_date,created_at').eq('deal_id',id).order('created_at',{ascending:false})
  ]);
  const x=d.data,ps=payments.data||[],ws=websites.data||[],qsRows=qrs.data||[],inv=invoices.data||[];
  const paid=ps.filter(p=>p.status==='paid').reduce((a,p)=>a+Number(p.amount||0),0);
  const outstanding=Math.max(0,Number(x.value||0)-paid);
  const paymentState=paid>=Number(x.value||0)&&Number(x.value||0)>0?'Paid':paid>0?'Partial':'Pending';
  const hasProject=ws.length>0||qsRows.length>0;
  const serviceName=String(x.services?.name||'').toLowerCase();
  const canCreateProject=!hasProject&&(serviceName.includes('website')||serviceName.includes('qr')||serviceName.includes('review'));
  const body=`<div class="detail-grid">
    <section><span class="eyebrow">DEAL</span><div class="project-actions"><button class="btn btn-primary" id="create-project" ${canCreateProject?'':'disabled'}>${hasProject?'Project linked':serviceName.includes('qr')||serviceName.includes('review')?'Create QR project':'Create website project'}</button></div><h2>${esc(x.services?.name||'Deal')}</h2><div class="lead-kpis"><div><span>Value</span><strong>${money(x.value,x.currency)}</strong></div><div><span>Paid</span><strong>${money(paid,x.currency)}</strong></div><div><span>Outstanding</span><strong>${money(outstanding,x.currency)}</strong></div><div><span>Status</span><strong>${esc(x.status)}</strong></div></div><div class="info-list"><div><span>Company</span><strong>${esc(x.leads?.companies?.name||'—')}</strong></div><div><span>Lead</span><strong>${esc(x.leads?.name||'—')}</strong></div><div><span>Probability</span><strong>${Number(x.probability||0)}%</strong></div><div><span>Expected close</span><strong>${esc(x.expected_close_date||'—')}</strong></div><div><span>Payment</span><strong>${paymentState}</strong></div></div><p>${esc(x.notes||'No notes')}</p></section>
    <section><span class="eyebrow">PAYMENTS</span>${ps.map(p=>`<div class="list-row"><span><b>${money(p.amount,p.currency)}</b><small>${esc(p.milestone_type||'payment')} · ${esc(p.payment_method||'manual')}</small></span><em>${esc(p.status)}</em></div>`).join('')||'<p class="muted">No payments.</p>'}</section>
    <section><span class="eyebrow">WEBSITE PROJECTS</span>${ws.map(p=>`<div class="list-row"><span><b>Website</b><small>${esc(p.status)}${p.client_approved_at?' · approved':''}${p.first_payment_at?' · first payment':''}</small></span><em>${esc(p.delivery_status||'not_ready')}</em></div>`).join('')||'<p class="muted">No website projects.</p>'}<span class="eyebrow">QR PROJECTS</span>${qsRows.map(p=>`<div class="list-row"><span><b>QR Project</b><small>${esc(p.status)}</small></span><em>${esc(p.delivery_status||'not_ready')}</em></div>`).join('')||'<p class="muted">No QR projects.</p>'}</section>
    <section><span class="eyebrow">INVOICES</span>${inv.map(i=>`<div class="list-row"><span><b>${esc(i.invoice_number)}</b><small>${money(i.total,i.currency)} · due ${esc(i.due_date||'—')}</small></span><em>${esc(i.status)}</em></div>`).join('')||'<p class="muted">No invoices.</p>'}</section>
  </div>`;
  const m=modal({title:'Deal details',body});
  m.querySelector('#create-project')?.addEventListener('click',()=>createProjectFromDeal(x));
}

export async function render(){
  const host=qs('#page');host.innerHTML=loading('Loading deals…');
  const db=supabaseClient();
  const [r,pay]=await Promise.all([
    db.from('deals').select('id,lead_id,service_id,value,currency,status,probability,expected_close_date,updated_at,leads(id,name,status,companies(id,name)),services(name,price)'),
    db.from('payments').select('deal_id,amount,status')
  ]);
  if(r.error){host.innerHTML=emptyState('Deals unavailable',r.error.message);return}
  if(pay.error){host.innerHTML=emptyState('Deals unavailable',pay.error.message);return}
  const rows=r.data||[],payments=pay.data||[];
  const paidByDeal={};payments.filter(p=>p.status==='paid').forEach(p=>{paidByDeal[p.deal_id]=(paidByDeal[p.deal_id]||0)+Number(p.amount||0)});
  const totalValue=rows.reduce((a,d)=>a+Number(d.value||0),0),wonValue=rows.filter(d=>d.status==='won').reduce((a,d)=>a+Number(d.value||0),0),openValue=rows.filter(d=>['open','negotiating'].includes(d.status)).reduce((a,d)=>a+Number(d.value||0),0);
  host.innerHTML=`<div class="module-head"><div><span class="eyebrow">CRM / DEALS</span><h2>Deals</h2><p>Commercial records connected to leads, services, payments and production.</p></div><button class="btn btn-primary" id="new-deal">+ New deal</button></div>
  <div class="metrics metrics-compact"><article class="metric-card"><span>Total pipeline</span><strong>${money(totalValue)}</strong><small>${rows.length} deals</small></article><article class="metric-card"><span>Open / negotiating</span><strong>${money(openValue)}</strong><small>Active pipeline</small></article><article class="metric-card"><span>Won value</span><strong>${money(wonValue)}</strong><small>Closed won</small></article><article class="metric-card"><span>Paid against deals</span><strong>${money(Object.values(paidByDeal).reduce((a,v)=>a+v,0))}</strong><small>Paid payments only</small></article></div>
  <section class="table-card"><table><thead><tr><th>Company</th><th>Lead</th><th>Service</th><th>Value</th><th>Paid</th><th>Outstanding</th><th>Status</th><th>Probability</th><th>Close</th><th></th></tr></thead><tbody>${rows.map(d=>{const paid=paidByDeal[d.id]||0;const outstanding=Math.max(0,Number(d.value||0)-paid);return `<tr><td>${esc(d.leads?.companies?.name||'—')}</td><td><button class="link-btn" data-view="${d.id}">${esc(d.leads?.name||'—')}</button></td><td>${esc(d.services?.name||'—')}</td><td>${money(d.value,d.currency)}</td><td>${money(paid,d.currency)}</td><td>${money(outstanding,d.currency)}</td><td><span class="badge">${esc(d.status)}</span></td><td>${Number(d.probability||0)}%</td><td>${esc(d.expected_close_date||'—')}</td><td><button class="icon-btn" data-edit="${d.id}">✎</button></td></tr>`}).join('')||`<tr><td colspan="10">${emptyState('No deals','Create a deal from a qualified lead to start the commercial workflow.')}</td></tr>`}</tbody></table></section>`;
  qs('#new-deal').onclick=()=>openForm();
  host.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>details(b.dataset.view));
  host.querySelectorAll('[data-edit]').forEach(b=>b.onclick=async()=>{const x=await db.from('deals').select('*').eq('id',b.dataset.edit).single();if(x.error)return toast(x.error.message,'error');openForm(x.data)});
}
