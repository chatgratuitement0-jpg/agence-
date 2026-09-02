import {createRow,supabaseClient} from './db.js';
import {getCurrentUser} from './auth.js';
import {emitWorkflowEvent} from './workflow-events.js';

const EVENT_MAP={
  lead_created:'lead_created',
  lead_status_changed:'lead_status_changed',
  deal_created:'deal_created',
  payment_received:'payment_received',
  human_handoff:'human_handoff',
  new_conversation:'new_conversation',
  new_message:'new_message',
  website_preview_ready:'website_preview_ready',
  website_approved:'website_approved',
  followup_due:'followup_due',
  campaign_completed:'campaign_completed'
};

export async function recordActivity({type,title,description='',lead_id=null,company_id=null,metadata={}}){
  const user=await getCurrentUser();
  if(!user)throw new Error('Authentication required.');
  const {data,error}=await createRow('activities',{user_id:user.id,lead_id,company_id,type,title,description,metadata});
  if(error)throw error;

  const trigger=EVENT_MAP[type];
  if(trigger){
    emitWorkflowEvent({
      trigger,
      leadId:lead_id,
      companyId:company_id,
      eventId:data.id,
      fields:{
        ...(metadata||{}),
        activity_type:type,
        title:title||'',
        description:description||''
      }
    }).catch(()=>{});
  }
  return data;
}

export async function listActivities({leadId=null,companyId=null,limit=30}={}){
  let q=supabaseClient().from('activities').select('id,type,title,description,metadata,created_at,user_id').order('created_at',{ascending:false}).limit(limit);
  if(leadId)q=q.eq('lead_id',leadId);else if(companyId)q=q.eq('company_id',companyId);
  return q;
}
