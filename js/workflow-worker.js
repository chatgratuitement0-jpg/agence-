import {supabaseClient} from './db.js';
import {toast} from './ui.js';

const db=()=>supabaseClient();
let running=false;

export async function processQueuedWorkflows({limit=10,silent=true}={}){
  if(running)return {skipped:true,reason:'worker_already_running'};
  running=true;
  try{
    const {data,error}=await db().rpc('process_queued_workflow_executions',{p_limit:Math.min(20,Math.max(1,Number(limit)||10))});
    if(error)throw error;
    const rows=data||[];
    const result={processed:rows.length,rows};
    if(!silent&&rows.length)toast(`Processed ${rows.length} workflow execution${rows.length===1?'':'s'}`,'success');
    return result;
  }catch(error){
    console.warn('[workflow-worker]',error);
    if(!silent)toast(error?.message||'Workflow worker failed','error');
    return {processed:0,error};
  }finally{running=false;}
}

let timer=null;
export function startWorkflowWorker({intervalMs=15000}={}){
  if(timer)return;
  processQueuedWorkflows({silent:true});
  timer=setInterval(()=>processQueuedWorkflows({silent:true}),Math.max(10000,Number(intervalMs)||15000));
}
export function stopWorkflowWorker(){if(timer){clearInterval(timer);timer=null;}}
