import {supabaseClient} from './db.js';
import {toast,loading,emptyState,modal} from './ui.js';
import {escapeHtml,qs} from './utils.js';
import {recordActivity} from './activity.js';

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
        lead_id:String(fd.get('lead_id')||''),
        service_id:String(fd.get('service_id')||''),
        value:Number(fd.get('value')),
        currency:String(fd.get('currency')||'MAD').trim().toUpperCase(),
        status:String(fd.get('status')||'open'),
        probability:Number(fd.get('probability')||0),
        expected_close_date:String(fd.get('expected_close_date')||'')||null,
        notes:String(fd.get('notes')||'').trim()||null
      };
      if(!payload.lead_id||!payload.service_id||!Number.isFinite(payload.value)||payload.value<0||!Number.isInteger(payload.probability)||payload.probability<0||payload.probability>100||!/^[A-Z]{3}$/.test(payload.currency)||!statuses.includes(payload.status))return toast('Check the deal fields.','error');
      const db=supabaseClient();
      const r=existing.id?await db.from('deals').update(payload).eq('id',existing.id).select('*,leads(name,company_id),services(name)').single():await db.from('deals').insert(payload).select('*,leads(name,company_id),services(name)').single();
      if(r.error)throw r.error;
      await recordActivity({type:existing.id?'deal_updated':'deal_created',title:existing.id?'Deal updated':'Deal created',description:`${r.data.services?.name||'Deal'} · ${r.data.leads?.name||''}`,lead_id:r.data.lead_id,metadata:{deal_id:r.data.id,value:r.data.value,currency:r.data.currency,status:r.data.status}});
      toast(existing.id?'Deal updated':'Deal created','success');m.remove();render();
    });
  }catch(e){toast(e.message||'Unable to open deal form','error')}
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
  const x=d.data, ps=payments.data||[], ws=websites.data||[], qsRows=qrs.data||[], inv=invoices.data||[];
  const paid=ps.filter(p=>p.status==='paid').reduce((a,p)=>a+Number(p.amount||0),0);
  const outstanding=Math.max(0,Number(x.value||0)-paid);
  const paymentState=paid>=Number(x.value||0)&&Number(x.value||0)>0?'Paid':paid>0?'Partial':'Pending';
  const body=`<div class="detail-grid">
    <section><span class="eyebrow">DEAL</span><h2>${esc(x.services?.name||'Deal')}</h2><div class="lead-kpis"><div><span>Value</span><strong>${money(x.value,x.currency)}</strong></div><div><span>Paid</span><strong>${money(paid,x.currency)}</strong></div><div><span>Outstanding</span><strong>${money(outstanding,x.currency)}</strong></div><div><span>Status</span><strong>${esc(x.status)}</strong></div></div><div class="info-list"><div><span>Company</span><strong>${esc(x.leads?.companies?.name||'—')}</strong></div><div><span>Lead</span><strong>${esc(x.leads?.name||'—')}</strong></div><div><span>Probability</span><strong>${Number(x.probability||0)}%</strong></div><div><span>Expected close</span><strong>${esc(x.expected_close_date||'—')}</strong></div><div><span>Payment</span><strong>${paymentState}</strong></div></div><p>${esc(x.notes||'No notes')}</p></section>
    <section><span class="eyebrow">PAYMENTS</span>${ps.map(p=>`<div class="list-row"><span><b>${money(p.amount,p.currency)}</b><small>${esc(p.milestone_type||'payment')} · ${esc(p.payment_method||'manual')}</small></span><em>${esc(p.status)}</em></div>`).join('')||'<p class="muted">No payments.</p>'}</section>
    <section><span class="eyebrow">WEBSITE PROJECTS</span>${ws.map(p=>`<div class="list-row"><span><b>Website</b><small>${esc(p.status)}${p.client_approved_at?' · approved':''}${p.first_payment_at?' · first payment':''}</small></span><em>${esc(p.delivery_status||'not_ready')}</em></div>`).join('')||'<p class="muted">No website projects.</p>'}<span class="eyebrow">QR PROJECTS</span>${qsRows.map(p=>`<div class="list-row"><span><b>QR Project</b><small>${esc(p.status)}</small></span><em>${esc(p.delivery_status||'not_ready')}</em></div>`).join('')||'<p class="muted">No QR projects.</p>'}</section>
    <section><span class="eyebrow">INVOICES</span>${inv.map(i=>`<div class="list-row"><span><b>${esc(i.invoice_number)}</b><small>${money(i.total,i.currency)} · due ${esc(i.due_date||'—')}</small></span><em>${esc(i.status)}</em></div>`).join('')||'<p class="muted">No invoices.</p>'}</section>
  </div>`;
  modal({title:'Deal details',body});
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
  const rows=r.data||[], payments=pay.data||[];
  const paidByDeal={};payments.filter(p=>p.status==='paid').forEach(p=>{paidByDeal[p.deal_id]=(paidByDeal[p.deal_id]||0)+Number(p.amount||0)});
  const totalValue=rows.reduce((a,d)=>a+Number(d.value||0),0),wonValue=rows.filter(d=>d.status==='won').reduce((a,d)=>a+Number(d.value||0),0),openValue=rows.filter(d=>['open','negotiating'].includes(d.status)).reduce((a,d)=>a+Number(d.value||0),0);
  host.innerHTML=`<div class="module-head"><div><span class="eyebrow">CRM / DEALS</span><h2>Deals</h2><p>Commercial records connected to leads, services, payments and production.</p></div><button class="btn btn-primary" id="new-deal">+ New deal</button></div>
  <div class="metrics metrics-compact"><article class="metric-card"><span>Total pipeline</span><strong>${money(totalValue)}</strong><small>${rows.length} deals</small></article><article class="metric-card"><span>Open / negotiating</span><strong>${money(openValue)}</strong><small>Active pipeline</small></article><article class="metric-card"><span>Won value</span><strong>${money(wonValue)}</strong><small>Closed won</small></article><article class="metric-card"><span>Paid against deals</span><strong>${money(Object.values(paidByDeal).reduce((a,v)=>a+v,0))}</strong><small>Paid payments only</small></article></div>
  <section class="table-card"><table><thead><tr><th>Company</th><th>Lead</th><th>Service</th><th>Value</th><th>Paid</th><th>Outstanding</th><th>Status</th><th>Probability</th><th>Close</th><th></th></tr></thead><tbody>${rows.map(d=>{const paid=paidByDeal[d.id]||0;const outstanding=Math.max(0,Number(d.value||0)-paid);return `<tr><td>${esc(d.leads?.companies?.name||'—')}</td><td><button class="link-btn" data-view="${d.id}">${esc(d.leads?.name||'—')}</button></td><td>${esc(d.services?.name||'—')}</td><td>${money(d.value,d.currency)}</td><td>${money(paid,d.currency)}</td><td>${money(outstanding,d.currency)}</td><td><span class="badge">${esc(d.status)}</span></td><td>${Number(d.probability||0)}%</td><td>${esc(d.expected_close_date||'—')}</td><td><button class="icon-btn" data-edit="${d.id}">✎</button></td></tr>`}).join('')||`<tr><td colspan="10">${emptyState('No deals','Create a deal from a qualified lead to start the commercial workflow.')}</td></tr>`}</tbody></table></section>`;
  qs('#new-deal').onclick=()=>openForm();
  host.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>details(b.dataset.view));
  host.querySelectorAll('[data-edit]').forEach(async b=>b.onclick=async()=>{const x=await db.from('deals').select('*').eq('id',b.dataset.edit).single();if(x.error)return toast(x.error.message,'error');openForm(x.data)});
}
