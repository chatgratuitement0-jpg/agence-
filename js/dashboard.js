import {supabaseClient} from './db.js';

async function countIsNull(table, column) { const r = await supabaseClient().from(table).select('id', { count: 'exact', head: true }).is(column, null); if (r.error) throw r.error; return r.count || 0; }
async function countNotIn(table, column, values) { const r = await supabaseClient().from(table).select('id', { count: 'exact', head: true }).not(column, 'in', `(${values.join(',')})`); if (r.error) throw r.error; return r.count || 0; }

async function count(table, filter) {
  let q = supabaseClient().from(table).select('id', { count: 'exact', head: true });
  if (filter) q = q.eq(filter[0], filter[1]);
  const r = await q;
  if (r.error) throw r.error;
  return r.count || 0;
}

export async function getDashboardMetrics() {
  const [totalCompanies,totalLeads,newLeads,qualifiedLeads,interestedLeads,negotiatingLeads,paymentPending,wonDeals,lostLeads,activeConversations,activeWebsiteProjects,awaitingApproval,readyForDelivery,qrProjects,activeQrProjects,revisionRequests,pendingFollowUps,pendingAiApprovals,humanHandoffs] = await Promise.all([
    count('companies'), count('leads'), count('leads',['status','new']), count('leads',['status','qualified']), count('leads',['status','interested']), count('leads',['status','negotiating']), count('leads',['status','payment']), count('deals',['status','won']), count('leads',['status','lost']), count('conversations',['status','active']), countNotIn('website_projects','status',['delivered','completed','cancelled','archived']), count('website_projects',['status','client_review']), count('website_projects',['status','ready_for_delivery']), countNotIn('qr_projects','status',['archived']), count('qr_projects',['status','active']), count('website_revision_requests',['status','requested']), count('follow_ups',['status','pending']), count('ai_decisions',['approval_status','pending']), countIsNull('conversation_handoffs','resolved_at')
  ]);
  const paymentResult = await supabaseClient().from('payments').select('amount,status');
  if (paymentResult.error) throw paymentResult.error;
  const payments = paymentResult.data || [];
  const paidRevenue = payments.filter(p => p.status === 'paid').reduce((sum,p) => sum + Number(p.amount || 0), 0);
  const pendingRevenue = payments.filter(p => ['pending','authorized'].includes(p.status)).reduce((sum,p) => sum + Number(p.amount || 0), 0);
  const summary = await supabaseClient().from('deal_payment_summary').select('outstanding_amount');
  if (summary.error) throw summary.error;
  const outstandingBalance = (summary.data || []).reduce((sum,d) => sum + Number(d.outstanding_amount || 0), 0);
  const [pendingPayments,failedPayments,readyDeliveries,blockedDeliveries,deliveredProjects,issuedInvoices,partialInvoices,overdueInvoices] = await Promise.all([
    count('payments',['status','pending']), count('payments',['status','failed']), count('deliveries',['delivery_status','ready']), count('deliveries',['delivery_status','not_ready']), count('deliveries',['delivery_status','delivered']), count('invoices',['status','issued']), count('invoices',['status','partially_paid']), count('invoices',['status','overdue'])
  ]);
  return {totalCompanies,totalLeads,newLeads,qualifiedLeads,interestedLeads,negotiatingLeads,paymentPending,wonDeals,lostLeads,activeConversations,activeWebsiteProjects,awaitingApproval,readyForDelivery,qrProjects,activeQrProjects,revisionRequests,pendingFollowUps,pendingAiApprovals,humanHandoffs,paidRevenue,revenue:paidRevenue,pendingRevenue,outstandingBalance,pendingPayments,failedPayments,readyDeliveries,blockedDeliveries,deliveredProjects,outstandingInvoices:issuedInvoices+partialInvoices+overdueInvoices};
}

export async function getRecentActivities(limit=12){return supabaseClient().from('activities').select('id,type,title,description,created_at,lead_id,company_id').order('created_at',{ascending:false}).limit(limit)}
export async function getPipeline(){const statuses=['new','qualified','interested','negotiating','payment','won','lost'];const out={};for(const s of statuses){const r=await supabaseClient().from('leads').select('id',{count:'exact',head:true}).eq('status',s);if(r.error)throw r.error;out[s]=r.count||0}return out}
