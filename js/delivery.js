import {supabaseClient} from './db.js';
import {toast,loading,emptyState,modal} from './ui.js';
import {escapeHtml} from './utils.js';

const esc=v=>escapeHtml(v??'');
const reasonLabel={pending:'Waiting for payment',partial:'Waiting for final payment',paid:'Paid',not_required:'No payment required'};
const statusLabel=s=>String(s||'—').replaceAll('_',' ');

async function rows(){
  return supabaseClient()
    .from('deliveries')
    .select('id,type,website_project_id,qr_project_id,company_id,lead_id,deal_id,delivery_status,payment_status,approval_status,production_status,delivered_at,download_count,responsible_user_id,notes,created_at,updated_at,companies(name),leads(name),deals(value,currency),website_projects(project_name,status),qr_projects(project_name,status)')
    .order('updated_at',{ascending:false})
    .limit(200);
}

async function refreshProject(type,id){
  const r=await supabaseClient().rpc('get_delivery_gate',{p_type:type,p_project_id:id});
  if(r.error)throw r.error;
  return Array.isArray(r.data)?r.data[0]:r.data;
}

function money(value,currency='MAD'){
  return `${Number(value||0).toLocaleString()} ${esc(currency||'MAD')}`;
}

async function details(d){
  const id=d.type==='Website'?d.website_project_id:d.qr_project_id;
  let gate;
  try{gate=await refreshProject(d.type,id)}catch(e){return toast(e.message,'error')}

  const projectName=d.type==='Website'
    ? d.website_projects?.project_name||'Website project'
    : d.qr_projects?.project_name||'QR project';
  const projectStatus=d.type==='Website'?d.website_projects?.status:d.qr_projects?.status;
  const currency=d.deals?.currency||'MAD';

  const body=`
    <section class="detail-grid">
      <section>
        <span class="eyebrow">DELIVERY</span>
        <h3>${esc(projectName)}</h3>
        <p class="muted">${esc(d.type)} · ${esc(d.companies?.name||'No company')} · ${esc(d.leads?.name||'No lead')}</p>
        <div class="info-list">
          <div><span>Project status</span><strong>${esc(statusLabel(projectStatus))}</strong></div>
          <div><span>Delivery status</span><strong>${esc(statusLabel(d.delivery_status))}</strong></div>
          <div><span>Downloads</span><strong>${Number(d.download_count||0)}</strong></div>
        </div>
      </section>
      <section>
        <span class="eyebrow">SERVER-SIDE GATE</span>
        <div class="gate-list">
          <div class="gate ${gate.allowed?'passed':'blocked'}"><b>${gate.allowed?'✓':'○'}</b><span>${esc(gate.reason)}</span></div>
          <div class="gate ${gate.payment_status==='paid'||gate.payment_status==='not_required'?'passed':'blocked'}"><b>₿</b><span>Payment: ${esc(reasonLabel[gate.payment_status]||gate.payment_status)} · Paid ${money(gate.paid_amount,currency)} · Outstanding ${money(gate.outstanding_amount,currency)}</span></div>
          <div class="gate ${gate.approval_status==='approved'||gate.approval_status==='not_required'?'passed':'blocked'}"><b>✓</b><span>Approval: ${esc(statusLabel(gate.approval_status))}</span></div>
          <div class="gate ${gate.production_status==='ready'?'passed':'blocked'}"><b>•</b><span>Production: ${esc(statusLabel(gate.production_status))}</span></div>
        </div>
      </section>
    </section>
    <div class="form-actions">
      ${gate.allowed&&d.delivery_status!=='delivered'?'<button class="btn btn-primary" data-authorize>Authorize download</button>':''}
      ${gate.allowed&&['ready','downloaded'].includes(d.delivery_status)?'<button class="btn btn-ghost" data-complete>Mark delivered</button>':''}
      ${!gate.allowed?'<button class="btn btn-ghost" data-refresh>Refresh gate</button>':''}
    </div>
    <p class="muted">Delivery is controlled by the database gate. Completing delivery also synchronizes the linked project to <b>delivered</b>.</p>`;

  const m=modal({title:'Delivery details',body});
  m.querySelector('[data-refresh]')?.addEventListener('click',()=>{m.remove();details(d)});
  m.querySelector('[data-authorize]')?.addEventListener('click',async()=>{
    const r=await supabaseClient().rpc('authorize_delivery_download',{p_type:d.type,p_project_id:id});
    if(r.error)return toast(r.error.message,'error');
    toast('Delivery authorized','success');
    m.remove();
    render();
  });
  m.querySelector('[data-complete]')?.addEventListener('click',async()=>{
    const r=await supabaseClient().rpc('complete_delivery',{p_delivery_id:d.id});
    if(r.error)return toast(r.error.message,'error');
    toast('Delivery completed and project synchronized','success');
    m.remove();
    render();
  });
}

export async function render(){
  const host=document.querySelector('#page');
  host.innerHTML=loading('Loading Delivery Center…');
  const r=await rows();
  if(r.error){host.innerHTML=emptyState('Delivery unavailable',r.error.message);return}
  const data=r.data||[];
  const ready=data.filter(x=>x.delivery_status==='ready').length;
  const blocked=data.filter(x=>x.delivery_status==='not_ready').length;
  const delivered=data.filter(x=>x.delivery_status==='delivered').length;
  const downloaded=data.filter(x=>x.delivery_status==='downloaded').length;

  host.innerHTML=`
    <div class="module-head">
      <div>
        <span class="eyebrow">OPERATIONS / DELIVERY</span>
        <h2>Delivery Center</h2>
        <p>Only approved, paid and production-ready projects can be authorized for delivery.</p>
      </div>
    </div>
    <div class="metrics metrics-compact">
      <article class="metric-card"><span>Ready</span><strong>${ready}</strong></article>
      <article class="metric-card"><span>Blocked</span><strong>${blocked}</strong></article>
      <article class="metric-card"><span>Downloaded</span><strong>${downloaded}</strong></article>
      <article class="metric-card"><span>Delivered</span><strong>${delivered}</strong></article>
    </div>
    <section class="table-card">
      <table>
        <thead><tr><th>Project</th><th>Company</th><th>Type</th><th>Payment</th><th>Approval</th><th>Production</th><th>Delivery</th><th>Date</th><th></th></tr></thead>
        <tbody>
          ${data.map(d=>{
            const name=d.type==='Website'?d.website_projects?.project_name:d.qr_projects?.project_name;
            return `<tr>
              <td><button class="link-btn" data-delivery="${d.id}">${esc(name||`${d.type} project`)}</button></td>
              <td>${esc(d.companies?.name||'—')}</td>
              <td>${esc(d.type)}</td>
              <td>${esc(statusLabel(d.payment_status))}</td>
              <td>${esc(statusLabel(d.approval_status))}</td>
              <td>${esc(statusLabel(d.production_status))}</td>
              <td><span class="badge">${esc(statusLabel(d.delivery_status))}</span></td>
              <td>${d.updated_at?new Date(d.updated_at).toLocaleDateString():'—'}</td>
              <td><button class="icon-btn" data-delivery="${d.id}">→</button></td>
            </tr>`;
          }).join('')||`<tr><td colspan="9">${emptyState('No delivery records','Website and QR projects will appear here as they are created.')}</td></tr>`}
        </tbody>
      </table>
    </section>`;

  host.querySelectorAll('[data-delivery]').forEach(b=>b.onclick=()=>{
    const item=data.find(x=>x.id===b.dataset.delivery);
    if(item)details(item);
  });
}
