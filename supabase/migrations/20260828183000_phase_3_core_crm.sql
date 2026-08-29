-- Phase 3: core CRM operational workflow additions
alter table public.companies add column if not exists archived_at timestamptz;
alter table public.leads add column if not exists archived_at timestamptz;
create index if not exists companies_archived_at_idx on public.companies(archived_at);
create index if not exists leads_archived_at_idx on public.leads(archived_at);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null check (char_length(trim(type)) between 1 and 100),
  title text not null check (char_length(trim(title)) between 1 and 200),
  message text,
  lead_id uuid references public.leads(id) on delete cascade,
  company_id uuid references public.companies(id) on delete cascade,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_created_idx on public.notifications(user_id,created_at desc);
create index if not exists notifications_unread_idx on public.notifications(user_id,read_at) where read_at is null;
alter table public.notifications enable row level security;
create policy notifications_select on public.notifications for select to authenticated using(user_id=auth.uid() or public.current_user_role() in ('admin','manager'));
create policy notifications_insert on public.notifications for insert to authenticated with check(user_id=auth.uid() or public.current_user_role() in ('admin','manager'));
create policy notifications_update on public.notifications for update to authenticated using(user_id=auth.uid() or public.current_user_role() in ('admin','manager')) with check(user_id=auth.uid() or public.current_user_role() in ('admin','manager'));

-- Align initial catalog with Phase 3 commercial naming.
update public.services set name='Site Vitrine',description='Professional showcase website for a business.',price=1500 where name='Website Vitrine';
update public.services set name='Site Professionnel',description='Advanced professional business website.',price=2500 where name='Website Professionnel';
insert into public.services(name,description,price,currency,active) values
('Site Vitrine','Professional showcase website for a business.',1500,'MAD',true),
('Site Professionnel','Advanced professional business website.',2500,'MAD',true),
('Google Review QR Code','Branded QR code package for Google reviews.',50,'MAD',true)
on conflict(name) do update set description=excluded.description,price=excluded.price,currency=excluded.currency,active=excluded.active;

drop policy if exists companies_select on public.companies;
create policy companies_select on public.companies for select to authenticated using (public.current_user_role() in ('admin','manager','sales'));
