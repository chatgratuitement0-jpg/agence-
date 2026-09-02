import {supabaseClient} from './db.js';
import {toast,loading,emptyState} from './ui.js';
import {escapeHtml} from './utils.js';

const db=()=>supabaseClient();
const esc=v=>escapeHtml(v??'');
const statuses=['all','pending','approved','rejected','sent','cancelled'];
let mounted=false;
let filter='pending';

async function loadDrafts(){
 let q=db().from('ai_response_drafts').select('id,lead_id,conversation_id,subject,body,status,knowledge_refs,created_at,updated_at,leads(name,companies(name)),conversations(subject,channel)').order('created_at',{ascending:false}).limit(100);
 if(filter!=='all')q=q.eq('status',filter);
 const r=await q;if(r.error)throw r.error;return r.data||[];
}

async function setStatus(id,status){
 const r=await db().from('ai_response_drafts').update({status,updated_at:new Date().toISOString()}).eq('id',id).select('id').single();
 if(r.error)throw r.error;
}

async function publish(id){
 const r=await db().rpc('publish_ai_response_draft',{p_draft_id:id});
 if(r.error)throw r.error;
}

function card(d){
 const refs=Array.isArray(d.knowledge_refs)?d.knowledge_refs:[];
 const lead=d.leads?.name||'Lead';
 const company=d.leads?.companies?.name||'Company';
 const channel=d.conversations?.channel||'internal';
 return `<article class="card ai-draft-card"><div class="card-head"><div><span class="eyebrow">AI RESPONSE DRAFT</span><h3>${esc(d.subject||'Response draft')}</h3><p class="muted">${esc(lead)} · ${esc(company)} · ${esc(channel)}</p></div><span class="badge">${esc(d.status)}</span></div><div class="draft-body"><p>${esc(d.body).replace(/\n/g,'<br>')}</p></div>${refs.length?`<details><summary>Knowledge used (${refs.length})</summary><div class="mini-list">${refs.map(x=>`<div class="list-row"><span><b>${esc(x.title)}</b><small>${esc(x.category)}</small></span></div>`).join('')}</div></details>`:''}<div class="project-actions">${d.status==='pending'?`<button class="btn btn-primary" data-draft="approve" data-id="${d.id}">Approve</button><button class="btn btn-ghost" data-draft="reject" data-id="${d.id}">Reject</button>`:''}${d.status==='approved'&&d.conversation_id?`<button class="btn btn-primary" data-draft="publish" data-id="${d.id}">Publish internally</button>`:''}${d.status==='sent'?`<span class="muted">Published to CRM conversation</span>`:''}</div><small class="muted">Created ${new Date(d.created_at).toLocaleString()}</small></article>`;
}

async function render(){
 const host=document.querySelector('[data-ai-drafts-host]');if(!host)return;
 host.innerHTML=loading('Loading AI response drafts…');
 try{
  const rows=await loadDrafts();
  host.innerHTML=`<div class="toolbar"><label>Status <select id="ai-draft-filter">${statuses.map(s=>`<option value="${s}" ${filter===s?'selected':''}>${s}</option>`).join('')}</select></label></div><div class="grid-2">${rows.map(card).join('')||emptyState('No response drafts','Generate a draft from a conversation or an automation workflow.')}</div>`;
  host.querySelector('#ai-draft-filter').onchange=e=>{filter=e.target.value;render()};
  host.querySelectorAll('[data-draft]').forEach(btn=>btn.onclick=async()=>{
   btn.disabled=true;
   try{
    const action=btn.dataset.draft;
    if(action==='approve')await setStatus(btn.dataset.id,'approved');
    else if(action==='reject')await setStatus(btn.dataset.id,'rejected');
    else await publish(btn.dataset.id);
    toast(action==='publish'?'Draft published internally':'Draft updated','success');
    render();
   }catch(e){toast(e.message||'Draft action failed','error');btn.disabled=false;}
  });
 }catch(e){host.innerHTML=emptyState('AI drafts unavailable',e.message);}
}

function mount(){
 if(mounted)return;
 const page=document.querySelector('#page');
 if(!page)return;
 const heading=[...page.querySelectorAll('h1,h2,h3')].find(x=>/AI Agent|AI Decision/i.test(x.textContent||''));
 if(!heading)return;
 const host=document.createElement('section');
 host.className='module-section';
 host.innerHTML='<div class="module-head"><div><span class="eyebrow">AI COMMUNICATION</span><h2>AI Response Drafts</h2><p>Review AI-generated responses before they are published into CRM conversations.</p></div></div><div data-ai-drafts-host></div>';
 page.appendChild(host);mounted=true;render();
}

const observer=new MutationObserver(()=>{mounted=false;mount()});
observer.observe(document.body,{childList:true,subtree:true});
setTimeout(mount,250);
export {render as renderAIDrafts};
