import {supabaseClient} from './db.js';
import {getCurrentUser} from './auth.js';

const db=()=>supabaseClient();

/** Queue active CRM workflows for a real CRM event. Execution remains safe and idempotent. */
export async function emitWorkflowEvent({trigger,leadId=null,companyId=null,conversationId=null,eventId=null,fields={}}={}){
  const user=await getCurrentUser();
  if(!user?.id) return {queued:[],skipped:'not_authenticated'};
  if(!trigger) throw new Error('Workflow trigger is required.');
  const {data,error}=await db().rpc('run_active_workflows_for_event',{
    p_trigger_type:trigger,
    p_lead_id:leadId,
    p_company_id:companyId,
    p_conversation_id:conversationId,
    p_event_id:eventId,
    p_fields:fields||{}
  });
  if(error) throw error;
  return {queued:Array.isArray(data)?data:[],trigger};
}

export const WORKFLOW_EVENTS={
  LEAD_CREATED:'lead_created',
  LEAD_STATUS_CHANGED:'lead_status_changed',
  NEW_MESSAGE:'new_message',
  NEW_CONVERSATION:'new_conversation',
  FOLLOWUP_DUE:'followup_due',
  WEBSITE_PREVIEW_READY:'website_preview_ready',
  WEBSITE_APPROVED:'website_approved',
  PAYMENT_RECEIVED:'payment_received',
  DEAL_CREATED:'deal_created',
  HUMAN_HANDOFF:'human_handoff',
  CAMPAIGN_COMPLETED:'campaign_completed'
};
