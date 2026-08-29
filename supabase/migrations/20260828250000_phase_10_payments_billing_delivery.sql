-- AI Agency CRM — Phase 10: Payments, Billing & Delivery Operations
-- Extends Phase 1-9 without replacing existing product tables.

-- Payment lifecycle now uses a constrained text status so legacy enum history remains intact while supporting operational states.
alter table public.payments alter column status drop default;
alter table public.payments alter column status type text using status::text;
alter table public.payments alter column status set default 'pending';
alter table public.payments drop constraint if exists payments_status_check;
alter table public.payments add constraint payments_status_check check (status in ('pending','authorized','paid','failed','refunded','cancelled'));

alter table public.payments add column if not exists milestone_type text not null default 'full_payment';
alter table public.payments add column if not exists website_project_id uuid references public.website_projects(id) on delete set null;
alter table public.payments add column if not exists qr_project_id uuid references public.qr_projects(id) on delete set null;
alter table public.payments add column if not exists reference text;
alter table public.payments add column if not exists notes text;
alter table public.payments add column if not exists updated_at timestamptz not null default now();
alter table public.payments add constraint payments_milestone_type_check check (milestone_type in ('deposit','remaining_balance','full_payment'));
create index if not exists payments_website_project_idx on public.payments(website_project_id);
create index if not exists payments_qr_project_idx on public.payments(qr_project_id);
create index if not exists payments_status_deal_idx on public.payments(deal_id,status);

-- Prevent financial status changes from the browser. Only SECURITY DEFINER RPCs set this flag.
create or replace function public.guard_payment_status_change()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  if TG_OP='INSERT' and NEW.status <> 'pending' and coalesce(current_setting('app.payment_status_authorized',true),'false') <> 'true' then
    raise exception 'Payment status can only be initialized as pending.' using errcode='42501';
  end if;
  if TG_OP='UPDATE' and NEW.status is distinct from OLD.status and coalesce(current_setting('app.payment_status_authorized',true),'false') <> 'true' then
    raise exception 'Payment status changes must use an authorized payment operation.' using errcode='42501';
  end if;
  return NEW;
end;
$$;
drop trigger if exists payments_guard_status on public.payments;
create trigger payments_guard_status before insert or update of status on public.payments for each row execute function public.guard_payment_status_change();

drop trigger if exists payments_set_updated_at on public.payments;
create trigger payments_set_updated_at before update on public.payments for each row execute function public.set_updated_at();

-- Payment milestones: explicit expected steps for a deal/project.
create table if not exists public.payment_milestones (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.deals(id) on delete cascade,
  website_project_id uuid references public.website_projects(id) on delete set null,
  qr_project_id uuid references public.qr_projects(id) on delete set null,
  milestone_type text not null check (milestone_type in ('deposit','remaining_balance','full_payment')),
  label text not null check (char_length(trim(label)) between 1 and 160),
  amount numeric(12,2) not null check (amount >= 0),
  currency text not null default 'MAD' check (char_length(currency)=3),
  due_date date,
  status text not null default 'pending' check (status in ('pending','paid','cancelled')),
  paid_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payment_milestones_parent_check check (website_project_id is not null or qr_project_id is not null or deal_id is not null)
);
create index if not exists payment_milestones_deal_idx on public.payment_milestones(deal_id);
create index if not exists payment_milestones_status_idx on public.payment_milestones(status);
drop trigger if exists payment_milestones_set_updated_at on public.payment_milestones;
create trigger payment_milestones_set_updated_at before update on public.payment_milestones for each row execute function public.set_updated_at();
alter table public.payment_milestones enable row level security;
drop policy if exists payment_milestones_access on public.payment_milestones;
create policy payment_milestones_access on public.payment_milestones for all to authenticated
using (public.current_user_role() in ('admin','manager') or exists(select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=payment_milestones.deal_id and l.owner_id=auth.uid()))
with check (public.current_user_role() in ('admin','manager') or exists(select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=payment_milestones.deal_id and l.owner_id=auth.uid()));

-- Invoicing foundation.
create sequence if not exists public.invoice_number_seq start 1001;
create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null unique,
  company_id uuid references public.companies(id) on delete set null,
  lead_id uuid references public.leads(id) on delete set null,
  deal_id uuid references public.deals(id) on delete set null,
  subtotal numeric(12,2) not null default 0 check (subtotal >= 0),
  discount numeric(12,2) not null default 0 check (discount >= 0),
  tax numeric(12,2) not null default 0 check (tax >= 0),
  total numeric(12,2) not null default 0 check (total >= 0),
  currency text not null default 'MAD' check (char_length(currency)=3),
  status text not null default 'draft' check (status in ('draft','issued','partially_paid','paid','overdue','cancelled')),
  issue_date date not null default current_date,
  due_date date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  description text not null check (char_length(trim(description)) between 1 and 500),
  quantity numeric(12,2) not null default 1 check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  amount numeric(12,2) generated always as (round(quantity * unit_price,2)) stored,
  created_at timestamptz not null default now()
);
create index if not exists invoices_company_idx on public.invoices(company_id);
create index if not exists invoices_deal_idx on public.invoices(deal_id);
create index if not exists invoices_status_idx on public.invoices(status);
create index if not exists invoice_items_invoice_idx on public.invoice_items(invoice_id);
drop trigger if exists invoices_set_updated_at on public.invoices;
create trigger invoices_set_updated_at before update on public.invoices for each row execute function public.set_updated_at();

create or replace function public.next_invoice_number()
returns text language plpgsql security definer set search_path=public
as $$
begin
  return 'INV-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.invoice_number_seq')::text,5,'0');
end;
$$;
revoke all on function public.next_invoice_number() from public;
grant execute on function public.next_invoice_number() to authenticated;

create or replace function public.refresh_invoice_totals(p_invoice_id uuid)
returns public.invoices language plpgsql security definer set search_path=public
as $$
declare v_row public.invoices; v_subtotal numeric(12,2);
begin
  select coalesce(sum(amount),0) into v_subtotal from public.invoice_items where invoice_id=p_invoice_id;
  update public.invoices set subtotal=v_subtotal,total=greatest(0,v_subtotal-discount+tax) where id=p_invoice_id returning * into v_row;
  return v_row;
end;
$$;
create or replace function public.invoice_items_refresh()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  perform public.refresh_invoice_totals(case when TG_OP='DELETE' then OLD.invoice_id else NEW.invoice_id end);
  if TG_OP='DELETE' then return OLD; else return NEW; end if;
end;
$$;
drop trigger if exists invoice_items_refresh_totals on public.invoice_items;
create trigger invoice_items_refresh_totals after insert or update or delete on public.invoice_items for each row execute function public.invoice_items_refresh();

alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security;
drop policy if exists invoices_access on public.invoices;
create policy invoices_access on public.invoices for all to authenticated
using (public.current_user_role() in ('admin','manager') or exists(select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=invoices.deal_id and l.owner_id=auth.uid()))
with check (public.current_user_role() in ('admin','manager') or exists(select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=invoices.deal_id and l.owner_id=auth.uid()));
drop policy if exists invoice_items_access on public.invoice_items;
create policy invoice_items_access on public.invoice_items for all to authenticated
using (public.current_user_role() in ('admin','manager') or exists(select 1 from public.invoices i join public.deals d on d.id=i.deal_id join public.leads l on l.id=d.lead_id where i.id=invoice_items.invoice_id and l.owner_id=auth.uid()))
with check (public.current_user_role() in ('admin','manager') or exists(select 1 from public.invoices i join public.deals d on d.id=i.deal_id join public.leads l on l.id=d.lead_id where i.id=invoice_items.invoice_id and l.owner_id=auth.uid()));

-- Delivery operations, one current record per project and an append-only history.
create table if not exists public.deliveries (
  id uuid primary key default gen_random_uuid(),
  website_project_id uuid references public.website_projects(id) on delete cascade,
  qr_project_id uuid references public.qr_projects(id) on delete cascade,
  company_id uuid references public.companies(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete set null,
  deal_id uuid references public.deals(id) on delete set null,
  type text not null check (type in ('Website','QR')),
  delivery_status text not null default 'not_ready' check (delivery_status in ('not_ready','ready','delivered','downloaded','cancelled')),
  payment_status text not null default 'pending' check (payment_status in ('pending','partial','paid','not_required')),
  approval_status text not null default 'pending' check (approval_status in ('pending','approved','not_required')),
  production_status text not null default 'not_ready',
  delivered_at timestamptz,
  download_count integer not null default 0 check (download_count >= 0),
  responsible_user_id uuid references public.profiles(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint deliveries_one_project check ((website_project_id is not null)::integer + (qr_project_id is not null)::integer = 1)
);
create unique index if not exists deliveries_website_unique on public.deliveries(website_project_id) where website_project_id is not null;
create unique index if not exists deliveries_qr_unique on public.deliveries(qr_project_id) where qr_project_id is not null;
create index if not exists deliveries_status_idx on public.deliveries(delivery_status);
create index if not exists deliveries_company_idx on public.deliveries(company_id);
create table if not exists public.delivery_events (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  event_type text not null check (event_type in ('delivery_ready','delivery_blocked','delivery_completed','downloaded')),
  user_id uuid references public.profiles(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists delivery_events_delivery_idx on public.delivery_events(delivery_id,created_at desc);
drop trigger if exists deliveries_set_updated_at on public.deliveries;
create trigger deliveries_set_updated_at before update on public.deliveries for each row execute function public.set_updated_at();
alter table public.deliveries enable row level security;
alter table public.delivery_events enable row level security;
drop policy if exists deliveries_access on public.deliveries;
create policy deliveries_access on public.deliveries for all to authenticated
using (public.current_user_role() in ('admin','manager') or (lead_id is not null and exists(select 1 from public.leads l where l.id=deliveries.lead_id and l.owner_id=auth.uid())) or (deal_id is not null and exists(select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=deliveries.deal_id and l.owner_id=auth.uid())))
with check (public.current_user_role() in ('admin','manager') or (lead_id is not null and exists(select 1 from public.leads l where l.id=deliveries.lead_id and l.owner_id=auth.uid())) or (deal_id is not null and exists(select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=deliveries.deal_id and l.owner_id=auth.uid())));
drop policy if exists delivery_events_access on public.delivery_events;
create policy delivery_events_access on public.delivery_events for select to authenticated
using (public.current_user_role() in ('admin','manager') or exists(select 1 from public.deliveries d where d.id=delivery_events.delivery_id and d.lead_id in (select id from public.leads where owner_id=auth.uid())));

-- Payment summary used by gates and dashboard. Paid means only status=paid.
create or replace view public.deal_payment_summary as
select d.id as deal_id,d.value,d.currency,
  coalesce(sum(p.amount) filter(where p.status='paid'),0)::numeric(12,2) as paid_amount,
  greatest(d.value-coalesce(sum(p.amount) filter(where p.status='paid'),0),0)::numeric(12,2) as outstanding_amount,
  case when d.value=0 then 100 else least(100,round(coalesce(sum(p.amount) filter(where p.status='paid'),0)/d.value*100,2)) end as paid_percent,
  count(p.id) filter(where p.status='pending') as pending_count,
  count(p.id) filter(where p.status='failed') as failed_count
from public.deals d left join public.payments p on p.deal_id=d.id
group by d.id;

-- Secure payment status transition. Direct table updates cannot mark a payment paid.
create or replace function public.set_payment_status(p_payment_id uuid,p_status text,p_transaction_id text default null)
returns public.payments language plpgsql security definer set search_path=public
as $$
declare v_payment public.payments; v_role public.user_role;
begin
  v_role:=public.current_user_role();
  if v_role not in ('admin','manager') and not exists(select 1 from public.payments p join public.deals d on d.id=p.deal_id join public.leads l on l.id=d.lead_id where p.id=p_payment_id and l.owner_id=auth.uid()) then
    raise exception 'Not authorized to update this payment.' using errcode='42501';
  end if;
  if p_status not in ('pending','authorized','paid','failed','refunded','cancelled') then raise exception 'Invalid payment status.' using errcode='22023'; end if;
  perform set_config('app.payment_status_authorized','true',true);
  update public.payments set status=p_status,transaction_id=coalesce(nullif(trim(p_transaction_id),''),transaction_id),paid_at=case when p_status='paid' then coalesce(paid_at,now()) else paid_at end where id=p_payment_id returning * into v_payment;
  if not found then raise exception 'Payment not found.' using errcode='P0002'; end if;
  perform set_config('app.payment_status_authorized','false',true);
  return v_payment;
end;
$$;
revoke all on function public.set_payment_status(uuid,text,text) from public;
grant execute on function public.set_payment_status(uuid,text,text) to authenticated;

-- Existing Phase 4 helper is retained but now creates a pending payment then authorizes it safely.
create or replace function public.record_website_first_payment(p_project_id uuid,p_amount numeric,p_method text default 'manual')
returns public.website_projects language plpgsql security definer set search_path=public
as $$
declare v_row public.website_projects; v_deal uuid; v_payment uuid;
begin
  if not exists(select 1 from public.website_projects wp where wp.id=p_project_id and (public.current_user_role() in ('admin','manager') or exists(select 1 from public.leads l where l.id=wp.lead_id and l.owner_id=auth.uid()))) then
    raise exception 'Not authorized.' using errcode='42501';
  end if;
  if p_amount is null or p_amount<=0 then raise exception 'Payment amount must be greater than zero.' using errcode='22023'; end if;
  if not exists(select 1 from public.website_projects wp where wp.id=p_project_id and wp.client_approved_at is not null) then raise exception 'Client approval is required before recording the first payment.' using errcode='42501'; end if;
  select deal_id into v_deal from public.website_projects where id=p_project_id;
  if v_deal is null then
    insert into public.deals(lead_id,service_id,value,currency,status,probability,notes)
    select lead_id,service_id,p_amount,'MAD','open',100,'Website project '||id from public.website_projects where id=p_project_id returning id into v_deal;
    update public.website_projects set deal_id=v_deal where id=p_project_id;
  end if;
  insert into public.payments(deal_id,amount,currency,status,payment_method,website_project_id,milestone_type) values(v_deal,p_amount,'MAD','pending',coalesce(nullif(trim(p_method),''),'manual'),p_project_id,'deposit') returning id into v_payment;
  perform set_config('app.payment_status_authorized','true',true);
  update public.payments set status='paid',paid_at=now() where id=v_payment;
  perform set_config('app.payment_status_authorized','false',true);
  update public.website_projects set first_payment_at=coalesce(first_payment_at,now()),status='payment_pending' where id=p_project_id returning * into v_row;
  return v_row;
end;
$$;
revoke all on function public.record_website_first_payment(uuid,numeric,text) from public;
grant execute on function public.record_website_first_payment(uuid,numeric,text) to authenticated;

-- Central delivery gate calculation. No delivery can be authorized unless all applicable gates pass.
create or replace function public.get_delivery_gate(p_type text,p_project_id uuid)
returns table(allowed boolean,reason text,payment_status text,approval_status text,production_status text,delivery_status text,paid_amount numeric,outstanding_amount numeric)
language plpgsql security definer set search_path=public
as $$
declare v_company uuid; v_lead uuid; v_deal uuid; v_value numeric; v_paid numeric; v_status text; v_approved boolean; v_production text; v_delivery text;
begin
  if p_type='Website' then
    select company_id,lead_id,deal_id,status,client_approved_at,delivery_status into v_company,v_lead,v_deal,v_production,v_approved,v_delivery from public.website_projects where id=p_project_id;
  elsif p_type='QR' then
    select company_id,lead_id,deal_id,status into v_company,v_lead,v_deal,v_production from public.qr_projects where id=p_project_id;
    v_approved:=true; v_delivery:=case when v_production='delivered' then 'delivered' else 'not_ready' end;
  else raise exception 'Invalid delivery type.' using errcode='22023'; end if;
  if v_company is null then return query select false,'Project not found','pending',case when v_approved then 'approved' else 'pending' end,v_production,coalesce(v_delivery,'not_ready'),0::numeric,0::numeric; return; end if;
  select value into v_value from public.deals where id=v_deal;
  select coalesce(sum(amount),0) into v_paid from public.payments where deal_id=v_deal and status='paid';
  if v_deal is null then v_paid:=0; end if;
  if v_deal is null then v_status:=case when v_paid>0 then 'paid' else 'not_required' end; else v_status:=case when v_paid>=coalesce(v_value,0) then 'paid' when v_paid>0 then 'partial' else 'pending' end; end if;
  if p_type='Website' and not coalesce(v_approved,false) then return query select false,'Waiting for client approval',v_status,'pending',v_production,coalesce(v_delivery,'not_ready'),v_paid,greatest(coalesce(v_value,0)-v_paid,0); return; end if;
  if v_deal is not null and v_paid < coalesce(v_value,0) then return query select false,case when v_paid=0 then 'Waiting for payment' else 'Waiting for final payment' end,v_status,case when v_approved then 'approved' else 'pending' end,v_production,coalesce(v_delivery,'not_ready'),v_paid,greatest(v_value-v_paid,0); return; end if;
  if p_type='Website' and v_production not in ('ready_for_delivery','packaged','delivered','completed') then return query select false,'Website not ready',v_status,'approved',v_production,coalesce(v_delivery,'not_ready'),v_paid,greatest(coalesce(v_value,0)-v_paid,0); return; end if;
  if p_type='QR' and v_production not in ('active','approved','approved_final','packaged','delivered') then return query select false,'QR project not ready',v_status,'approved',v_production,coalesce(v_delivery,'not_ready'),v_paid,greatest(coalesce(v_value,0)-v_paid,0); return; end if;
  return query select true,'Delivery allowed',v_status,case when v_approved then 'approved' else 'not_required' end,v_production,coalesce(v_delivery,'not_ready'),v_paid,greatest(coalesce(v_value,0)-v_paid,0);
end;
$$;
revoke all on function public.get_delivery_gate(text,uuid) from public;
grant execute on function public.get_delivery_gate(text,uuid) to authenticated;

create or replace function public.authorize_delivery_download(p_type text,p_project_id uuid)
returns uuid language plpgsql security definer set search_path=public
as $$
declare v_gate record; v_delivery uuid; v_user uuid:=auth.uid();
begin
  if public.current_user_role() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  select * into v_gate from public.get_delivery_gate(p_type,p_project_id);
  if not v_gate.allowed then
    raise exception 'Delivery blocked: %',v_gate.reason using errcode='42501';
  end if;
  if p_type='Website' then
    select id into v_delivery from public.deliveries where website_project_id=p_project_id;
    if v_delivery is null then
      insert into public.deliveries(website_project_id,company_id,lead_id,deal_id,type,delivery_status,payment_status,approval_status,production_status,responsible_user_id)
      select id,company_id,lead_id,deal_id,'Website','ready',v_gate.payment_status,v_gate.approval_status,v_gate.production_status,v_user from public.website_projects where id=p_project_id returning id into v_delivery;
    else
      update public.deliveries set payment_status=v_gate.payment_status,approval_status=v_gate.approval_status,production_status=v_gate.production_status,delivery_status=case when delivery_status='delivered' then delivery_status else 'ready' end,updated_at=now() where id=v_delivery;
    end if;
  else
    select id into v_delivery from public.deliveries where qr_project_id=p_project_id;
    if v_delivery is null then
      insert into public.deliveries(qr_project_id,company_id,lead_id,deal_id,type,delivery_status,payment_status,approval_status,production_status,responsible_user_id)
      select id,company_id,lead_id,deal_id,'QR','ready',v_gate.payment_status,v_gate.approval_status,v_gate.production_status,v_user from public.qr_projects where id=p_project_id returning id into v_delivery;
    else
      update public.deliveries set payment_status=v_gate.payment_status,approval_status=v_gate.approval_status,production_status=v_gate.production_status,delivery_status=case when delivery_status='delivered' then delivery_status else 'ready' end,updated_at=now() where id=v_delivery;
    end if;
  end if;
  insert into public.delivery_events(delivery_id,event_type,user_id,metadata) values(v_delivery,'delivery_ready',v_user,jsonb_build_object('type',p_type,'project_id',p_project_id));
  return v_delivery;
end;
$$;
revoke all on function public.authorize_delivery_download(text,uuid) from public;
grant execute on function public.authorize_delivery_download(text,uuid) to authenticated;

create or replace function public.record_delivery_download(p_delivery_id uuid)
returns public.deliveries language plpgsql security definer set search_path=public
as $$
declare v public.deliveries;
begin
  select * into v from public.deliveries where id=p_delivery_id;
  if v.id is null then raise exception 'Delivery record not found.' using errcode='P0002'; end if;
  if public.current_user_role() not in ('admin','manager') and not exists(select 1 from public.leads l where l.id=v.lead_id and l.owner_id=auth.uid()) then raise exception 'Not authorized.' using errcode='42501'; end if;
  if v.delivery_status not in ('ready','delivered','downloaded') then raise exception 'Delivery is not authorized.' using errcode='42501'; end if;
  update public.deliveries set delivery_status='downloaded',download_count=download_count+1 where id=v.id returning * into v;
  insert into public.delivery_events(delivery_id,event_type,user_id,metadata) values(v.id,'downloaded',auth.uid(),jsonb_build_object('download_count',v.download_count));
  return v;
end;
$$;
revoke all on function public.record_delivery_download(uuid) from public;
grant execute on function public.record_delivery_download(uuid) to authenticated;

create or replace function public.complete_delivery(p_delivery_id uuid)
returns public.deliveries language plpgsql security definer set search_path=public
as $$
declare v public.deliveries;
begin
  select * into v from public.deliveries where id=p_delivery_id;
  if v.id is null then raise exception 'Delivery record not found.' using errcode='P0002'; end if;
  if public.current_user_role() not in ('admin','manager') and not exists(select 1 from public.leads l where l.id=v.lead_id and l.owner_id=auth.uid()) then raise exception 'Not authorized.' using errcode='42501'; end if;
  if v.delivery_status not in ('ready','downloaded','delivered') then raise exception 'Delivery is not ready.' using errcode='42501'; end if;
  update public.deliveries set delivery_status='delivered',delivered_at=coalesce(delivered_at,now()) where id=v.id returning * into v;
  if v.website_project_id is not null then
    update public.website_projects set status='delivered',delivery_status='delivered',delivered_at=coalesce(delivered_at,now()) where id=v.website_project_id and status in ('ready_for_delivery','packaged');
  elsif v.qr_project_id is not null then
    update public.qr_projects set status='delivered' where id=v.qr_project_id and status not in ('archived');
  end if;
  insert into public.delivery_events(delivery_id,event_type,user_id,metadata) values(v.id,'delivery_completed',auth.uid(),jsonb_build_object('type',v.type));
  return v;
end;
$$;
revoke all on function public.complete_delivery(uuid) from public;
grant execute on function public.complete_delivery(uuid) to authenticated;

-- Operational payment events feed existing Activities/Notifications. No fake paid state is created.
create or replace function public.phase10_payment_event()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_lead uuid; v_company uuid; v_title text; v_type text;
begin
  select l.id,l.company_id into v_lead,v_company from public.deals d join public.leads l on l.id=d.lead_id where d.id=NEW.deal_id;
  if TG_OP='INSERT' then v_type:='payment_created'; v_title:='Payment Created';
  elsif NEW.status='paid' and OLD.status is distinct from 'paid' then v_type:='payment_paid'; v_title:='Payment Paid';
  elsif NEW.status='failed' and OLD.status is distinct from 'failed' then v_type:='payment_failed'; v_title:='Payment Failed';
  elsif NEW.status='refunded' and OLD.status is distinct from 'refunded' then v_type:='payment_refunded'; v_title:='Payment Refunded';
  elsif NEW.status='cancelled' and OLD.status is distinct from 'cancelled' then v_type:='payment_cancelled'; v_title:='Payment Cancelled';
  else return NEW; end if;
  insert into public.activities(user_id,lead_id,company_id,type,title,description,metadata) values(auth.uid(),v_lead,v_company,v_type,v_title,'Payment operation recorded.',jsonb_build_object('payment_id',NEW.id,'deal_id',NEW.deal_id,'amount',NEW.amount,'currency',NEW.currency,'status',NEW.status));
  if NEW.status='paid' and (NEW.website_project_id is not null or NEW.qr_project_id is not null) then
    insert into public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id)
    select p.id,'payment_paid','Payment received','A project payment has been confirmed.',v_lead,v_company,'payment',NEW.id from public.profiles p where p.role in ('admin','manager')
    on conflict do nothing;
  end if;
  return NEW;
end;
$$;
drop trigger if exists phase10_payment_event_trigger on public.payments;
create trigger phase10_payment_event_trigger after insert or update of status on public.payments for each row execute function public.phase10_payment_event();

-- Synchronize Website Gate: final packaging requires full deal payment when a deal exists.
create or replace function public.mark_website_packaged(p_project_id uuid)
returns public.website_projects language plpgsql security definer set search_path=public
as $$
declare v_row public.website_projects; v_paid numeric; v_required numeric;
begin
  if not exists(select 1 from public.website_projects wp where wp.id=p_project_id and (public.current_user_role() in ('admin','manager') or exists(select 1 from public.leads l where l.id=wp.lead_id and l.owner_id=auth.uid()) or exists(select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=wp.deal_id and l.owner_id=auth.uid()))) then raise exception 'Not authorized.' using errcode='42501'; end if;
  select coalesce(sum(p.amount),0) into v_paid from public.payments p join public.website_projects wp on wp.deal_id=p.deal_id where wp.id=p_project_id and p.status='paid';
  select coalesce(d.value,0) into v_required from public.website_projects wp left join public.deals d on d.id=wp.deal_id where wp.id=p_project_id;
  if not exists(select 1 from public.website_projects where id=p_project_id and client_approved_at is not null) then raise exception 'Delivery blocked: waiting for client approval.' using errcode='42501'; end if;
  if exists(select 1 from public.website_projects where id=p_project_id and deal_id is not null) and v_paid < v_required then raise exception 'Delivery blocked: waiting for final payment.' using errcode='42501'; end if;
  if not exists(select 1 from public.website_projects where id=p_project_id and status in ('approved_final','payment_pending','ready_for_delivery','packaged') and rendered_html is not null) then raise exception 'Delivery blocked: website is not production-ready.' using errcode='42501'; end if;
  update public.website_projects set status='packaged',package_generated_at=coalesce(package_generated_at,now()),delivery_status='ready' where id=p_project_id and status not in ('delivered','completed','cancelled','archived') returning * into v_row;
  if not found then raise exception 'Website cannot be packaged from its current state.' using errcode='42501'; end if;
  return v_row;
end;
$$;
revoke all on function public.mark_website_packaged(uuid) from public;
grant execute on function public.mark_website_packaged(uuid) to authenticated;

-- Backfill current delivery records for projects already present in Phase 9.
insert into public.deliveries(website_project_id,company_id,lead_id,deal_id,type,delivery_status,approval_status,production_status)
select wp.id,wp.company_id,wp.lead_id,wp.deal_id,'Website',case when wp.delivery_status='delivered' then 'delivered' else 'not_ready' end,case when wp.client_approved_at is not null then 'approved' else 'pending' end,wp.status
from public.website_projects wp
where not exists(select 1 from public.deliveries d where d.website_project_id=wp.id);
insert into public.deliveries(qr_project_id,company_id,lead_id,deal_id,type,delivery_status,approval_status,production_status)
select qp.id,qp.company_id,qp.lead_id,qp.deal_id,'QR',case when qp.status='delivered' then 'delivered' else 'not_ready' end,'not_required',qp.status
from public.qr_projects qp
where not exists(select 1 from public.deliveries d where d.qr_project_id=qp.id);

-- Keep delivery center synchronized whenever a project changes.
create or replace function public.sync_delivery_record()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_gate record; v_id uuid; v_type text;
begin
  v_type:=case when TG_TABLE_NAME='website_projects' then 'Website' else 'QR' end;
  select * into v_gate from public.get_delivery_gate(v_type,NEW.id);
  if v_type='Website' then
    select id into v_id from public.deliveries where website_project_id=NEW.id;
    if v_id is null then
      insert into public.deliveries(website_project_id,company_id,lead_id,deal_id,type,delivery_status,payment_status,approval_status,production_status)
      values(NEW.id,NEW.company_id,NEW.lead_id,NEW.deal_id,'Website',case when v_gate.allowed then 'ready' when NEW.delivery_status='delivered' then 'delivered' else 'not_ready' end,v_gate.payment_status,v_gate.approval_status,v_gate.production_status);
    else
      update public.deliveries set company_id=NEW.company_id,lead_id=NEW.lead_id,deal_id=NEW.deal_id,payment_status=v_gate.payment_status,approval_status=v_gate.approval_status,production_status=v_gate.production_status,delivery_status=case when delivery_status in ('delivered','downloaded') then delivery_status when v_gate.allowed then 'ready' else 'not_ready' end,updated_at=now() where id=v_id;
    end if;
  else
    select id into v_id from public.deliveries where qr_project_id=NEW.id;
    if v_id is null then
      insert into public.deliveries(qr_project_id,company_id,lead_id,deal_id,type,delivery_status,payment_status,approval_status,production_status)
      values(NEW.id,NEW.company_id,NEW.lead_id,NEW.deal_id,'QR',case when v_gate.allowed then 'ready' when NEW.status='delivered' then 'delivered' else 'not_ready' end,v_gate.payment_status,v_gate.approval_status,v_gate.production_status);
    else
      update public.deliveries set company_id=NEW.company_id,lead_id=NEW.lead_id,deal_id=NEW.deal_id,payment_status=v_gate.payment_status,approval_status=v_gate.approval_status,production_status=v_gate.production_status,delivery_status=case when delivery_status in ('delivered','downloaded') then delivery_status when v_gate.allowed then 'ready' else 'not_ready' end,updated_at=now() where id=v_id;
    end if;
  end if;
  return NEW;
end;
$$;
drop trigger if exists phase10_website_delivery_sync on public.website_projects;
create trigger phase10_website_delivery_sync after insert or update on public.website_projects for each row execute function public.sync_delivery_record();
drop trigger if exists phase10_qr_delivery_sync on public.qr_projects;
create trigger phase10_qr_delivery_sync after insert or update on public.qr_projects for each row execute function public.sync_delivery_record();

-- Invoice lifecycle is also server-authorized.
create or replace function public.guard_invoice_status_change()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  if TG_OP='INSERT' and NEW.status <> 'draft' and coalesce(current_setting('app.invoice_status_authorized',true),'false') <> 'true' then
    raise exception 'Invoices can only be created as draft.' using errcode='42501';
  end if;
  if TG_OP='UPDATE' and NEW.status is distinct from OLD.status and coalesce(current_setting('app.invoice_status_authorized',true),'false') <> 'true' then
    raise exception 'Invoice status changes must use an authorized invoice operation.' using errcode='42501';
  end if;
  return NEW;
end;
$$;
drop trigger if exists invoices_guard_status on public.invoices;
create trigger invoices_guard_status before insert or update of status on public.invoices for each row execute function public.guard_invoice_status_change();

create or replace function public.set_invoice_status(p_invoice_id uuid,p_status text)
returns public.invoices language plpgsql security definer set search_path=public
as $$
declare v public.invoices;
begin
  if public.current_user_role() not in ('admin','manager') and not exists(select 1 from public.invoices i join public.deals d on d.id=i.deal_id join public.leads l on l.id=d.lead_id where i.id=p_invoice_id and l.owner_id=auth.uid()) then raise exception 'Not authorized.' using errcode='42501'; end if;
  if p_status not in ('draft','issued','partially_paid','paid','overdue','cancelled') then raise exception 'Invalid invoice status.' using errcode='22023'; end if;
  perform set_config('app.invoice_status_authorized','true',true);
  update public.invoices set status=p_status where id=p_invoice_id returning * into v;
  perform set_config('app.invoice_status_authorized','false',true);
  if v.id is null then raise exception 'Invoice not found.' using errcode='P0002'; end if;
  insert into public.activities(user_id,lead_id,company_id,type,title,description,metadata)
  select auth.uid(),v.lead_id,v.company_id,'invoice_'||p_status,'Invoice '||replace(p_status,'_',' '),'Invoice lifecycle event recorded.',jsonb_build_object('invoice_id',v.id,'invoice_number',v.invoice_number,'status',p_status);
  return v;
end;
$$;
revoke all on function public.set_invoice_status(uuid,text) from public;
grant execute on function public.set_invoice_status(uuid,text) to authenticated;

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
drop trigger if exists payments_guard_mutation on public.payments;
create trigger payments_guard_mutation before update on public.payments for each row execute function public.guard_payment_mutation();

-- Delivery gate must respect the same ownership model as the underlying project.
create or replace function public.get_delivery_gate(p_type text,p_project_id uuid)
returns table(allowed boolean,reason text,payment_status text,approval_status text,production_status text,delivery_status text,paid_amount numeric,outstanding_amount numeric)
language plpgsql security definer set search_path=public
as $$
declare v_company uuid; v_lead uuid; v_deal uuid; v_value numeric; v_paid numeric; v_status text; v_approved boolean; v_production text; v_delivery text; v_allowed boolean;
begin
  if p_type='Website' then
    select company_id,lead_id,deal_id,status,client_approved_at,delivery_status into v_company,v_lead,v_deal,v_production,v_approved,v_delivery from public.website_projects where id=p_project_id;
  elsif p_type='QR' then
    select company_id,lead_id,deal_id,status into v_company,v_lead,v_deal,v_production from public.qr_projects where id=p_project_id;
    v_approved:=true; v_delivery:=case when v_production='delivered' then 'delivered' else 'not_ready' end;
  else raise exception 'Invalid delivery type.' using errcode='22023'; end if;
  if v_company is null then raise exception 'Project not found.' using errcode='P0002'; end if;
  v_allowed:=public.current_user_role() in ('admin','manager') or (v_lead is not null and exists(select 1 from public.leads l where l.id=v_lead and l.owner_id=auth.uid())) or (v_deal is not null and exists(select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=v_deal and l.owner_id=auth.uid()));
  if not v_allowed then raise exception 'Not authorized to inspect this delivery.' using errcode='42501'; end if;
  select value into v_value from public.deals where id=v_deal;
  select coalesce(sum(amount),0) into v_paid from public.payments where deal_id=v_deal and status='paid';
  if v_deal is null then v_paid:=0; end if;
  if v_deal is null then v_status:='not_required'; else v_status:=case when v_paid>=coalesce(v_value,0) then 'paid' when v_paid>0 then 'partial' else 'pending' end; end if;
  if p_type='Website' and not coalesce(v_approved,false) then return query select false,'Waiting for client approval',v_status,'pending',v_production,coalesce(v_delivery,'not_ready'),v_paid,greatest(coalesce(v_value,0)-v_paid,0); return; end if;
  if v_deal is not null and v_paid < coalesce(v_value,0) then return query select false,case when v_paid=0 then 'Waiting for payment' else 'Waiting for final payment' end,v_status,case when v_approved then 'approved' else 'pending' end,v_production,coalesce(v_delivery,'not_ready'),v_paid,greatest(v_value-v_paid,0); return; end if;
  if p_type='Website' and v_production not in ('ready_for_delivery','packaged','delivered','completed') then return query select false,'Website not ready',v_status,'approved',v_production,coalesce(v_delivery,'not_ready'),v_paid,greatest(coalesce(v_value,0)-v_paid,0); return; end if;
  if p_type='QR' and v_production not in ('active','approved','approved_final','packaged','delivered') then return query select false,'QR project not ready',v_status,'approved',v_production,coalesce(v_delivery,'not_ready'),v_paid,greatest(coalesce(v_value,0)-v_paid,0); return; end if;
  return query select true,'Delivery allowed',v_status,case when v_approved then 'approved' else 'not_required' end,v_production,coalesce(v_delivery,'not_ready'),v_paid,greatest(coalesce(v_value,0)-v_paid,0);
end;
$$;
revoke all on function public.get_delivery_gate(text,uuid) from public;
grant execute on function public.get_delivery_gate(text,uuid) to authenticated;

create or replace function public.refresh_delivery_after_payment()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_gate record;
begin
  if NEW.website_project_id is not null then
    select * into v_gate from public.get_delivery_gate('Website',NEW.website_project_id);
    update public.deliveries set payment_status=v_gate.payment_status,approval_status=v_gate.approval_status,production_status=v_gate.production_status,delivery_status=case when delivery_status in ('delivered','downloaded') then delivery_status when v_gate.allowed then 'ready' else 'not_ready' end,updated_at=now() where website_project_id=NEW.website_project_id;
  elsif NEW.qr_project_id is not null then
    select * into v_gate from public.get_delivery_gate('QR',NEW.qr_project_id);
    update public.deliveries set payment_status=v_gate.payment_status,approval_status=v_gate.approval_status,production_status=v_gate.production_status,delivery_status=case when delivery_status in ('delivered','downloaded') then delivery_status when v_gate.allowed then 'ready' else 'not_ready' end,updated_at=now() where qr_project_id=NEW.qr_project_id;
  end if;
  return NEW;
end;
$$;
drop trigger if exists phase10_payment_delivery_refresh on public.payments;
create trigger phase10_payment_delivery_refresh after insert or update on public.payments for each row execute function public.refresh_delivery_after_payment();

create or replace function public.phase10_invoice_created()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  insert into public.activities(user_id,lead_id,company_id,type,title,description,metadata) values(auth.uid(),NEW.lead_id,NEW.company_id,'invoice_created','Invoice Created','Invoice foundation record created.',jsonb_build_object('invoice_id',NEW.id,'invoice_number',NEW.invoice_number));
  return NEW;
end;
$$;
drop trigger if exists phase10_invoice_created_trigger on public.invoices;
create trigger phase10_invoice_created_trigger after insert on public.invoices for each row execute function public.phase10_invoice_created();
