import {createRow,supabaseClient} from './db.js';
import {getCurrentUser} from './auth.js';
export async function recordActivity({type,title,description='',lead_id=null,company_id=null,metadata={}}){const user=await getCurrentUser();if(!user)throw new Error('Authentication required.');const{data,error}=await createRow('activities',{user_id:user.id,lead_id,company_id,type,title,description,metadata});if(error)throw error;return data}
export async function listActivities({leadId=null,companyId=null,limit=30}={}){let q=supabaseClient().from('activities').select('id,type,title,description,metadata,created_at,user_id').order('created_at',{ascending:false}).limit(limit);if(leadId)q=q.eq('lead_id',leadId);else if(companyId)q=q.eq('company_id',companyId);return q}
