-- AI Agency CRM — Phase 9: Website & QR Production Engine
-- Extends existing Phase 2/4 foundations. No duplicate product tables are created.

-- Website lifecycle and production metadata.
alter table public.website_projects drop constraint if exists website_projects_status_check;
alter table public.website_projects add constraint website_projects_status_check check (status in (
  'pending','approved','collecting','information_required','generating','preview','preview_ready','review','client_review',
  'regeneration_requested','revision_requested','approved_final','payment_pending','ready_for_delivery','packaged','delivered','completed','cancelled','archived'
));
alter table public.website_projects add column if not exists project_data jsonb not null default '{}'::jsonb;
alter table public.website_projects add column if not exists preview_view_count integer not null default 0 check (preview_view_count >= 0);
alter table public.website_projects add column if not exists last_preview_viewed_at timestamptz;
alter table public.website_projects add column if not exists final_zip_size bigint check (final_zip_size is null or final_zip_size >= 0);
alter table public.website_projects add column if not exists final_zip_sha256 text;
alter table public.website_projects add column if not exists final_zip_generated_at timestamptz;
alter table public.website_projects add column if not exists delivery_status text not null default 'not_ready' check (delivery_status in ('not_ready','ready','delivered','failed'));
alter table public.website_projects add column if not exists delivery_notes text;
create index if not exists website_projects_delivery_status_idx on public.website_projects(delivery_status);

create table if not exists public.website_revision_requests (
  id uuid primary key default gen_random_uuid(),
  website_project_id uuid not null references public.website_projects(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete set null,
  company_id uuid references public.companies(id) on delete cascade,
  message text not null check (char_length(trim(message)) between 1 and 5000),
  requested_by text not null default 'client' check (requested_by in ('client','internal')),
  status text not null default 'requested' check (status in ('requested','in_progress','completed','cancelled')),
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists website_revision_requests_project_idx on public.website_revision_requests(website_project_id,created_at desc);
create index if not exists website_revision_requests_status_idx on public.website_revision_requests(status);
create trigger website_revision_requests_set_updated_at before update on public.website_revision_requests for each row execute function public.set_updated_at();
alter table public.website_revision_requests enable row level security;
drop policy if exists website_revision_requests_access on public.website_revision_requests;
create policy website_revision_requests_access on public.website_revision_requests for all to authenticated
using (
 public.current_user_role() in ('admin','manager')
 or exists(select 1 from public.leads l where l.id=website_revision_requests.lead_id and l.owner_id=auth.uid())
 or exists(select 1 from public.website_projects wp join public.leads l on l.id=wp.lead_id where wp.id=website_revision_requests.website_project_id and l.owner_id=auth.uid())
)
with check (
 public.current_user_role() in ('admin','manager')
 or exists(select 1 from public.leads l where l.id=website_revision_requests.lead_id and l.owner_id=auth.uid())
 or exists(select 1 from public.website_projects wp join public.leads l on l.id=wp.lead_id where wp.id=website_revision_requests.website_project_id and l.owner_id=auth.uid())
);

create table if not exists public.website_preview_views (
  id uuid primary key default gen_random_uuid(),
  website_project_id uuid not null references public.website_projects(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  user_agent text,
  source text default 'client_preview'
);
create index if not exists website_preview_views_project_idx on public.website_preview_views(website_project_id,viewed_at desc);
alter table public.website_preview_views enable row level security;
drop policy if exists website_preview_views_internal on public.website_preview_views;
create policy website_preview_views_internal on public.website_preview_views for select to authenticated using (
 public.current_user_role() in ('admin','manager')
 or exists(select 1 from public.website_projects wp join public.leads l on l.id=wp.lead_id where wp.id=website_preview_views.website_project_id and l.owner_id=auth.uid())
);

-- QR foundations already exist since Phase 2; extend them without duplicating tables.
alter table public.qr_templates add column if not exists key text;
update public.qr_templates set key=lower(regexp_replace(name,'[^a-z0-9]+','-','g')) where key is null;
update public.qr_templates set key='classic' where name ilike 'classic';
update public.qr_templates set key='modern' where name ilike 'modern';
update public.qr_templates set key='premium' where name ilike 'premium';
update public.qr_templates set key='template-'||left(id::text,8) where key is null or trim(key)='';
create unique index if not exists qr_templates_key_idx on public.qr_templates(key);
alter table public.qr_templates drop constraint if exists qr_templates_key_check;
alter table public.qr_templates add constraint qr_templates_key_check check (key ~ '^[a-z0-9][a-z0-9_-]{1,80}$');

alter table public.qr_projects add column if not exists deal_id uuid references public.deals(id) on delete set null;
alter table public.qr_projects add column if not exists project_name text;
alter table public.qr_projects add column if not exists created_by uuid references public.profiles(id) on delete set null;
alter table public.qr_projects add column if not exists destination_url text;
alter table public.qr_projects add column if not exists generated_at timestamptz;
alter table public.qr_projects add column if not exists svg_checksum text;
alter table public.qr_projects add column if not exists download_count integer not null default 0 check (download_count >= 0);
alter table public.qr_projects drop constraint if exists qr_projects_status_check;
alter table public.qr_projects add constraint qr_projects_status_check check (status in ('draft','pending','active','approved','collecting','generating','review','approved_final','packaged','delivered','archived'));
create index if not exists qr_projects_deal_id_idx on public.qr_projects(deal_id);
create index if not exists qr_projects_destination_url_idx on public.qr_projects(destination_url);
drop policy if exists qr_projects_access on public.qr_projects;
create policy qr_projects_access on public.qr_projects for all to authenticated
using (
 public.current_user_role() in ('admin','manager')
 or exists(select 1 from public.leads l where l.id=qr_projects.lead_id and l.owner_id=auth.uid())
 or exists(select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=qr_projects.deal_id and l.owner_id=auth.uid())
)
with check (
 public.current_user_role() in ('admin','manager')
 or exists(select 1 from public.leads l where l.id=qr_projects.lead_id and l.owner_id=auth.uid())
 or exists(select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=qr_projects.deal_id and l.owner_id=auth.uid())
);

insert into public.qr_templates(key,name,description,configuration,active) values
('classic','Classic','High-contrast, clean QR with restrained typography.','{"background":"#ffffff","foreground":"#171717","accent":"#171717","radius":0}'::jsonb,true),
('modern','Modern','Contemporary layout with generous whitespace and rounded framing.','{"background":"#ffffff","foreground":"#171717","accent":"#171717","radius":12}'::jsonb,true),
('premium','Premium','Editorial premium layout with restrained brand accents.','{"background":"#f7f4ec","foreground":"#171717","accent":"#7b6b52","radius":16}'::jsonb,true)
on conflict (key) do update set name=excluded.name,description=excluded.description,configuration=excluded.configuration,active=excluded.active;

-- Public preview access remains token-only. The RPCs expose no CRM row or credentials.
create or replace function public.get_website_preview(p_token text)
returns table(project_id uuid,company_name text,html text,expires_at timestamptz)
language sql security definer set search_path=public stable
as $$
  select wp.id,c.name,wp.rendered_html,wp.preview_expires_at
  from public.website_projects wp join public.companies c on c.id=wp.company_id
  where wp.preview_token_hash=encode(digest(p_token,'sha256'),'hex')
    and wp.preview_expires_at is not null and wp.preview_expires_at>now()
    and wp.status in ('preview','preview_ready','review','client_review','regeneration_requested','revision_requested','approved_final','payment_pending','ready_for_delivery','packaged','delivered','completed');
$$;
revoke all on function public.get_website_preview(text) from public;
grant execute on function public.get_website_preview(text) to anon,authenticated;

create or replace function public.record_website_preview_view(p_token text,p_user_agent text default null)
returns boolean language plpgsql security definer set search_path=public
as $$
declare v_id uuid;
begin
 select wp.id into v_id from public.website_projects wp where wp.preview_token_hash=encode(digest(p_token,'sha256'),'hex') and wp.preview_expires_at>now() and wp.status in ('preview','preview_ready','review','client_review','regeneration_requested','revision_requested','approved_final','payment_pending','ready_for_delivery','packaged','delivered','completed');
 if v_id is null then return false; end if;
 insert into public.website_preview_views(website_project_id,user_agent) values(v_id,left(p_user_agent,500));
 update public.website_projects set preview_view_count=preview_view_count+1,last_preview_viewed_at=now() where id=v_id;
 return true;
end; $$;
revoke all on function public.record_website_preview_view(text,text) from public;
grant execute on function public.record_website_preview_view(text,text) to anon,authenticated;

create or replace function public.client_review_website_preview(p_token text,p_action text,p_message text default null)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_row public.website_projects; v_revision uuid;
begin
 select * into v_row from public.website_projects where preview_token_hash=encode(digest(p_token,'sha256'),'hex') and preview_expires_at>now() and status in ('preview','preview_ready','review','client_review','regeneration_requested','revision_requested');
 if not found then raise exception 'Preview is unavailable or no longer accepting client review.' using errcode='42501'; end if;
 if p_action='approve' then
   update public.website_projects set client_approved_at=coalesce(client_approved_at,now()),status='payment_pending' where id=v_row.id returning * into v_row;
 elsif p_action='request_revision' then
   if char_length(trim(coalesce(p_message,'')))<1 then raise exception 'A revision message is required.'; end if;
   insert into public.website_revision_requests(website_project_id,lead_id,company_id,message,requested_by,context) values(v_row.id,v_row.lead_id,v_row.company_id,trim(p_message),'client',jsonb_build_object('preview_view_count',v_row.preview_view_count)) returning id into v_revision;
   update public.website_projects set status='revision_requested' where id=v_row.id returning * into v_row;
 else raise exception 'Unsupported review action.'; end if;
 return jsonb_build_object('project_id',v_row.id,'status',v_row.status,'revision_id',v_revision);
end; $$;
revoke all on function public.client_review_website_preview(text,text,text) from public;
grant execute on function public.client_review_website_preview(text,text,text) to anon,authenticated;

create or replace function public.mark_website_packaged(p_project_id uuid)
returns public.website_projects language plpgsql security definer set search_path=public
as $$
declare v_row public.website_projects;
begin
 update public.website_projects wp set status='ready_for_delivery',delivery_status='ready',package_generated_at=coalesce(package_generated_at,now())
 where wp.id=p_project_id
 and (public.current_user_role() in ('admin','manager') or exists(select 1 from public.leads l where l.id=wp.lead_id and l.owner_id=auth.uid()) or exists(select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=wp.deal_id and l.owner_id=auth.uid()))
 and wp.client_approved_at is not null and wp.first_payment_at is not null and wp.status not in ('delivered','completed','cancelled','archived');
 if not found then raise exception 'Website cannot be packaged: client approval and first payment are required.' using errcode='42501'; end if;
 select * into v_row from public.website_projects where id=p_project_id; return v_row;
end; $$;
revoke all on function public.mark_website_packaged(uuid) from public;
grant execute on function public.mark_website_packaged(uuid) to authenticated;

create or replace function public.mark_website_delivered(p_project_id uuid)
returns public.website_projects language plpgsql security definer set search_path=public
as $$
declare v_row public.website_projects;
begin
 update public.website_projects wp set status='delivered',delivery_status='delivered',delivered_at=coalesce(delivered_at,now())
 where wp.id=p_project_id
 and (public.current_user_role() in ('admin','manager') or exists(select 1 from public.leads l where l.id=wp.lead_id and l.owner_id=auth.uid()) or exists(select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=wp.deal_id and l.owner_id=auth.uid()) )
 and wp.status in ('ready_for_delivery','packaged');
 if not found then raise exception 'Website must be ready for delivery before it can be marked delivered.' using errcode='42501'; end if;
 select * into v_row from public.website_projects where id=p_project_id; return v_row;
end; $$;
revoke all on function public.mark_website_delivered(uuid) from public;
grant execute on function public.mark_website_delivered(uuid) to authenticated;

-- Keep schema.sql synchronized with the migration by adding the same Phase 9 objects there below this marker.

-- Reuse the existing Activities/Notifications systems for Phase 9 operational events.
create or replace function public.phase9_operational_event()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_title text; v_type text; v_message text; v_lead uuid; v_company uuid; v_project uuid; v_qr uuid;
begin
 if TG_TABLE_NAME='website_revision_requests' then
   v_title:='Revision Requested'; v_type:='revision_requested'; v_message:=left(NEW.message,240); v_lead:=NEW.lead_id; v_company:=NEW.company_id;
   insert into public.activities(user_id,lead_id,company_id,type,title,description,metadata) values(null,v_lead,v_company,v_type,v_title,v_message,jsonb_build_object('website_project_id',NEW.website_project_id,'revision_id',NEW.id));
 elsif TG_TABLE_NAME='website_projects' then
   if TG_OP='UPDATE' and NEW.preview_view_count>OLD.preview_view_count then v_title:='Client Viewed Preview'; v_type:='preview_viewed'; v_message:='The secure website preview was viewed.';
   elsif TG_OP='UPDATE' and NEW.client_approved_at is not null and OLD.client_approved_at is null then v_title:='Website Approved'; v_type:='approval_received'; v_message:='Client approval was recorded.';
   elsif TG_OP='UPDATE' and NEW.delivery_status='ready' and OLD.delivery_status is distinct from 'ready' then v_title:='Website Ready for Delivery'; v_type:='ready_for_delivery'; v_message:='Payment and approval gates are satisfied.';
   else return NEW; end if;
   insert into public.activities(user_id,lead_id,company_id,type,title,description,metadata) values(null,NEW.lead_id,NEW.company_id,v_type,v_title,v_message,jsonb_build_object('website_project_id',NEW.id,'status',NEW.status));
 elsif TG_TABLE_NAME='qr_projects' then
   v_title:=case when TG_OP='INSERT' then 'QR Project Created' else 'QR Project Updated' end; v_type:=case when TG_OP='INSERT' then 'qr_project_created' else 'qr_updated' end; v_message:='QR production record updated.'; v_lead:=NEW.lead_id; v_company:=NEW.company_id; v_qr:=NEW.id;
   insert into public.activities(user_id,lead_id,company_id,type,title,description,metadata) values(null,v_lead,v_company,v_type,v_title,v_message,jsonb_build_object('qr_project_id',v_qr,'status',NEW.status));
 end if;
 for v_project in select id from public.profiles where role in ('admin','manager') loop
   insert into public.notifications(user_id,type,title,message,lead_id,company_id) values(v_project,v_type,v_title,v_message,v_lead,v_company);
 end loop;
 if v_lead is not null then
   for v_project in select owner_id from public.leads where id=v_lead and owner_id is not null loop
     if not exists(select 1 from public.notifications where user_id=v_project and type=v_type and title=v_title and lead_id=v_lead and created_at>now()-interval '2 seconds') then
       insert into public.notifications(user_id,type,title,message,lead_id,company_id) values(v_project,v_type,v_title,v_message,v_lead,v_company);
     end if;
   end loop;
 end if;
 return NEW;
end; $$;

 drop trigger if exists phase9_revision_event on public.website_revision_requests;
 create trigger phase9_revision_event after insert on public.website_revision_requests for each row execute function public.phase9_operational_event();
 drop trigger if exists phase9_website_event on public.website_projects;
 create trigger phase9_website_event after update on public.website_projects for each row execute function public.phase9_operational_event();
 drop trigger if exists phase9_qr_event on public.qr_projects;
 create trigger phase9_qr_event after insert or update on public.qr_projects for each row execute function public.phase9_operational_event();
