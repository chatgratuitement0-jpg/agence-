-- AI Agency CRM — Phase 4: Website production, preview and controlled delivery
-- Apply after Phase 3.

create table if not exists public.website_templates (
  id uuid primary key default gen_random_uuid(),
  key text not null unique check (key ~ '^[a-z0-9][a-z0-9_-]{1,80}$'),
  name text not null unique check (char_length(trim(name)) between 1 and 160),
  description text,
  service_type text not null default 'Site Vitrine',
  version integer not null default 1 check (version > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.website_projects add column if not exists template_id uuid references public.website_templates(id) on delete set null;
alter table public.website_projects add column if not exists deal_id uuid references public.deals(id) on delete set null;
alter table public.website_projects add column if not exists intake_completed_at timestamptz;
alter table public.website_projects add column if not exists client_approved_at timestamptz;
alter table public.website_projects add column if not exists first_payment_at timestamptz;
alter table public.website_projects add column if not exists last_generation_at timestamptz;
alter table public.website_projects add column if not exists package_generated_at timestamptz;
alter table public.website_projects add column if not exists delivered_at timestamptz;
alter table public.website_projects add column if not exists rendered_html text;
alter table public.website_projects add column if not exists preview_token_hash text;
alter table public.website_projects add column if not exists preview_expires_at timestamptz;

alter table public.website_projects drop constraint if exists website_projects_status_check;
alter table public.website_projects add constraint website_projects_status_check check (status in ('pending','approved','collecting','generating','preview','review','regeneration_requested','approved_final','payment_pending','packaged','delivered'));

create unique index if not exists website_projects_preview_token_hash_idx on public.website_projects(preview_token_hash) where preview_token_hash is not null;
create index if not exists website_projects_template_id_idx on public.website_projects(template_id);
create index if not exists website_projects_deal_id_idx on public.website_projects(deal_id);
create index if not exists website_projects_preview_expires_idx on public.website_projects(preview_expires_at);

create trigger website_templates_set_updated_at before update on public.website_templates for each row execute function public.set_updated_at();

insert into public.website_templates(key,name,description,service_type,version,active) values
('vitrine-modern','Vitrine Modern','Clean, conversion-focused showcase template for local businesses.','Site Vitrine',1,true),
('professional-corporate','Professional Corporate','Structured professional template for businesses needing a stronger corporate presence.','Site Professionnel',1,true)
on conflict(key) do update set name=excluded.name,description=excluded.description,service_type=excluded.service_type,version=excluded.version,active=excluded.active;

alter table public.website_templates enable row level security;
create policy website_templates_select on public.website_templates for select to authenticated using (active=true or public.current_user_role() in ('admin','manager'));
create policy website_templates_manage on public.website_templates for all to authenticated using (public.current_user_role() in ('admin','manager')) with check (public.current_user_role() in ('admin','manager'));

-- Re-define website project access so a project is also accessible when it is linked directly to an owned deal.
drop policy if exists website_projects_access on public.website_projects;
create policy website_projects_access on public.website_projects for all to authenticated
using (
  public.current_user_role() in ('admin','manager')
  or exists (select 1 from public.leads l where l.id = website_projects.lead_id and l.owner_id = auth.uid())
  or exists (select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=website_projects.deal_id and l.owner_id=auth.uid())
)
with check (
  public.current_user_role() in ('admin','manager')
  or exists (select 1 from public.leads l where l.id = website_projects.lead_id and l.owner_id = auth.uid())
  or exists (select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=website_projects.deal_id and l.owner_id=auth.uid())
);

create or replace function public.issue_website_preview_token(p_project_id uuid)
returns text language plpgsql security definer set search_path=public
as $$
declare v_token text; v_allowed boolean;
begin
  select exists(
    select 1 from public.website_projects wp
    where wp.id=p_project_id and (
      public.current_user_role() in ('admin','manager')
      or exists(select 1 from public.leads l where l.id=wp.lead_id and l.owner_id=auth.uid())
    )
  ) into v_allowed;
  if not v_allowed then raise exception 'Not authorized to issue a preview token.' using errcode='42501'; end if;
  v_token=encode(gen_random_bytes(32),'hex');
  update public.website_projects set preview_token_hash=encode(digest(v_token,'sha256'),'hex'), preview_expires_at=now()+interval '14 days' where id=p_project_id;
  return v_token;
end;
$$;
revoke all on function public.issue_website_preview_token(uuid) from public;
grant execute on function public.issue_website_preview_token(uuid) to authenticated;

create or replace function public.get_website_preview(p_token text)
returns table(project_id uuid,company_name text,html text,expires_at timestamptz)
language sql security definer set search_path=public stable
as $$
  select wp.id,c.name,wp.rendered_html,wp.preview_expires_at
  from public.website_projects wp
  join public.companies c on c.id=wp.company_id
  where wp.preview_token_hash=encode(digest(p_token,'sha256'),'hex')
    and wp.preview_expires_at is not null
    and wp.preview_expires_at > now()
    and wp.status in ('preview','review','approved_final','payment_pending','packaged','delivered');
$$;
revoke all on function public.get_website_preview(text) from public;
grant execute on function public.get_website_preview(text) to anon, authenticated;

create or replace function public.mark_website_packaged(p_project_id uuid)
returns public.website_projects language plpgsql security definer set search_path=public
as $$
declare v_row public.website_projects;
begin
  update public.website_projects wp set status='packaged',package_generated_at=coalesce(package_generated_at,now())
  where wp.id=p_project_id
    and (public.current_user_role() in ('admin','manager') or exists(select 1 from public.leads l where l.id=wp.lead_id and l.owner_id=auth.uid()))
    and wp.client_approved_at is not null
    and wp.first_payment_at is not null
    and wp.status not in ('delivered');
  if not found then raise exception 'Website cannot be packaged: client approval and first payment are required.' using errcode='42501'; end if;
  select * into v_row from public.website_projects where id=p_project_id;
  return v_row;
end;
$$;
revoke all on function public.mark_website_packaged(uuid) from public;
grant execute on function public.mark_website_packaged(uuid) to authenticated;

create or replace function public.record_website_first_payment(p_project_id uuid,p_amount numeric,p_method text default 'manual')
returns public.website_projects language plpgsql security definer set search_path=public
as $$
declare v_row public.website_projects; v_deal uuid;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'Payment amount must be positive.'; end if;
  if not exists (select 1 from public.website_projects wp where wp.id=p_project_id and wp.client_approved_at is not null) then
    raise exception 'First payment cannot be recorded before client approval.' using errcode='42501';
  end if;
  select wp.deal_id into v_deal from public.website_projects wp
  where wp.id=p_project_id and (public.current_user_role() in ('admin','manager') or exists(select 1 from public.leads l where l.id=wp.lead_id and l.owner_id=auth.uid()));
  if not found then raise exception 'Not authorized to record this payment.' using errcode='42501'; end if;
  if v_deal is null then
    insert into public.deals(lead_id,service_id,value,currency,status,probability,notes)
    select lead_id,service_id,p_amount,'MAD','open',100,'Website project '||id from public.website_projects where id=p_project_id returning id into v_deal;
    update public.website_projects set deal_id=v_deal where id=p_project_id;
  end if;
  insert into public.payments(deal_id,amount,currency,status,payment_method,paid_at) values(v_deal,p_amount,'MAD','paid',coalesce(nullif(trim(p_method),''),'manual'),now());
  update public.website_projects set first_payment_at=coalesce(first_payment_at,now()),status='approved_final' where id=p_project_id;
  select * into v_row from public.website_projects where id=p_project_id;
  return v_row;
end;
$$;
revoke all on function public.record_website_first_payment(uuid,numeric,text) from public;
grant execute on function public.record_website_first_payment(uuid,numeric,text) to authenticated;


create or replace function public.mark_website_delivered(p_project_id uuid)
returns public.website_projects language plpgsql security definer set search_path=public
as $$
declare v_row public.website_projects;
begin
  update public.website_projects wp set status='delivered',delivered_at=coalesce(delivered_at,now())
  where wp.id=p_project_id
    and (public.current_user_role() in ('admin','manager') or exists(select 1 from public.leads l where l.id=wp.lead_id and l.owner_id=auth.uid()))
    and wp.status='packaged';
  if not found then raise exception 'Website must be packaged before it can be marked delivered.' using errcode='42501'; end if;
  select * into v_row from public.website_projects where id=p_project_id;
  return v_row;
end;
$$;
revoke all on function public.mark_website_delivered(uuid) from public;
grant execute on function public.mark_website_delivered(uuid) to authenticated;
