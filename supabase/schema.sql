-- AI Agency CRM — Phase 2 database foundation
-- Run this file in Supabase SQL Editor.

create extension if not exists pgcrypto;

create type public.user_role as enum ('admin','manager','sales');
create type public.lead_status as enum ('new','qualified','interested','negotiating','payment','won','lost');
create type public.priority_level as enum ('high','medium','low');
create type public.opportunity_severity as enum ('low','medium','high');
create type public.conversation_channel as enum ('email','whatsapp','sms','instagram','manual');
create type public.conversation_status as enum ('active','waiting','closed','human_required');
create type public.sender_type as enum ('lead','human','ai');
create type public.outreach_channel as enum ('email','whatsapp','sms','instagram');
create type public.outreach_status as enum ('draft','active','paused','completed');
create type public.outreach_message_status as enum ('pending','sent','delivered','opened','replied','failed');
create type public.deal_status as enum ('open','negotiating','won','lost');
create type public.payment_status as enum ('pending','paid','failed','refunded');
create type public.integration_status as enum ('not_connected','connected','error','disabled');

create or replace function public.set_updated_at()
returns trigger language plpgsql security invoker set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  avatar_url text,
  role public.user_role not null default 'sales',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 200),
  industry text,
  description text,
  city text,
  country text,
  address text,
  latitude double precision check (latitude is null or latitude between -90 and 90),
  longitude double precision check (longitude is null or longitude between -180 and 180),
  phone text,
  email text,
  website text,
  instagram text,
  facebook text,
  linkedin text,
  google_maps_url text,
  source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Normalized/partial uniqueness prevents obvious duplicates while allowing missing contact data.
create unique index companies_name_city_country_unique
  on public.companies (lower(trim(name)), lower(coalesce(city,'')), lower(coalesce(country,'')));

create table public.leads (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  name text not null check (char_length(trim(name)) between 1 and 200),
  status public.lead_status not null default 'new',
  score integer not null default 0 check (score between 0 and 100),
  priority public.priority_level not null default 'medium',
  source text,
  recommended_service text,
  notes text,
  owner_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.lead_opportunities (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references public.leads(id) on delete cascade,
  type text not null check (char_length(trim(type)) between 1 and 100),
  title text not null check (char_length(trim(title)) between 1 and 200),
  description text,
  severity public.opportunity_severity not null default 'medium',
  created_at timestamptz not null default now()
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references public.leads(id) on delete cascade,
  channel public.conversation_channel not null,
  status public.conversation_status not null default 'active',
  assigned_to uuid references public.profiles(id) on delete set null,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_type public.sender_type not null,
  sender_id uuid references public.profiles(id) on delete set null,
  message text not null check (char_length(trim(message)) > 0),
  channel public.conversation_channel not null,
  ai_generated boolean not null default false,
  created_at timestamptz not null default now(),
  constraint messages_human_sender_check check (sender_type <> 'human' or sender_id is not null)
);

create table public.outreach_campaigns (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 200),
  channel public.outreach_channel not null,
  status public.outreach_status not null default 'draft',
  message_template text not null check (char_length(trim(message_template)) > 0),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.outreach_messages (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.outreach_campaigns(id) on delete cascade,
  lead_id uuid not null references public.leads(id) on delete cascade,
  channel public.outreach_channel not null,
  message text not null check (char_length(trim(message)) > 0),
  status public.outreach_message_status not null default 'pending',
  sent_at timestamptz,
  opened_at timestamptz,
  replied_at timestamptz
);

create table public.services (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (char_length(trim(name)) between 1 and 200),
  description text,
  price numeric(12,2) not null check (price >= 0),
  currency text not null default 'MAD' check (char_length(currency) = 3),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.deals (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references public.leads(id) on delete cascade,
  service_id uuid not null references public.services(id) on delete restrict,
  value numeric(12,2) not null check (value >= 0),
  currency text not null default 'MAD' check (char_length(currency) = 3),
  status public.deal_status not null default 'open',
  probability integer not null default 50 check (probability between 0 and 100),
  expected_close_date date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.deals(id) on delete cascade,
  amount numeric(12,2) not null check (amount >= 0),
  currency text not null default 'MAD' check (char_length(currency) = 3),
  status public.payment_status not null default 'pending',
  payment_method text,
  transaction_id text,
  paid_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.activities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete set null,
  lead_id uuid references public.leads(id) on delete cascade,
  company_id uuid references public.companies(id) on delete cascade,
  type text not null check (char_length(trim(type)) between 1 and 100),
  title text not null check (char_length(trim(title)) between 1 and 200),
  description text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint activities_parent_check check (lead_id is not null or company_id is not null)
);

create table public.ai_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  enabled boolean not null default false,
  model text,
  system_prompt text,
  auto_reply boolean not null default false,
  qualification_enabled boolean not null default false,
  scoring_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.integrations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null check (provider in ('OpenAI','WhatsApp','Email','SMS','Instagram','Stripe','n8n','Make')),
  status public.integration_status not null default 'not_connected',
  configuration jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, provider)
);

-- Future website-generation and QR delivery foundations. These are internal records only;
-- no external generation API is connected in Phase 2.
create table public.website_projects (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid references public.leads(id) on delete set null,
  company_id uuid not null references public.companies(id) on delete cascade,
  service_id uuid references public.services(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','approved','collecting','generating','preview','review','regeneration_requested','approved_final','packaged','delivered')),
  business_data jsonb not null default '{}'::jsonb,
  preview_url text,
  package_path text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.qr_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  configuration jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.qr_projects (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid references public.leads(id) on delete set null,
  company_id uuid not null references public.companies(id) on delete cascade,
  service_id uuid references public.services(id) on delete set null,
  template_id uuid references public.qr_templates(id) on delete set null,
  review_url text,
  branding jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','approved','collecting','generating','review','approved_final','packaged','delivered')),
  asset_path text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index companies_industry_idx on public.companies (industry);
create index companies_city_idx on public.companies (city);
create index leads_status_idx on public.leads (status);
create index leads_priority_idx on public.leads (priority);
create index leads_score_idx on public.leads (score);
create index leads_owner_id_idx on public.leads (owner_id);
create index leads_company_id_idx on public.leads (company_id);
create index lead_opportunities_lead_id_idx on public.lead_opportunities (lead_id);
create index conversations_lead_id_idx on public.conversations (lead_id);
create index conversations_status_idx on public.conversations (status);
create index conversations_last_message_at_idx on public.conversations (last_message_at desc);
create index messages_conversation_id_idx on public.messages (conversation_id);
create index messages_created_at_idx on public.messages (created_at desc);
create index outreach_campaigns_created_by_idx on public.outreach_campaigns (created_by);
create index outreach_messages_campaign_id_idx on public.outreach_messages (campaign_id);
create index outreach_messages_lead_id_idx on public.outreach_messages (lead_id);
create index deals_lead_id_idx on public.deals (lead_id);
create index deals_status_idx on public.deals (status);
create index payments_deal_id_idx on public.payments (deal_id);
create index payments_status_idx on public.payments (status);
create index activities_created_at_idx on public.activities (created_at desc);
create index activities_lead_id_idx on public.activities (lead_id);
create index activities_company_id_idx on public.activities (company_id);
create index ai_settings_user_id_idx on public.ai_settings (user_id);
create index integrations_provider_idx on public.integrations (provider);
create index website_projects_company_id_idx on public.website_projects (company_id);
create index website_projects_status_idx on public.website_projects (status);
create index qr_projects_company_id_idx on public.qr_projects (company_id);
create index qr_projects_status_idx on public.qr_projects (status);

create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger companies_set_updated_at before update on public.companies for each row execute function public.set_updated_at();
create trigger leads_set_updated_at before update on public.leads for each row execute function public.set_updated_at();
create trigger conversations_set_updated_at before update on public.conversations for each row execute function public.set_updated_at();
create trigger outreach_campaigns_set_updated_at before update on public.outreach_campaigns for each row execute function public.set_updated_at();
create trigger services_set_updated_at before update on public.services for each row execute function public.set_updated_at();
create trigger deals_set_updated_at before update on public.deals for each row execute function public.set_updated_at();
create trigger ai_settings_set_updated_at before update on public.ai_settings for each row execute function public.set_updated_at();
create trigger integrations_set_updated_at before update on public.integrations for each row execute function public.set_updated_at();
create trigger website_projects_set_updated_at before update on public.website_projects for each row execute function public.set_updated_at();
create trigger qr_templates_set_updated_at before update on public.qr_templates for each row execute function public.set_updated_at();
create trigger qr_projects_set_updated_at before update on public.qr_projects for each row execute function public.set_updated_at();

-- Profile creation after Supabase Auth signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, avatar_url)
  values (new.id, new.email, new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'avatar_url')
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Role helper is SECURITY DEFINER to avoid recursive profiles RLS checks.
create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

revoke all on function public.current_user_role() from public;
grant execute on function public.current_user_role() to authenticated;

-- Seed only the agency's initial service catalog. Safe to re-run.
insert into public.services (name, description, price, currency, active)
values
 ('Website Vitrine', 'Professional showcase website for a business.', 1500, 'MAD', true),
 ('Website Professionnel', 'More advanced professional business website.', 2500, 'MAD', true),
 ('Google Review QR Code', 'Branded QR code package for Google reviews.', 50, 'MAD', true)
on conflict (name) do update set description = excluded.description, price = excluded.price, currency = excluded.currency, active = excluded.active;

-- RLS: no anonymous access. Admin/manager have broad CRM access; sales are scoped to owned/assigned leads.
alter table public.profiles enable row level security;
alter table public.companies enable row level security;
alter table public.leads enable row level security;
alter table public.lead_opportunities enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.outreach_campaigns enable row level security;
alter table public.outreach_messages enable row level security;
alter table public.services enable row level security;
alter table public.deals enable row level security;
alter table public.payments enable row level security;
alter table public.activities enable row level security;
alter table public.ai_settings enable row level security;
alter table public.integrations enable row level security;
alter table public.website_projects enable row level security;
alter table public.qr_templates enable row level security;
alter table public.qr_projects enable row level security;

-- Profiles: users can read their own profile; admin/manager can manage profiles.
create policy profiles_select on public.profiles for select to authenticated
using (id = auth.uid() or public.current_user_role() in ('admin','manager'));
create policy profiles_insert on public.profiles for insert to authenticated
with check (id = auth.uid() or public.current_user_role() in ('admin','manager'));
create policy profiles_update on public.profiles for update to authenticated
using (id = auth.uid() or public.current_user_role() in ('admin','manager'))
with check (id = auth.uid() or public.current_user_role() in ('admin','manager'));

-- Companies are shared CRM records. Sales may access companies linked to their leads.
create policy companies_select on public.companies for select to authenticated
using (public.current_user_role() in ('admin','manager','sales'));
create policy companies_insert on public.companies for insert to authenticated
with check (public.current_user_role() in ('admin','manager','sales'));
create policy companies_update on public.companies for update to authenticated
using (public.current_user_role() in ('admin','manager') or exists (select 1 from public.leads l where l.company_id = companies.id and l.owner_id = auth.uid()))
with check (public.current_user_role() in ('admin','manager','sales'));
create policy companies_delete on public.companies for delete to authenticated
using (public.current_user_role() in ('admin','manager'));

create policy leads_select on public.leads for select to authenticated
using (public.current_user_role() in ('admin','manager') or owner_id = auth.uid());
create policy leads_insert on public.leads for insert to authenticated
with check (public.current_user_role() in ('admin','manager') or owner_id = auth.uid());
create policy leads_update on public.leads for update to authenticated
using (public.current_user_role() in ('admin','manager') or owner_id = auth.uid())
with check (public.current_user_role() in ('admin','manager') or owner_id = auth.uid());
create policy leads_delete on public.leads for delete to authenticated
using (public.current_user_role() in ('admin','manager') or owner_id = auth.uid());

create policy opportunities_access on public.lead_opportunities for all to authenticated
using (public.current_user_role() in ('admin','manager') or exists (select 1 from public.leads l where l.id = lead_opportunities.lead_id and l.owner_id = auth.uid()))
with check (public.current_user_role() in ('admin','manager') or exists (select 1 from public.leads l where l.id = lead_opportunities.lead_id and l.owner_id = auth.uid()));

create policy conversations_access on public.conversations for all to authenticated
using (public.current_user_role() in ('admin','manager') or assigned_to = auth.uid() or exists (select 1 from public.leads l where l.id = conversations.lead_id and l.owner_id = auth.uid()))
with check (public.current_user_role() in ('admin','manager') or assigned_to = auth.uid() or exists (select 1 from public.leads l where l.id = conversations.lead_id and l.owner_id = auth.uid()));

create policy messages_access on public.messages for all to authenticated
using (public.current_user_role() in ('admin','manager') or exists (select 1 from public.conversations c join public.leads l on l.id = c.lead_id where c.id = messages.conversation_id and (c.assigned_to = auth.uid() or l.owner_id = auth.uid())))
with check (public.current_user_role() in ('admin','manager') or exists (select 1 from public.conversations c join public.leads l on l.id = c.lead_id where c.id = messages.conversation_id and (c.assigned_to = auth.uid() or l.owner_id = auth.uid())));

create policy campaigns_access on public.outreach_campaigns for all to authenticated
using (public.current_user_role() in ('admin','manager') or created_by = auth.uid())
with check (public.current_user_role() in ('admin','manager') or created_by = auth.uid());
create policy outreach_messages_access on public.outreach_messages for all to authenticated
using (public.current_user_role() in ('admin','manager') or exists (select 1 from public.leads l where l.id = outreach_messages.lead_id and l.owner_id = auth.uid()))
with check (public.current_user_role() in ('admin','manager') or exists (select 1 from public.leads l where l.id = outreach_messages.lead_id and l.owner_id = auth.uid()));

create policy services_select on public.services for select to authenticated using (true);
create policy services_manage on public.services for all to authenticated
using (public.current_user_role() in ('admin','manager'))
with check (public.current_user_role() in ('admin','manager'));

create policy deals_access on public.deals for all to authenticated
using (public.current_user_role() in ('admin','manager') or exists (select 1 from public.leads l where l.id = deals.lead_id and l.owner_id = auth.uid()))
with check (public.current_user_role() in ('admin','manager') or exists (select 1 from public.leads l where l.id = deals.lead_id and l.owner_id = auth.uid()));
create policy payments_access on public.payments for all to authenticated
using (public.current_user_role() in ('admin','manager') or exists (select 1 from public.deals d join public.leads l on l.id = d.lead_id where d.id = payments.deal_id and l.owner_id = auth.uid()))
with check (public.current_user_role() in ('admin','manager') or exists (select 1 from public.deals d join public.leads l on l.id = d.lead_id where d.id = payments.deal_id and l.owner_id = auth.uid()));

create policy activities_select on public.activities for select to authenticated
using (public.current_user_role() in ('admin','manager') or user_id = auth.uid() or exists (select 1 from public.leads l where l.id = activities.lead_id and l.owner_id = auth.uid()) or exists (select 1 from public.leads l where l.company_id = activities.company_id and l.owner_id = auth.uid()));
create policy activities_insert on public.activities for insert to authenticated
with check (user_id = auth.uid() or public.current_user_role() in ('admin','manager'));

create policy ai_settings_access on public.ai_settings for all to authenticated
using (user_id = auth.uid() or public.current_user_role() in ('admin','manager'))
with check (user_id = auth.uid() or public.current_user_role() in ('admin','manager'));
create policy integrations_access on public.integrations for all to authenticated
using (user_id = auth.uid() or public.current_user_role() in ('admin','manager'))
with check (user_id = auth.uid() or public.current_user_role() in ('admin','manager'));

create policy website_projects_access on public.website_projects for all to authenticated
using (public.current_user_role() in ('admin','manager') or exists (select 1 from public.leads l where l.id = website_projects.lead_id and l.owner_id = auth.uid()))
with check (public.current_user_role() in ('admin','manager') or exists (select 1 from public.leads l where l.id = website_projects.lead_id and l.owner_id = auth.uid()));
create policy qr_templates_select on public.qr_templates for select to authenticated using (true);
create policy qr_templates_manage on public.qr_templates for all to authenticated
using (public.current_user_role() in ('admin','manager'))
with check (public.current_user_role() in ('admin','manager'));
create policy qr_projects_access on public.qr_projects for all to authenticated
using (public.current_user_role() in ('admin','manager') or exists (select 1 from public.leads l where l.id = qr_projects.lead_id and l.owner_id = auth.uid()))
with check (public.current_user_role() in ('admin','manager') or exists (select 1 from public.leads l where l.id = qr_projects.lead_id and l.owner_id = auth.uid()));

-- Storage is intentionally not provisioned here: bucket ownership and private delivery policies
-- should be added with the later website/asset delivery phase.
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
      or exists(select 1 from public.deals d join public.leads l on l.id=d.lead_id where d.id=wp.deal_id and l.owner_id=auth.uid())
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
    and wp.status in ('preview','preview_ready','review','client_review','regeneration_requested','revision_requested','approved_final','payment_pending','ready_for_delivery','packaged','delivered','completed');
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
-- AI Agency CRM — Phase 5 enum extensions.
-- Kept in its own migration so new enum values are committed before columns/functions use them.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_status'::regtype AND enumlabel='scheduled') THEN ALTER TYPE public.outreach_status ADD VALUE 'scheduled'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_status'::regtype AND enumlabel='running') THEN ALTER TYPE public.outreach_status ADD VALUE 'running'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_status'::regtype AND enumlabel='cancelled') THEN ALTER TYPE public.outreach_status ADD VALUE 'cancelled'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_message_status'::regtype AND enumlabel='draft') THEN ALTER TYPE public.outreach_message_status ADD VALUE 'draft'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_message_status'::regtype AND enumlabel='queued') THEN ALTER TYPE public.outreach_message_status ADD VALUE 'queued'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_message_status'::regtype AND enumlabel='bounced') THEN ALTER TYPE public.outreach_message_status ADD VALUE 'bounced'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_message_status'::regtype AND enumlabel='cancelled') THEN ALTER TYPE public.outreach_message_status ADD VALUE 'cancelled'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.conversation_status'::regtype AND enumlabel='open') THEN ALTER TYPE public.conversation_status ADD VALUE 'open'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.conversation_status'::regtype AND enumlabel='qualified') THEN ALTER TYPE public.conversation_status ADD VALUE 'qualified'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.conversation_status'::regtype AND enumlabel='handoff') THEN ALTER TYPE public.conversation_status ADD VALUE 'handoff'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.conversation_status'::regtype AND enumlabel='archived') THEN ALTER TYPE public.conversation_status ADD VALUE 'archived'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.conversation_channel'::regtype AND enumlabel='other') THEN ALTER TYPE public.conversation_channel ADD VALUE 'other'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid='public.outreach_channel'::regtype AND enumlabel='other') THEN ALTER TYPE public.outreach_channel ADD VALUE 'other'; END IF;
END $$;

-- AI Agency CRM — Phase 5: Communication, outreach & conversation workflows
-- Apply after Phase 4. Extends existing enums/tables; no duplicate CRM systems.


-- Reusable outbound message templates.
CREATE TABLE IF NOT EXISTS public.message_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 160),
  channel public.outreach_channel NOT NULL DEFAULT 'email',
  subject text,
  body text NOT NULL CHECK (char_length(trim(body)) > 0),
  service_id uuid REFERENCES public.services(id) ON DELETE SET NULL,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  archived_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.outreach_campaign_targets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.outreach_campaigns(id) ON DELETE CASCADE,
  lead_id uuid REFERENCES public.leads(id) ON DELETE CASCADE,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT campaign_target_parent_check CHECK (lead_id IS NOT NULL OR company_id IS NOT NULL),
  CONSTRAINT campaign_target_unique_lead UNIQUE (campaign_id, lead_id),
  CONSTRAINT campaign_target_unique_company UNIQUE (campaign_id, company_id)
);

ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS template_id uuid REFERENCES public.message_templates(id) ON DELETE SET NULL;
ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS service_id uuid REFERENCES public.services(id) ON DELETE SET NULL;
ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS scheduled_at timestamptz;
ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS started_at timestamptz;
ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS completed_at timestamptz;
ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS archived_at timestamptz;
ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS notes text;
ALTER TABLE public.outreach_campaigns ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.outreach_messages ALTER COLUMN lead_id DROP NOT NULL;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS template_id uuid REFERENCES public.message_templates(id) ON DELETE SET NULL;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS subject text;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS queued_at timestamptz;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS delivered_at timestamptz;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS failed_at timestamptz;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS bounced_at timestamptz;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS provider text;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS provider_message_id text;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS error_message text;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.outreach_messages ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.conversations ALTER COLUMN status SET DEFAULT 'open';
UPDATE public.conversations SET status='open' WHERE status='active';
UPDATE public.conversations SET status='handoff' WHERE status='human_required';
UPDATE public.outreach_campaigns SET status='running' WHERE status='active';
UPDATE public.outreach_messages SET status='queued',queued_at=coalesce(queued_at,now()) WHERE status='pending';
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS last_message_preview text;
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS unread_count integer NOT NULL DEFAULT 0 CHECK (unread_count >= 0);
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS last_activity_at timestamptz;
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS subject text;
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS ai_handling boolean NOT NULL DEFAULT false;
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS resolved_at timestamptz;

ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS status public.outreach_message_status DEFAULT 'sent';
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS delivered_at timestamptz;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS read_at timestamptz;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS failed_at timestamptz;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS bounced_at timestamptz;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS attachments jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS provider text;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS provider_message_id text;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS error_message text;

CREATE TABLE IF NOT EXISTS public.conversation_handoffs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK (reason IN ('client_requested_human','pricing_negotiation','complex_request','complaint','high_value_lead','ai_confidence_too_low')),
  requested_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  assigned_to uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'needs_human' CHECK (status IN ('needs_human','human_handling','resolved')),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  accepted_at timestamptz,
  resolved_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.follow_ups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id uuid REFERENCES public.leads(id) ON DELETE CASCADE,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  campaign_id uuid REFERENCES public.outreach_campaigns(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (char_length(trim(title)) BETWEEN 1 AND 200),
  due_at timestamptz NOT NULL,
  priority public.priority_level NOT NULL DEFAULT 'medium',
  assigned_to uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','completed','cancelled')),
  notes text,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT follow_up_parent_check CHECK (lead_id IS NOT NULL OR company_id IS NOT NULL OR conversation_id IS NOT NULL OR campaign_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS message_templates_channel_idx ON public.message_templates(channel) WHERE archived_at IS NULL;
CREATE INDEX IF NOT EXISTS campaign_targets_campaign_idx ON public.outreach_campaign_targets(campaign_id);
CREATE INDEX IF NOT EXISTS campaign_targets_lead_idx ON public.outreach_campaign_targets(lead_id);
CREATE INDEX IF NOT EXISTS campaign_targets_company_idx ON public.outreach_campaign_targets(company_id);
CREATE INDEX IF NOT EXISTS outreach_campaigns_status_idx ON public.outreach_campaigns(status);
CREATE INDEX IF NOT EXISTS outreach_campaigns_scheduled_idx ON public.outreach_campaigns(scheduled_at);
CREATE INDEX IF NOT EXISTS outreach_messages_campaign_idx ON public.outreach_messages(campaign_id);
CREATE INDEX IF NOT EXISTS outreach_messages_status_idx ON public.outreach_messages(status);
CREATE INDEX IF NOT EXISTS outreach_messages_lead_idx ON public.outreach_messages(lead_id);
CREATE INDEX IF NOT EXISTS conversations_assigned_idx ON public.conversations(assigned_to,status);
CREATE INDEX IF NOT EXISTS conversations_activity_idx ON public.conversations(last_activity_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS conversation_handoffs_conversation_idx ON public.conversation_handoffs(conversation_id,created_at DESC);
CREATE INDEX IF NOT EXISTS follow_ups_due_idx ON public.follow_ups(due_at) WHERE status='pending';
CREATE INDEX IF NOT EXISTS follow_ups_assigned_idx ON public.follow_ups(assigned_to,status,due_at);

DROP TRIGGER IF EXISTS message_templates_set_updated_at ON public.message_templates;
CREATE TRIGGER message_templates_set_updated_at BEFORE UPDATE ON public.message_templates FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS outreach_campaigns_set_updated_at ON public.outreach_campaigns;
CREATE TRIGGER outreach_campaigns_set_updated_at BEFORE UPDATE ON public.outreach_campaigns FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS follow_ups_set_updated_at ON public.follow_ups;
CREATE TRIGGER follow_ups_set_updated_at BEFORE UPDATE ON public.follow_ups FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS conversations_set_updated_at_phase5 ON public.conversations;
CREATE TRIGGER conversations_set_updated_at_phase5 BEFORE UPDATE ON public.conversations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.message_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outreach_campaign_targets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_handoffs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follow_ups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS message_templates_access ON public.message_templates;
CREATE POLICY message_templates_access ON public.message_templates FOR ALL TO authenticated
USING (public.current_user_role() IN ('admin','manager') OR created_by=auth.uid())
WITH CHECK (public.current_user_role() IN ('admin','manager') OR created_by=auth.uid());

DROP POLICY IF EXISTS campaign_targets_access ON public.outreach_campaign_targets;
CREATE POLICY campaign_targets_access ON public.outreach_campaign_targets FOR ALL TO authenticated
USING (
  public.current_user_role() IN ('admin','manager')
  OR EXISTS (SELECT 1 FROM public.outreach_campaigns c WHERE c.id=campaign_id AND c.created_by=auth.uid())
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=lead_id AND l.owner_id=auth.uid())
)
WITH CHECK (
  public.current_user_role() IN ('admin','manager')
  OR EXISTS (SELECT 1 FROM public.outreach_campaigns c WHERE c.id=campaign_id AND c.created_by=auth.uid())
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=lead_id AND l.owner_id=auth.uid())
);

DROP POLICY IF EXISTS outreach_messages_access ON public.outreach_messages;
CREATE POLICY outreach_messages_access ON public.outreach_messages FOR ALL TO authenticated
USING (
  public.current_user_role() IN ('admin','manager')
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=outreach_messages.lead_id AND l.owner_id=auth.uid())
  OR EXISTS (SELECT 1 FROM public.outreach_campaigns c WHERE c.id=outreach_messages.campaign_id AND c.created_by=auth.uid())
)
WITH CHECK (
  public.current_user_role() IN ('admin','manager')
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=outreach_messages.lead_id AND l.owner_id=auth.uid())
  OR EXISTS (SELECT 1 FROM public.outreach_campaigns c WHERE c.id=outreach_messages.campaign_id AND c.created_by=auth.uid())
);

DROP POLICY IF EXISTS conversations_access ON public.conversations;
CREATE POLICY conversations_access ON public.conversations FOR ALL TO authenticated
USING (
  public.current_user_role() IN ('admin','manager') OR assigned_to=auth.uid()
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=conversations.lead_id AND l.owner_id=auth.uid())
)
WITH CHECK (
  public.current_user_role() IN ('admin','manager') OR assigned_to=auth.uid()
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=conversations.lead_id AND l.owner_id=auth.uid())
);

DROP POLICY IF EXISTS messages_access ON public.messages;
CREATE POLICY messages_access ON public.messages FOR ALL TO authenticated
USING (
  public.current_user_role() IN ('admin','manager')
  OR EXISTS (SELECT 1 FROM public.conversations c JOIN public.leads l ON l.id=c.lead_id WHERE c.id=messages.conversation_id AND (c.assigned_to=auth.uid() OR l.owner_id=auth.uid()))
)
WITH CHECK (
  public.current_user_role() IN ('admin','manager')
  OR EXISTS (SELECT 1 FROM public.conversations c JOIN public.leads l ON l.id=c.lead_id WHERE c.id=messages.conversation_id AND (c.assigned_to=auth.uid() OR l.owner_id=auth.uid()))
);

DROP POLICY IF EXISTS conversation_handoffs_access ON public.conversation_handoffs;
CREATE POLICY conversation_handoffs_access ON public.conversation_handoffs FOR ALL TO authenticated
USING (
  public.current_user_role() IN ('admin','manager')
  OR requested_by=auth.uid() OR assigned_to=auth.uid()
  OR EXISTS (SELECT 1 FROM public.conversations c JOIN public.leads l ON l.id=c.lead_id WHERE c.id=conversation_id AND l.owner_id=auth.uid())
)
WITH CHECK (
  public.current_user_role() IN ('admin','manager')
  OR requested_by=auth.uid() OR assigned_to=auth.uid()
  OR EXISTS (SELECT 1 FROM public.conversations c JOIN public.leads l ON l.id=c.lead_id WHERE c.id=conversation_id AND l.owner_id=auth.uid())
);

DROP POLICY IF EXISTS follow_ups_access ON public.follow_ups;
CREATE POLICY follow_ups_access ON public.follow_ups FOR ALL TO authenticated
USING (
  public.current_user_role() IN ('admin','manager') OR assigned_to=auth.uid()
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=follow_ups.lead_id AND l.owner_id=auth.uid())
)
WITH CHECK (
  public.current_user_role() IN ('admin','manager') OR assigned_to=auth.uid()
  OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=follow_ups.lead_id AND l.owner_id=auth.uid())
);


ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS source_type text;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS source_id uuid;
CREATE UNIQUE INDEX IF NOT EXISTS notifications_source_unique_idx ON public.notifications(user_id,type,source_id) WHERE source_id IS NOT NULL;
-- Keep conversation denormalized activity/unread fields synchronized when messages arrive.
CREATE OR REPLACE FUNCTION public.sync_conversation_from_message()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  UPDATE public.conversations
  SET last_message_at=NEW.created_at,
      last_message_preview=left(NEW.message,240),
      last_activity_at=NEW.created_at,
      unread_count=CASE WHEN NEW.sender_type='lead' THEN unread_count+1 ELSE unread_count END
  WHERE id=NEW.conversation_id;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS messages_sync_conversation ON public.messages;
CREATE TRIGGER messages_sync_conversation AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION public.sync_conversation_from_message();

-- A real database-side notification for inbound replies.
CREATE OR REPLACE FUNCTION public.notify_inbound_message()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_user uuid; v_lead uuid; v_company uuid;
BEGIN
  IF NEW.sender_type='lead' THEN
    SELECT c.assigned_to,c.lead_id INTO v_user,v_lead FROM public.conversations c WHERE c.id=NEW.conversation_id;
    SELECT l.company_id INTO v_company FROM public.leads l WHERE l.id=v_lead;
    IF v_user IS NOT NULL THEN
      INSERT INTO public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id)
      VALUES(v_user,'new_reply','New reply','A lead replied in a CRM conversation.',v_lead,v_company,'message',NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS messages_notify_inbound ON public.messages;
CREATE TRIGGER messages_notify_inbound AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION public.notify_inbound_message();

CREATE OR REPLACE FUNCTION public.notify_handoff()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_lead uuid; v_company uuid;
BEGIN
  SELECT c.lead_id,l.company_id INTO v_lead,v_company FROM public.conversations c JOIN public.leads l ON l.id=c.lead_id WHERE c.id=NEW.conversation_id;
  IF NEW.assigned_to IS NOT NULL THEN
    INSERT INTO public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id)
    VALUES(NEW.assigned_to,'human_handoff','Human handoff required','A conversation requires human attention.',v_lead,v_company,'handoff',NEW.id);
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS conversation_handoffs_notify ON public.conversation_handoffs;
CREATE TRIGGER conversation_handoffs_notify AFTER INSERT ON public.conversation_handoffs FOR EACH ROW EXECUTE FUNCTION public.notify_handoff();

CREATE OR REPLACE FUNCTION public.mark_conversation_read(p_conversation_id uuid)
RETURNS public.conversations LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.conversations;
BEGIN
  UPDATE public.conversations c SET unread_count=0 WHERE c.id=p_conversation_id AND (
    public.current_user_role() IN ('admin','manager') OR c.assigned_to=auth.uid()
    OR EXISTS (SELECT 1 FROM public.leads l WHERE l.id=c.lead_id AND l.owner_id=auth.uid())
  );
  IF NOT FOUND THEN RAISE EXCEPTION 'Conversation not found or not authorized.' USING errcode='42501'; END IF;
  SELECT * INTO v FROM public.conversations WHERE id=p_conversation_id; RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.mark_conversation_read(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.mark_conversation_read(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_conversation_message(p_conversation_id uuid,p_message text,p_sender_type public.sender_type default 'human',p_channel public.conversation_channel default 'email',p_ai_generated boolean default false)
RETURNS public.messages LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.messages;
BEGIN
  IF p_message IS NULL OR char_length(trim(p_message))=0 THEN RAISE EXCEPTION 'Message cannot be empty.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.conversations c WHERE c.id=p_conversation_id AND (public.current_user_role() IN ('admin','manager') OR c.assigned_to=auth.uid() OR EXISTS(SELECT 1 FROM public.leads l WHERE l.id=c.lead_id AND l.owner_id=auth.uid()))) THEN
    RAISE EXCEPTION 'Not authorized to write to this conversation.' USING errcode='42501';
  END IF;
  INSERT INTO public.messages(conversation_id,sender_type,sender_id,message,channel,ai_generated,status) VALUES(p_conversation_id,p_sender_type,CASE WHEN p_sender_type='human' THEN auth.uid() ELSE NULL END,p_message,p_channel,p_ai_generated,CASE WHEN p_sender_type='human' THEN 'queued'::public.outreach_message_status ELSE 'sent'::public.outreach_message_status END) RETURNING * INTO v;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.create_conversation_message(uuid,text,public.sender_type,public.conversation_channel,boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.create_conversation_message(uuid,text,public.sender_type,public.conversation_channel,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.complete_follow_up(p_follow_up_id uuid)
RETURNS public.follow_ups LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.follow_ups;
BEGIN
  UPDATE public.follow_ups f SET status='completed',completed_at=now()
  WHERE f.id=p_follow_up_id AND (public.current_user_role() IN ('admin','manager') OR f.assigned_to=auth.uid() OR EXISTS(SELECT 1 FROM public.leads l WHERE l.id=f.lead_id AND l.owner_id=auth.uid()));
  IF NOT FOUND THEN RAISE EXCEPTION 'Follow-up not found or not authorized.' USING errcode='42501'; END IF;
  SELECT * INTO v FROM public.follow_ups WHERE id=p_follow_up_id; RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_follow_up(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.complete_follow_up(uuid) TO authenticated;


-- Provider-independent failure/completion notifications.
CREATE OR REPLACE FUNCTION public.notify_outreach_events()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_user uuid; v_lead uuid; v_company uuid;
BEGIN
  IF TG_TABLE_NAME='outreach_messages' AND NEW.status IN ('failed','bounced') AND COALESCE(OLD.status::text,'') IS DISTINCT FROM NEW.status::text THEN
    SELECT c.created_by INTO v_user FROM public.outreach_campaigns c WHERE c.id=NEW.campaign_id;
    IF v_user IS NOT NULL THEN
      INSERT INTO public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id)
      VALUES(v_user,'email_failed','Email failed','An outreach message failed or bounced.',NEW.lead_id,NEW.company_id,'outreach_message',NEW.id)
      ON CONFLICT DO NOTHING;
    END IF;
  ELSIF TG_TABLE_NAME='outreach_campaigns' AND NEW.status='completed' AND COALESCE(OLD.status::text,'') IS DISTINCT FROM 'completed' THEN
    v_user:=NEW.created_by;
    IF v_user IS NOT NULL THEN
      INSERT INTO public.notifications(user_id,type,title,message,source_type,source_id)
      VALUES(v_user,'campaign_completed','Campaign completed','An outreach campaign was marked completed.','campaign',NEW.id)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS outreach_messages_notify_events ON public.outreach_messages;
CREATE TRIGGER outreach_messages_notify_events AFTER UPDATE OF status ON public.outreach_messages FOR EACH ROW EXECUTE FUNCTION public.notify_outreach_events();
DROP TRIGGER IF EXISTS outreach_campaigns_notify_events ON public.outreach_campaigns;
CREATE TRIGGER outreach_campaigns_notify_events AFTER UPDATE OF status ON public.outreach_campaigns FOR EACH ROW EXECUTE FUNCTION public.notify_outreach_events();

CREATE OR REPLACE FUNCTION public.notify_operational_events()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_user uuid; v_lead uuid; v_company uuid;
BEGIN
  IF TG_TABLE_NAME='website_projects' AND NEW.client_approved_at IS NOT NULL AND OLD.client_approved_at IS NULL THEN
    SELECT owner_id,company_id INTO v_user,v_company FROM public.leads WHERE id=NEW.lead_id;
    IF v_user IS NOT NULL THEN
      INSERT INTO public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id) VALUES(v_user,'website_approval','Website approved','A client approved a website project.',NEW.lead_id,v_company,'website_project',NEW.id) ON CONFLICT DO NOTHING;
    END IF;
  ELSIF TG_TABLE_NAME='payments' AND NEW.status='paid' AND COALESCE(OLD.status::text,'') IS DISTINCT FROM 'paid' THEN
    SELECT l.owner_id,l.company_id INTO v_user,v_company FROM public.deals d JOIN public.leads l ON l.id=d.lead_id WHERE d.id=NEW.deal_id;
    IF v_user IS NOT NULL THEN
      INSERT INTO public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id) SELECT v_user,'payment_event','Payment event','A payment was recorded as paid.',d.lead_id,v_company,'payment',NEW.id FROM public.deals d WHERE d.id=NEW.deal_id ON CONFLICT DO NOTHING;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS website_projects_notify_events ON public.website_projects;
CREATE TRIGGER website_projects_notify_events AFTER UPDATE OF client_approved_at ON public.website_projects FOR EACH ROW EXECUTE FUNCTION public.notify_operational_events();
DROP TRIGGER IF EXISTS payments_notify_events ON public.payments;
CREATE TRIGGER payments_notify_events AFTER UPDATE OF status ON public.payments FOR EACH ROW EXECUTE FUNCTION public.notify_operational_events();

DROP TRIGGER IF EXISTS leads_notify_qualified ON public.leads;
CREATE OR REPLACE FUNCTION public.notify_qualified_lead()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.status='qualified' AND OLD.status IS DISTINCT FROM NEW.status AND NEW.owner_id IS NOT NULL THEN
    INSERT INTO public.notifications(user_id,type,title,message,lead_id,company_id,source_type,source_id)
    VALUES(NEW.owner_id,'qualified_lead','New qualified lead','A lead was moved to qualified status.',NEW.id,NEW.company_id,'lead',NEW.id)
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER leads_notify_qualified AFTER UPDATE OF status ON public.leads FOR EACH ROW EXECUTE FUNCTION public.notify_qualified_lead();

CREATE OR REPLACE FUNCTION public.outreach_analytics()
RETURNS json LANGUAGE sql SECURITY DEFINER SET search_path=public STABLE AS $$
  SELECT json_build_object(
    'total_campaigns',(SELECT count(*) FROM public.outreach_campaigns WHERE archived_at IS NULL),
    'messages_sent',(SELECT count(*) FROM public.outreach_messages WHERE status IN ('sent','delivered','opened','replied')),
    'delivered',(SELECT count(*) FROM public.outreach_messages WHERE status IN ('delivered','opened','replied')),
    'failed',(SELECT count(*) FROM public.outreach_messages WHERE status IN ('failed','bounced')),
    'replies',(SELECT count(*) FROM public.outreach_messages WHERE status='replied'),
    'reply_rate',CASE WHEN (SELECT count(*) FROM public.outreach_messages WHERE status IN ('sent','delivered','opened','replied'))=0 THEN 0 ELSE round(100.0*(SELECT count(*) FROM public.outreach_messages WHERE status='replied')/(SELECT count(*) FROM public.outreach_messages WHERE status IN ('sent','delivered','opened','replied')),2) END,
    'qualified_leads',(SELECT count(*) FROM public.leads WHERE status='qualified'),
    'human_handoffs',(SELECT count(*) FROM public.conversation_handoffs),
    'followups_completed',(SELECT count(*) FROM public.follow_ups WHERE status='completed')
  );
$$;
REVOKE ALL ON FUNCTION public.outreach_analytics() FROM public;
GRANT EXECUTE ON FUNCTION public.outreach_analytics() TO authenticated;

-- Notification helper for application-owned events (website/payment/campaign/etc.).
CREATE OR REPLACE FUNCTION public.create_notification(p_user_id uuid,p_type text,p_title text,p_message text default null,p_lead_id uuid default null,p_company_id uuid default null)
RETURNS public.notifications LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.notifications;
BEGIN
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'Notification user is required.'; END IF;
  IF p_user_id <> auth.uid() AND public.current_user_role() NOT IN ('admin','manager') THEN RAISE EXCEPTION 'Not authorized to create a notification.' USING errcode='42501'; END IF;
  INSERT INTO public.notifications(user_id,type,title,message,lead_id,company_id) VALUES(p_user_id,p_type,p_title,p_message,p_lead_id,p_company_id) RETURNING * INTO v;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.create_notification(uuid,text,text,text,uuid,uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.create_notification(uuid,text,text,text,uuid,uuid) TO authenticated;
-- AI Agency CRM — Phase 6: AI Agent & Automation Engine
-- Apply after Phase 5. Provider-neutral, deterministic-safe architecture.

CREATE TABLE IF NOT EXISTS public.ai_agents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 160),
  status text NOT NULL DEFAULT 'disabled' CHECK (status IN ('active','paused','disabled')),
  enabled boolean NOT NULL DEFAULT false,
  default_mode text NOT NULL DEFAULT 'assisted' CHECK (default_mode IN ('manual','ai_draft','assisted','automation_ready')),
  confidence_threshold integer NOT NULL DEFAULT 70 CHECK (confidence_threshold BETWEEN 0 AND 100),
  handoff_threshold integer NOT NULL DEFAULT 45 CHECK (handoff_threshold BETWEEN 0 AND 100),
  assigned_channels jsonb NOT NULL DEFAULT '[]'::jsonb,
  assigned_campaigns jsonb NOT NULL DEFAULT '[]'::jsonb,
  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS agent_name text NOT NULL DEFAULT 'Sales Agent';
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS default_mode text NOT NULL DEFAULT 'assisted';
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS confidence_threshold integer NOT NULL DEFAULT 70;
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS handoff_threshold integer NOT NULL DEFAULT 45;
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS default_language text NOT NULL DEFAULT 'fr';
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS allowed_actions jsonb NOT NULL DEFAULT '["qualify_lead","create_followup","create_activity","request_human","recommend_service"]'::jsonb;
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS max_automated_actions integer NOT NULL DEFAULT 0;
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS approval_required boolean NOT NULL DEFAULT true;

CREATE TABLE IF NOT EXISTS public.ai_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id uuid REFERENCES public.ai_agents(id) ON DELETE SET NULL,
  lead_id uuid REFERENCES public.leads(id) ON DELETE CASCADE,
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  input_context_ref jsonb NOT NULL DEFAULT '{}'::jsonb,
  context_ref jsonb NOT NULL DEFAULT '{}'::jsonb,
  decision text NOT NULL CHECK (char_length(trim(decision)) BETWEEN 1 AND 100),
  confidence integer NOT NULL CHECK (confidence BETWEEN 0 AND 100),
  reason text NOT NULL,
  action text NOT NULL CHECK (action IN ('qualify_lead','reply','create_followup','update_lead','change_status','request_human','recommend_service','create_activity','do_nothing')),
  approval_status text NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending','approved','rejected','executed')),
  mode text NOT NULL DEFAULT 'assisted' CHECK (mode IN ('manual','ai_draft','assisted','automation_ready')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ai_decisions_parent_check CHECK (lead_id IS NOT NULL OR conversation_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS public.ai_drafts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id uuid REFERENCES public.ai_agents(id) ON DELETE SET NULL,
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  lead_id uuid REFERENCES public.leads(id) ON DELETE CASCADE,
  incoming_message_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
  draft_body text NOT NULL CHECK (char_length(trim(draft_body)) > 0),
  reasoning_summary text,
  confidence integer NOT NULL DEFAULT 0 CHECK (confidence BETWEEN 0 AND 100),
  approval_status text NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending','approved','rejected','executed')),
  mode text NOT NULL DEFAULT 'ai_draft' CHECK (mode IN ('manual','ai_draft','assisted','automation_ready')),
  approved_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  approved_at timestamptz,
  rejected_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.workflows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 200),
  description text,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','paused','archived')),
  mode text NOT NULL DEFAULT 'assisted' CHECK (mode IN ('manual','ai_draft','assisted','automation_ready')),
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.workflow_triggers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id uuid NOT NULL REFERENCES public.workflows(id) ON DELETE CASCADE,
  trigger_type text NOT NULL CHECK (trigger_type IN ('lead_created','lead_status_changed','new_message','new_conversation','followup_due','website_preview_ready','website_approved','payment_received','deal_created','human_handoff','campaign_completed')),
  position integer NOT NULL DEFAULT 0 CHECK (position >= 0),
  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.workflow_conditions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id uuid NOT NULL REFERENCES public.workflows(id) ON DELETE CASCADE,
  field text NOT NULL CHECK (char_length(trim(field)) BETWEEN 1 AND 120),
  operator text NOT NULL CHECK (operator IN ('equals','not_equals','greater_than','less_than','contains','is_empty','is_not_empty')),
  value text,
  position integer NOT NULL DEFAULT 0 CHECK (position >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.workflow_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id uuid NOT NULL REFERENCES public.workflows(id) ON DELETE CASCADE,
  action_type text NOT NULL CHECK (action_type IN ('update_lead','create_activity','create_followup','create_notification','change_conversation_status','assign_conversation','add_tag','recommend_service','generate_response_draft','request_human','update_campaign_state')),
  position integer NOT NULL DEFAULT 0 CHECK (position >= 0),
  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.workflow_executions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id uuid NOT NULL REFERENCES public.workflows(id) ON DELETE CASCADE,
  trigger_type text NOT NULL,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','completed','failed','cancelled')),
  started_at timestamptz,
  ended_at timestamptz,
  result jsonb NOT NULL DEFAULT '{}'::jsonb,
  error text,
  context jsonb NOT NULL DEFAULT '{}'::jsonb,
  lead_id uuid REFERENCES public.leads(id) ON DELETE SET NULL,
  company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.workflow_execution_steps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id uuid NOT NULL REFERENCES public.workflow_executions(id) ON DELETE CASCADE,
  action_id uuid REFERENCES public.workflow_actions(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','completed','failed','cancelled')),
  started_at timestamptz,
  ended_at timestamptz,
  input jsonb NOT NULL DEFAULT '{}'::jsonb,
  output jsonb NOT NULL DEFAULT '{}'::jsonb,
  error text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ai_knowledge_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (char_length(trim(title)) BETWEEN 1 AND 200),
  category text NOT NULL CHECK (category IN ('company','service','pricing','website_project','faq','message_template','crm_history')),
  content text NOT NULL CHECK (char_length(trim(content)) > 0),
  source_type text NOT NULL DEFAULT 'manual',
  active boolean NOT NULL DEFAULT true,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ai_agents_status_idx ON public.ai_agents(status,enabled);
CREATE INDEX IF NOT EXISTS ai_decisions_lead_idx ON public.ai_decisions(lead_id,created_at DESC);
CREATE INDEX IF NOT EXISTS ai_decisions_conversation_idx ON public.ai_decisions(conversation_id,created_at DESC);
CREATE INDEX IF NOT EXISTS ai_decisions_pending_idx ON public.ai_decisions(approval_status,created_at DESC) WHERE approval_status='pending';
CREATE INDEX IF NOT EXISTS ai_drafts_conversation_idx ON public.ai_drafts(conversation_id,created_at DESC);
CREATE INDEX IF NOT EXISTS ai_drafts_pending_idx ON public.ai_drafts(approval_status,created_at DESC) WHERE approval_status='pending';
CREATE INDEX IF NOT EXISTS workflows_status_idx ON public.workflows(status,updated_at DESC);
CREATE INDEX IF NOT EXISTS workflow_triggers_workflow_idx ON public.workflow_triggers(workflow_id,position);
CREATE INDEX IF NOT EXISTS workflow_conditions_workflow_idx ON public.workflow_conditions(workflow_id,position);
CREATE INDEX IF NOT EXISTS workflow_actions_workflow_idx ON public.workflow_actions(workflow_id,position);
CREATE INDEX IF NOT EXISTS workflow_executions_workflow_idx ON public.workflow_executions(workflow_id,started_at DESC);
CREATE INDEX IF NOT EXISTS workflow_executions_context_idx ON public.workflow_executions(lead_id,company_id,conversation_id);
CREATE INDEX IF NOT EXISTS workflow_execution_steps_execution_idx ON public.workflow_execution_steps(execution_id,created_at);
CREATE INDEX IF NOT EXISTS ai_knowledge_active_idx ON public.ai_knowledge_items(category,active,updated_at DESC);

DROP TRIGGER IF EXISTS ai_agents_set_updated_at ON public.ai_agents;
CREATE TRIGGER ai_agents_set_updated_at BEFORE UPDATE ON public.ai_agents FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS ai_settings_set_updated_at ON public.ai_settings;
CREATE TRIGGER ai_settings_set_updated_at BEFORE UPDATE ON public.ai_settings FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS ai_drafts_set_updated_at ON public.ai_drafts;
CREATE TRIGGER ai_drafts_set_updated_at BEFORE UPDATE ON public.ai_drafts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS workflows_set_updated_at ON public.workflows;
CREATE TRIGGER workflows_set_updated_at BEFORE UPDATE ON public.workflows FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS ai_knowledge_items_set_updated_at ON public.ai_knowledge_items;
CREATE TRIGGER ai_knowledge_items_set_updated_at BEFORE UPDATE ON public.ai_knowledge_items FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.ai_agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_drafts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_triggers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_conditions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_execution_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_knowledge_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ai_agents_select ON public.ai_agents;
CREATE POLICY ai_agents_select ON public.ai_agents FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager') OR created_by=auth.uid());
DROP POLICY IF EXISTS ai_agents_manage ON public.ai_agents;
CREATE POLICY ai_agents_manage ON public.ai_agents FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));

DROP POLICY IF EXISTS ai_settings_access ON public.ai_settings;
CREATE POLICY ai_settings_access ON public.ai_settings FOR ALL TO authenticated USING (user_id=auth.uid() OR public.current_user_role() IN ('admin','manager')) WITH CHECK (user_id=auth.uid() OR public.current_user_role() IN ('admin','manager'));

DROP POLICY IF EXISTS ai_decisions_select ON public.ai_decisions;
CREATE POLICY ai_decisions_select ON public.ai_decisions FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager') OR lead_id IN (SELECT id FROM public.leads WHERE owner_id=auth.uid()));
DROP POLICY IF EXISTS ai_decisions_insert ON public.ai_decisions;
CREATE POLICY ai_decisions_insert ON public.ai_decisions FOR INSERT TO authenticated WITH CHECK (public.current_user_role() IN ('admin','manager','sales'));
DROP POLICY IF EXISTS ai_decisions_update ON public.ai_decisions;
CREATE POLICY ai_decisions_update ON public.ai_decisions FOR UPDATE TO authenticated USING (public.current_user_role() IN ('admin','manager') OR lead_id IN (SELECT id FROM public.leads WHERE owner_id=auth.uid())) WITH CHECK (public.current_user_role() IN ('admin','manager') OR lead_id IN (SELECT id FROM public.leads WHERE owner_id=auth.uid()));

DROP POLICY IF EXISTS ai_drafts_select ON public.ai_drafts;
CREATE POLICY ai_drafts_select ON public.ai_drafts FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager') OR lead_id IN (SELECT id FROM public.leads WHERE owner_id=auth.uid()));
DROP POLICY IF EXISTS ai_drafts_manage ON public.ai_drafts;
CREATE POLICY ai_drafts_manage ON public.ai_drafts FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager','sales')) WITH CHECK (public.current_user_role() IN ('admin','manager','sales'));

DROP POLICY IF EXISTS workflows_select ON public.workflows;
CREATE POLICY workflows_select ON public.workflows FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager','sales'));
DROP POLICY IF EXISTS workflows_manage ON public.workflows;
CREATE POLICY workflows_manage ON public.workflows FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));

DROP POLICY IF EXISTS workflow_triggers_access ON public.workflow_triggers;
CREATE POLICY workflow_triggers_access ON public.workflow_triggers FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS workflow_conditions_access ON public.workflow_conditions;
CREATE POLICY workflow_conditions_access ON public.workflow_conditions FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS workflow_actions_access ON public.workflow_actions;
CREATE POLICY workflow_actions_access ON public.workflow_actions FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS workflow_executions_select ON public.workflow_executions;
CREATE POLICY workflow_executions_select ON public.workflow_executions FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager','sales'));
DROP POLICY IF EXISTS workflow_executions_insert ON public.workflow_executions;
CREATE POLICY workflow_executions_insert ON public.workflow_executions FOR INSERT TO authenticated WITH CHECK (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS workflow_executions_update ON public.workflow_executions;
CREATE POLICY workflow_executions_update ON public.workflow_executions FOR UPDATE TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS workflow_execution_steps_access ON public.workflow_execution_steps;
CREATE POLICY workflow_execution_steps_access ON public.workflow_execution_steps FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));

DROP POLICY IF EXISTS ai_knowledge_select ON public.ai_knowledge_items;
CREATE POLICY ai_knowledge_select ON public.ai_knowledge_items FOR SELECT TO authenticated USING (active=true OR public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS ai_knowledge_manage ON public.ai_knowledge_items;
CREATE POLICY ai_knowledge_manage ON public.ai_knowledge_items FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));

-- Explicitly deny any provider secret storage through the Phase 6 model: configuration is non-secret CRM configuration only.
COMMENT ON COLUMN public.ai_agents.configuration IS 'Non-secret agent configuration only. Provider API keys, OAuth secrets and private tokens must remain server-side.';
COMMENT ON COLUMN public.ai_settings.allowed_actions IS 'JSON array of internal safe actions; external provider actions are not supported in Phase 6.';

-- ========================= PHASE 7: SECURE INTEGRATIONS =========================
-- Public CRM tables contain metadata only. Provider credentials belong server-side.
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS connection_status text NOT NULL DEFAULT 'not_configured';
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS enabled boolean NOT NULL DEFAULT false;
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS provider_account_label text;
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS last_success_at timestamptz;
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS last_error_at timestamptz;
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS last_error_code text;
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS last_error_message text;
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS last_event_at timestamptz;

CREATE TABLE IF NOT EXISTS public.provider_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), integration_id uuid REFERENCES public.integrations(id) ON DELETE SET NULL,
 provider text NOT NULL, event_type text NOT NULL, external_event_id text,
 status text NOT NULL DEFAULT 'received' CHECK(status IN ('received','processing','processed','failed','ignored')),
 payload jsonb NOT NULL DEFAULT '{}'::jsonb, normalized_event jsonb NOT NULL DEFAULT '{}'::jsonb,
 signature_verified boolean NOT NULL DEFAULT false, idempotency_key text, retry_count integer NOT NULL DEFAULT 0 CHECK(retry_count >= 0),
 next_retry_at timestamptz, error_code text, error_message text, received_at timestamptz NOT NULL DEFAULT now(), processed_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(provider,idempotency_key)
);
CREATE TABLE IF NOT EXISTS public.integration_logs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), integration_id uuid REFERENCES public.integrations(id) ON DELETE SET NULL,
 provider text NOT NULL, operation text NOT NULL, status text NOT NULL CHECK(status IN ('started','succeeded','failed','skipped')),
 error_code text, safe_error_message text, retryable boolean NOT NULL DEFAULT false, attempt integer NOT NULL DEFAULT 1 CHECK(attempt > 0),
 related_lead_id uuid REFERENCES public.leads(id) ON DELETE SET NULL, related_company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
 related_conversation_id uuid REFERENCES public.conversations(id) ON DELETE SET NULL, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.integration_audit_log (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
 integration_id uuid REFERENCES public.integrations(id) ON DELETE SET NULL,
 action text NOT NULL CHECK(action IN ('enabled','disabled','connection_attempt','provider_error','webhook_received','webhook_processed','ai_request','email_request','whatsapp_request','sms_request')),
 provider text NOT NULL, success boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS provider_events_status_idx ON public.provider_events(status,next_retry_at);
CREATE INDEX IF NOT EXISTS provider_events_provider_idx ON public.provider_events(provider,event_type,received_at DESC);
CREATE INDEX IF NOT EXISTS integration_logs_integration_idx ON public.integration_logs(integration_id,created_at DESC);
CREATE INDEX IF NOT EXISTS integration_audit_idx ON public.integration_audit_log(provider,created_at DESC);
ALTER TABLE public.provider_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS provider_events_select ON public.provider_events; CREATE POLICY provider_events_select ON public.provider_events FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS provider_events_manage ON public.provider_events; CREATE POLICY provider_events_manage ON public.provider_events FOR ALL TO authenticated USING (public.current_user_role() IN ('admin','manager')) WITH CHECK (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS integration_logs_select ON public.integration_logs; CREATE POLICY integration_logs_select ON public.integration_logs FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS integration_logs_insert ON public.integration_logs; CREATE POLICY integration_logs_insert ON public.integration_logs FOR INSERT TO authenticated WITH CHECK (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS integration_audit_select ON public.integration_audit_log; CREATE POLICY integration_audit_select ON public.integration_audit_log FOR SELECT TO authenticated USING (public.current_user_role() IN ('admin','manager'));
DROP POLICY IF EXISTS integration_audit_insert ON public.integration_audit_log; CREATE POLICY integration_audit_insert ON public.integration_audit_log FOR INSERT TO authenticated WITH CHECK (public.current_user_role() IN ('admin','manager') OR user_id=auth.uid());
COMMENT ON COLUMN public.integrations.configuration IS 'Non-secret metadata only. API keys, OAuth secrets, tokens and passwords must remain server-side.';


-- PHASE 9 EXTENSIONS (kept in sync with 20260828240000_phase_9_website_qr_production.sql)
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

-- PHASE 9 OPERATIONAL EVENTS (same definitions as the Phase 9 migration)
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


-- Phase 11 final audit hardening (kept synchronized with migration 20260828260000_phase_11_final_audit.sql)
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
