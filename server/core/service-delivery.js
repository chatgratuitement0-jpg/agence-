import { getAdminDb } from './db.js';

const WEBSITE_SERVICE_HINTS = ['website', 'site', 'web', 'website generation'];
const QR_SERVICE_HINTS = ['qr', 'qrcode', 'qr code'];

function serviceText(service) { return `${service?.name || ''} ${service?.description || ''}`.toLowerCase(); }
function looksLikeWebsiteService(service) { return WEBSITE_SERVICE_HINTS.some(hint => serviceText(service).includes(hint)); }
function looksLikeQrService(service) { return QR_SERVICE_HINTS.some(hint => serviceText(service).includes(hint)); }

export async function startApprovedService({ taskId, userId }) {
  const db = getAdminDb();
  const { data: task, error: taskError } = await db.from('sales_agent_tasks').select('*').eq('id', taskId).single();
  if (taskError || !task) throw new Error('Service task not found');
  if (task.task_type !== 'start_service') throw new Error('Task is not a service-start task');
  if (task.status !== 'pending' || task.requires_human) throw new Error('Service task is not ready to start');

  const { data: lead, error: leadError } = await db.from('leads').select('id,name,owner_id,company_id,recommended_service').eq('id', task.lead_id).single();
  if (leadError || !lead) throw new Error('Lead not found');
  if (lead.owner_id !== userId) throw new Error('Not authorized');

  const requestedServiceId = task.payload?.service_id || null;
  let service = null;
  if (requestedServiceId) {
    const { data } = await db.from('services').select('*').eq('id', requestedServiceId).eq('active', true).single();
    service = data;
  }
  if (!service && lead.recommended_service) {
    const { data } = await db.from('services').select('*').eq('active', true).ilike('name', `%${lead.recommended_service}%`).limit(1).maybeSingle();
    service = data;
  }
  if (!service) throw new Error('No active service could be resolved for this lead');

  const websiteService = looksLikeWebsiteService(service);
  const qrService = looksLikeQrService(service);
  const supportedDeliveryService = websiteService || qrService;

  const { data: existingDeal } = await db.from('deals').select('*').eq('lead_id', lead.id).eq('service_id', service.id).in('status', ['open', 'negotiating', 'won']).order('created_at', { ascending: false }).limit(1).maybeSingle();
  let deal = existingDeal;
  if (!deal) {
    const { data: createdDeal, error } = await db.from('deals').insert({ lead_id: lead.id, service_id: service.id, value: service.price, currency: service.currency, status: 'won', probability: 100, notes: 'Created from approved start_service task' }).select().single();
    if (error) throw new Error(`Could not create deal: ${error.message}`);
    deal = createdDeal;
  }

  const firstAmount = Number(task.payload?.first_payment_amount ?? Math.ceil(Number(service.price) / 2));
  if (!Number.isFinite(firstAmount) || firstAmount <= 0) throw new Error('First payment amount must be positive');
  const remainingAmount = Math.max(0, Number(service.price) - firstAmount);

  const { data: existingMilestone } = await db.from('payment_milestones').select('*').eq('deal_id', deal.id).eq('milestone_type', 'deposit').maybeSingle();
  let firstMilestone = existingMilestone;
  if (!firstMilestone) {
    const { data, error } = await db.from('payment_milestones').insert({ deal_id: deal.id, website_project_id: websiteService ? null : null, qr_project_id: qrService ? null : null, milestone_type: 'deposit', label: 'First payment', amount: firstAmount, currency: service.currency, status: 'pending', notes: 'Required before final package delivery' }).select().single();
    if (error) throw new Error(`Could not create first payment milestone: ${error.message}`);
    firstMilestone = data;
  }

  if (remainingAmount > 0) {
    const { data: existingRemaining } = await db.from('payment_milestones').select('id').eq('deal_id', deal.id).eq('milestone_type', 'remaining_balance').maybeSingle();
    if (!existingRemaining) {
      const { error } = await db.from('payment_milestones').insert({ deal_id: deal.id, milestone_type: 'remaining_balance', label: 'Remaining payment', amount: remainingAmount, currency: service.currency, status: 'pending', notes: 'Due after final approval/delivery' });
      if (error) throw new Error(`Could not create remaining payment milestone: ${error.message}`);
    }
  }

  let websiteProject = null;
  if (websiteService) {
    const { data: existingProject } = await db.from('website_projects').select('*').eq('deal_id', deal.id).maybeSingle();
    if (existingProject) websiteProject = existingProject;
    else {
      const { data, error } = await db.from('website_projects').insert({ lead_id: lead.id, company_id: lead.company_id, service_id: service.id, deal_id: deal.id, status: 'payment_pending', business_data: { lead_name: lead.name, service_name: service.name }, project_data: {}, delivery_status: 'not_ready', notes: 'Service started. Preview can be generated; final package requires client approval and first payment.' }).select().single();
      if (error) throw new Error(`Could not create website project: ${error.message}`);
      websiteProject = data;
    }
  }

  let deliveryRow = null;
  if (supportedDeliveryService) {
    const { data: delivery, error: deliveryError } = await db.from('deliveries').select('*').eq('deal_id', deal.id).maybeSingle();
    if (deliveryError) throw new Error(`Could not read delivery: ${deliveryError.message}`);
    deliveryRow = delivery;
    if (!deliveryRow) {
      const payload = {
        deal_id: deal.id,
        company_id: lead.company_id,
        lead_id: lead.id,
        website_project_id: websiteProject?.id || null,
        qr_project_id: qrService ? null : null,
        type: websiteService ? 'Website' : 'QR',
        delivery_status: 'not_ready',
        payment_status: 'pending',
        approval_status: 'pending',
        production_status: websiteService ? 'awaiting_intake' : 'not_ready',
        download_count: 0,
        responsible_user_id: userId,
        notes: `Service started. First payment: ${firstAmount} ${service.currency}.`
      };
      const { data, error } = await db.from('deliveries').insert(payload).select().single();
      if (error) throw new Error(`Could not create delivery: ${error.message}`);
      deliveryRow = data;
    }
  }

  await db.from('leads').update({ status: 'payment', recommended_service: service.name }).eq('id', lead.id);
  const { error: taskUpdateError } = await db.from('sales_agent_tasks').update({ status: 'completed', requires_human: false, result: { deal_id: deal.id, first_milestone_id: firstMilestone.id, website_project_id: websiteProject?.id || null, delivery_id: deliveryRow?.id || null }, completed_at: new Date().toISOString() }).eq('id', task.id).eq('status', 'pending');
  if (taskUpdateError) throw new Error(`Could not complete service task: ${taskUpdateError.message}`);

  return { deal, firstMilestone, websiteProject, delivery: deliveryRow };
}
