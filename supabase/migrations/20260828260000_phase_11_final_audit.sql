-- AI Agency CRM — Phase 11: Final Integration, Audit & Production Readiness
-- Hardens the cumulative Phase 1-10 system without replacing prior architecture.

-- Financial status transitions are privileged operations. Sales users can still
-- create/edit pending payments within their RLS scope, but cannot self-authorize
-- money as paid/refunded/authorized.
create or replace function public.set_payment_status(p_payment_id uuid,p_status text,p_transaction_id text default null)
returns public.payments language plpgsql security definer set search_path=public
as $$
declare v_payment public.payments; v_old text; v_role public.user_role;
begin
  v_role:=public.current_user_role();
  if v_role not in ('admin','manager') then
    raise exception 'Only admin or manager can change a payment financial status.' using errcode='42501';
  end if;
  if p_status not in ('pending','authorized','paid','failed','refunded','cancelled') then raise exception 'Invalid payment status.' using errcode='22023'; end if;
  select status into v_old from public.payments where id=p_payment_id for update;
  if not found then raise exception 'Payment not found.' using errcode='P0002'; end if;
  if v_old='paid' and p_status not in ('paid','refunded') then raise exception 'A paid payment can only remain paid or be refunded.' using errcode='42501'; end if;
  if v_old in ('failed','cancelled','refunded') and p_status<>v_old then raise exception 'A terminal payment status cannot be reopened.' using errcode='42501'; end if;
  if v_old='pending' and p_status='refunded' then raise exception 'A pending payment cannot be refunded.' using errcode='42501'; end if;
  perform set_config('app.payment_status_authorized','true',true);
  update public.payments set status=p_status,transaction_id=coalesce(nullif(trim(p_transaction_id),''),transaction_id),paid_at=case when p_status='paid' then coalesce(paid_at,now()) when p_status='refunded' then paid_at else paid_at end where id=p_payment_id returning * into v_payment;
  perform set_config('app.payment_status_authorized','false',true);
  insert into public.activities(user_id,lead_id,company_id,type,title,description,metadata)
  select auth.uid(),d.lead_id,l.company_id,'payment_'||p_status,'Payment '||replace(p_status,'_',' '),'Payment status transition recorded.',jsonb_build_object('payment_id',v_payment.id,'old_status',v_old,'new_status',p_status,'transaction_id_present',v_payment.transaction_id is not null)
  from public.deals d join public.leads l on l.id=d.lead_id where d.id=v_payment.deal_id;
  return v_payment;
exception when others then
  perform set_config('app.payment_status_authorized','false',true); raise;
end;
$$;
revoke all on function public.set_payment_status(uuid,text,text) from public;
grant execute on function public.set_payment_status(uuid,text,text) to authenticated;

-- Manual website payment recording is a finance operation, not a sales self-approval.
create or replace function public.record_website_first_payment(p_project_id uuid,p_amount numeric,p_method text default 'manual')
returns public.website_projects language plpgsql security definer set search_path=public
as $$
declare v_row public.website_projects; v_deal uuid; v_payment uuid; v_expected numeric;
begin
  if public.current_user_role() not in ('admin','manager') then raise exception 'Only admin or manager can record a manual website payment.' using errcode='42501'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Payment amount must be greater than zero.' using errcode='22023'; end if;
  select * into v_row from public.website_projects where id=p_project_id for update;
  if not found then raise exception 'Website project not found.' using errcode='P0002'; end if;
  if v_row.client_approved_at is null then raise exception 'Client approval is required before recording the first payment.' using errcode='42501'; end if;
  if v_row.first_payment_at is not null then raise exception 'The website first payment has already been recorded.' using errcode='23505'; end if;
  v_deal:=v_row.deal_id;
  if v_deal is null then
    insert into public.deals(lead_id,service_id,value,currency,status,probability,notes)
    select lead_id,service_id,p_amount,'MAD','open',100,'Website project '||id from public.website_projects where id=p_project_id returning id into v_deal;
    update public.website_projects set deal_id=v_deal where id=p_project_id;
  else
    select value into v_expected from public.deals where id=v_deal;
    if v_expected is not null then
      select v_expected-coalesce(sum(amount) filter(where status='paid'),0) into v_expected from public.payments where deal_id=v_deal;
      if p_amount>greatest(v_expected,0) then raise exception 'Payment cannot exceed the remaining deal balance.' using errcode='22003'; end if;
    end if;
  end if;
  insert into public.payments(deal_id,amount,currency,status,payment_method,website_project_id,milestone_type) values(v_deal,p_amount,'MAD','pending',coalesce(nullif(trim(p_method),''),'manual'),p_project_id,'deposit') returning id into v_payment;
  perform set_config('app.payment_status_authorized','true',true);
  update public.payments set status='paid',paid_at=now() where id=v_payment;
  perform set_config('app.payment_status_authorized','false',true);
  update public.website_projects set first_payment_at=coalesce(first_payment_at,now()),status='payment_pending' where id=p_project_id returning * into v_row;
  return v_row;
exception when others then
  perform set_config('app.payment_status_authorized','false',true); raise;
end;
$$;
revoke all on function public.record_website_first_payment(uuid,numeric,text) from public;
grant execute on function public.record_website_first_payment(uuid,numeric,text) to authenticated;

-- Invoice lifecycle is finance-authorized only. Draft creation remains available
-- to users allowed by the invoice RLS policy.
create or replace function public.set_invoice_status(p_invoice_id uuid,p_status text)
returns public.invoices language plpgsql security definer set search_path=public
as $$
declare v public.invoices; v_old text;
begin
  if public.current_user_role() not in ('admin','manager') then raise exception 'Only admin or manager can change invoice status.' using errcode='42501'; end if;
  if p_status not in ('draft','issued','partially_paid','paid','overdue','cancelled') then raise exception 'Invalid invoice status.' using errcode='22023'; end if;
  select status into v_old from public.invoices where id=p_invoice_id for update;
  if not found then raise exception 'Invoice not found.' using errcode='P0002'; end if;
  if v_old='paid' and p_status<>'paid' then raise exception 'A paid invoice cannot be reopened.' using errcode='42501'; end if;
  if v_old='cancelled' and p_status<>'cancelled' then raise exception 'A cancelled invoice cannot be reopened.' using errcode='42501'; end if;
  perform set_config('app.invoice_status_authorized','true',true);
  update public.invoices set status=p_status where id=p_invoice_id returning * into v;
  perform set_config('app.invoice_status_authorized','false',true);
  insert into public.activities(user_id,lead_id,company_id,type,title,description,metadata)
  values(auth.uid(),v.lead_id,v.company_id,'invoice_'||p_status,'Invoice '||replace(p_status,'_',' '),'Invoice lifecycle event recorded.',jsonb_build_object('invoice_id',v.id,'invoice_number',v.invoice_number,'old_status',v_old,'new_status',p_status));
  return v;
exception when others then
  perform set_config('app.invoice_status_authorized','false',true); raise;
end;
$$;
revoke all on function public.set_invoice_status(uuid,text) from public;
grant execute on function public.set_invoice_status(uuid,text) to authenticated;

-- Prevent a non-finance role from changing financial fields through direct table updates.
create or replace function public.guard_payment_mutation()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  if TG_OP='UPDATE' and OLD.status not in ('pending','authorized') and (
    NEW.amount is distinct from OLD.amount or NEW.currency is distinct from OLD.currency or NEW.deal_id is distinct from OLD.deal_id or
    NEW.website_project_id is distinct from OLD.website_project_id or NEW.qr_project_id is distinct from OLD.qr_project_id or NEW.milestone_type is distinct from OLD.milestone_type
  ) then
    raise exception 'Settled payments cannot have financial fields changed.' using errcode='42501';
  end if;
  return NEW;
end;
$$;

-- Additional operational notifications use the existing notification system and
-- unique source keys to remain idempotent.
create or replace function public.phase11_operational_notifications()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_user uuid; v_lead uuid; v_company uuid; v_type text; v_title text; v_message text; v_source_type text; v_source_id uuid;
begin
  if TG_TABLE_NAME='payments' and NEW.status is distinct from OLD.status and NEW.status in ('pending','paid','failed','refunded','cancelled') then
    select l.owner_id,l.id,l.company_id into v_user,v_lead,v_company from public.deals d join public.leads l on l.id=d.lead_id where d.id=NEW.deal_id;
    if v_user is not null then
      v_type:=case NEW.status when 'paid' then 'payment_received' when 'failed' then 'payment_failed' when 'pending' then 'payment_pending' else 'payment_'||NEW.status end;
      v_title:=case NEW.status when 'paid' then 'Payment received' when 'failed' then 'Payment failed' when 'pending' then 'Payment pending' when 'refunded' then 'Payment refunded' else 'Payment cancelled' end;
      v_message:='Payment status changed to '||NEW.status||'.'; v_source_type:='payment'; v_source_id:=NEW.id;
      insert into public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id) values(v_user,v_type,v_title,v_message,v_lead,v_company,v_source_type,v_source_id) on conflict do nothing;
    end if;
  elsif TG_TABLE_NAME='deliveries' and NEW.delivery_status is distinct from OLD.delivery_status and NEW.delivery_status in ('ready','delivered') then
    select owner_id into v_user from public.leads where id=NEW.lead_id;
    v_lead:=NEW.lead_id; v_company:=NEW.company_id; v_source_type:='delivery'; v_source_id:=NEW.id;
    if v_user is not null then
      v_type:=case NEW.delivery_status when 'ready' then 'delivery_ready' else 'delivery_completed' end;
      v_title:=case NEW.delivery_status when 'ready' then 'Delivery ready' else 'Delivery completed' end;
      v_message:=case NEW.delivery_status when 'ready' then 'A project passed its delivery gates.' else 'A project delivery was completed.' end;
      insert into public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id) values(v_user,v_type,v_title,v_message,v_lead,v_company,v_source_type,v_source_id) on conflict do nothing;
    end if;
  elsif TG_TABLE_NAME='workflow_executions' and NEW.status='failed' and OLD.status is distinct from NEW.status then
    select created_by into v_user from public.workflows where id=NEW.workflow_id;
    if v_user is not null then
      insert into public.notifications(user_id,type,title,message,source_type,source_id) values(v_user,'workflow_failure','Workflow failed','A workflow execution failed and requires review.','workflow_execution',NEW.id) on conflict do nothing;
    end if;
  end if;
  return NEW;
end;
$$;
drop trigger if exists phase11_payment_notifications on public.payments;
create trigger phase11_payment_notifications after update of status on public.payments for each row execute function public.phase11_operational_notifications();
drop trigger if exists phase11_delivery_notifications on public.deliveries;
create trigger phase11_delivery_notifications after update of delivery_status on public.deliveries for each row execute function public.phase11_operational_notifications();
drop trigger if exists phase11_workflow_notifications on public.workflow_executions;
create trigger phase11_workflow_notifications after update of status on public.workflow_executions for each row execute function public.phase11_operational_notifications();

-- Ensure the operational tables used by the final dashboard have useful indexes.
create index if not exists follow_ups_status_due_idx on public.follow_ups(status,due_at) where status='pending';
create index if not exists conversation_handoffs_open_idx on public.conversation_handoffs(created_at desc) where resolved_at is null;
create index if not exists invoices_due_status_idx on public.invoices(status,due_date);
create index if not exists deliveries_updated_idx on public.deliveries(updated_at desc);

comment on function public.set_payment_status(uuid,text,text) is 'Phase 11 finance-authorized payment transition. Paid/refunded/authorized transitions require admin or manager.';
comment on function public.set_invoice_status(uuid,text) is 'Phase 11 finance-authorized invoice transition.';

-- Final event coverage for lead creation, AI approval queues and integration errors.
create or replace function public.phase11_final_notifications()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_user uuid; v_company uuid; v_title text; v_type text; v_message text; v_source_type text; v_source_id uuid;
begin
  if TG_TABLE_NAME='leads' and TG_OP='INSERT' then
    v_user:=NEW.owner_id; v_company:=NEW.company_id; v_type:='new_lead'; v_title:='New lead'; v_message:='A new lead was created.'; v_source_type:='lead'; v_source_id:=NEW.id;
  elsif TG_TABLE_NAME='ai_drafts' and TG_OP='INSERT' and NEW.approval_status='pending' then
    select owner_id,company_id into v_user,v_company from public.leads where id=NEW.lead_id; v_type:='ai_approval_required'; v_title:='AI approval required'; v_message:='A new AI draft is waiting for review.'; v_source_type:='ai_draft'; v_source_id:=NEW.id;
  elsif TG_TABLE_NAME='provider_connection_tests' and TG_OP='INSERT' and NEW.status='failed' then
    v_user:=NEW.created_by; v_type:='integration_error'; v_title:='Integration error'; v_message:=coalesce(NEW.safe_error_message,'A provider connection test failed.'); v_source_type:='provider_connection_test'; v_source_id:=NEW.id;
  else return NEW; end if;
  if v_user is not null then
    insert into public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id) values(v_user,v_type,v_title,v_message,case when TG_TABLE_NAME='leads' then NEW.id when TG_TABLE_NAME='ai_drafts' then NEW.lead_id else null end,v_company,v_source_type,v_source_id) on conflict do nothing;
  end if;
  return NEW;
end;
$$;
drop trigger if exists phase11_new_lead_notification on public.leads;
create trigger phase11_new_lead_notification after insert on public.leads for each row execute function public.phase11_final_notifications();
drop trigger if exists phase11_ai_approval_notification on public.ai_drafts;
create trigger phase11_ai_approval_notification after insert on public.ai_drafts for each row execute function public.phase11_final_notifications();
drop trigger if exists phase11_integration_error_notification on public.provider_connection_tests;
create trigger phase11_integration_error_notification after insert on public.provider_connection_tests for each row execute function public.phase11_final_notifications();
