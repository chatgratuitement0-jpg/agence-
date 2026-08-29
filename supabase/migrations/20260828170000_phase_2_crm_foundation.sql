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
using (public.current_user_role() in ('admin','manager') or exists (select 1 from public.leads l where l.company_id = companies.id and l.owner_id = auth.uid()));
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
