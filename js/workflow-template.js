import {supabaseClient} from './db.js';
import {getCurrentUser} from './auth.js';
import {toast} from './ui.js';

const db=()=>supabaseClient();
let mounted=false;

async function installAiDraftWorkflow(button){
  if(button.disabled)return;
  button.disabled=true;
  button.textContent='Installing…';
  try{
    await getCurrentUser();
    const {data,error}=await db().rpc('create_ai_draft_workflow');
    if(error)throw error;
    toast('AI Draft workflow is active','success');
    button.textContent='✓ AI Draft workflow active';
    button.classList.remove('btn-primary');
    button.classList.add('btn-ghost');
    window.dispatchEvent(new CustomEvent('workflow-template-installed',{detail:{workflowId:data}}));
  }catch(error){
    console.warn('[workflow-template]',error);
    toast(error?.message||'Could not install workflow','error');
    button.disabled=false;
    button.textContent='⚡ Install AI Draft workflow';
  }
}

function mount(){
  if(mounted)return;
  const page=document.querySelector('#page');
  if(!page)return;
  const heading=page.querySelector('h2');
  if(!heading||!heading.textContent.includes('Workflow Builder'))return;
  mounted=true;
  const header=page.querySelector('.module-head');
  if(!header)return;
  const button=document.createElement('button');
  button.type='button';
  button.className='btn btn-primary';
  button.textContent='⚡ Install AI Draft workflow';
  button.title='New lead message → AI draft → human approval';
  button.onclick=()=>installAiDraftWorkflow(button);
  header.appendChild(button);
}

const observer=new MutationObserver(mount);
if(document.body)observer.observe(document.body,{childList:true,subtree:true});
setTimeout(mount,0);
