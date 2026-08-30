-- Complete QR production + client review + paid delivery metadata.
alter table public.qr_projects add column if not exists project_name text;
alter table public.qr_projects add column if not exists preview_token_hash text;
alter table public.qr_projects add column if not exists preview_expires_at timestamptz;
alter table public.qr_projects add column if not exists rendered_svg text;
alter table public.qr_projects add column if not exists package_path text;
alter table public.qr_projects add column if not exists package_size bigint;
alter table public.qr_projects add column if not exists package_sha256 text;
alter table public.qr_projects add column if not exists package_generated_at timestamptz;
alter table public.qr_projects add column if not exists client_approved_at timestamptz;
alter table public.qr_projects add column if not exists first_payment_at timestamptz;
alter table public.qr_projects add column if not exists delivery_status text not null default 'not_ready';
alter table public.qr_projects add column if not exists delivery_notes text;

alter table public.qr_projects drop constraint if exists qr_projects_delivery_status_check;
alter table public.qr_projects add constraint qr_projects_delivery_status_check check (delivery_status in ('not_ready','ready','delivered','failed'));
create unique index if not exists qr_projects_preview_token_hash_idx on public.qr_projects(preview_token_hash) where preview_token_hash is not null;
create index if not exists qr_projects_package_path_idx on public.qr_projects(package_path) where package_path is not null;

create or replace function public.get_qr_preview(p_token text)
returns table(project_id uuid,project_name text,destination_url text,svg text,expires_at timestamptz,status text)
language sql security definer set search_path=public stable
as $$
  select q.id,q.project_name,q.destination_url,q.rendered_svg,q.preview_expires_at,q.status
  from public.qr_projects q
  where q.preview_token_hash=encode(digest(p_token,'sha256'),'hex')
    and q.preview_expires_at is not null
    and q.preview_expires_at>now()
    and q.status not in ('archived');
$$;
revoke all on function public.get_qr_preview(text) from public;
grant execute on function public.get_qr_preview(text) to anon,authenticated;

create or replace function public.mark_qr_ready_for_delivery(p_project_id uuid)
returns public.qr_projects language plpgsql security definer set search_path=public
as $$
declare v_row public.qr_projects;
begin
 update public.qr_projects q set delivery_status='ready'
 where q.id=p_project_id
 and q.client_approved_at is not null
 and q.first_payment_at is not null
 and q.package_path is not null
 and (public.current_user_role() in ('admin','manager') or exists(select 1 from public.leads l where l.id=q.lead_id and l.owner_id=auth.uid()) or exists(select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=q.deal_id and l.owner_id=auth.uid()));
 if not found then raise exception 'QR cannot be marked ready: approval, first payment and package are required.' using errcode='42501'; end if;
 select * into v_row from public.qr_projects where id=p_project_id;
 return v_row;
end; $$;
revoke all on function public.mark_qr_ready_for_delivery(uuid) from public;
grant execute on function public.mark_qr_ready_for_delivery(uuid) to authenticated;

create or replace function public.mark_qr_delivered(p_project_id uuid)
returns public.qr_projects language plpgsql security definer set search_path=public
as $$
declare v_row public.qr_projects;
begin
 update public.qr_projects q set status='delivered',delivery_status='delivered',delivery_notes='QR package delivered.'
 where q.id=p_project_id and q.delivery_status in ('ready','delivered')
 and (public.current_user_role() in ('admin','manager') or exists(select 1 from public.leads l where l.id=q.lead_id and l.owner_id=auth.uid()) or exists(select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=q.deal_id and l.owner_id=auth.uid()));
 if not found then raise exception 'QR must be ready before delivery.' using errcode='42501'; end if;
 select * into v_row from public.qr_projects where id=p_project_id;
 return v_row;
end; $$;
revoke all on function public.mark_qr_delivered(uuid) from public;
grant execute on function public.mark_qr_delivered(uuid) to authenticated;
