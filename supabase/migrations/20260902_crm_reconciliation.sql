-- Reconciliation migration for the live CRM database.
-- Non-destructive: preserves existing data and adds only fields/support tables required by the current app.

alter table public.companies add column if not exists archived_at timestamptz;

alter table public.website_projects add column if not exists deal_id uuid references public.deals(id) on delete set null;
alter table public.website_projects add column if not exists template_id uuid;
alter table public.website_projects add column if not exists preview_view_count integer not null default 0;
alter table public.website_projects add column if not exists last_preview_viewed_at timestamptz;
alter table public.website_projects add column if not exists client_approved_at timestamptz;
alter table public.website_projects add column if not exists first_payment_at timestamptz;
alter table public.website_projects add column if not exists final_zip_size bigint;
alter table public.website_projects add column if not exists final_zip_sha256 text;
alter table public.website_projects add column if not exists final_zip_generated_at timestamptz;
alter table public.website_projects add column if not exists delivery_status text not null default 'not_ready';
alter table public.website_projects add column if not exists intake_completed_at timestamptz;

alter table public.qr_projects add column if not exists project_name text not null default 'Google Review QR';
alter table public.qr_projects add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.qr_projects add column if not exists deal_id uuid references public.deals(id) on delete set null;
alter table public.qr_projects add column if not exists destination_url text;
alter table public.qr_projects add column if not exists generated_at timestamptz;
alter table public.qr_projects add column if not exists svg_checksum text;
alter table public.qr_projects add column if not exists download_count integer not null default 0;

create table if not exists public.website_templates (
 id uuid primary key default gen_random_uuid(), key text not null unique, name text not null,
 description text, service_type text, configuration jsonb not null default '{}'::jsonb,
 active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
insert into public.website_templates(key,name,description,service_type) values
 ('vitrine','Vitrine','Clean business showcase website','Website Vitrine'),
 ('professional','Professional','Premium professional business website','Website Professionnel')
on conflict (key) do nothing;
alter table public.website_projects add constraint website_projects_template_fk foreign key (template_id) references public.website_templates(id) on delete set null;

alter table public.payments add column if not exists reference text;
alter table public.payments add column if not exists notes text;
alter table public.payments add column if not exists milestone_type text not null default 'full';
alter table public.payments add column if not exists updated_at timestamptz not null default now();
alter table public.payments add column if not exists website_project_id uuid references public.website_projects(id) on delete set null;
alter table public.payments add column if not exists qr_project_id uuid references public.qr_projects(id) on delete set null;

create table if not exists public.invoices (
 id uuid primary key default gen_random_uuid(), invoice_number text not null unique,
 company_id uuid not null references public.companies(id) on delete cascade,
 lead_id uuid references public.leads(id) on delete set null, deal_id uuid references public.deals(id) on delete set null,
 subtotal numeric(12,2) not null default 0, discount numeric(12,2) not null default 0, tax numeric(12,2) not null default 0,
 total numeric(12,2) not null default 0, currency text not null default 'MAD', status text not null default 'draft',
 issue_date date not null default current_date, due_date date, notes text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.invoice_items (
 id uuid primary key default gen_random_uuid(), invoice_id uuid not null references public.invoices(id) on delete cascade,
 description text not null, quantity numeric(12,2) not null default 1, unit_price numeric(12,2) not null default 0,
 amount numeric(12,2) generated always as (quantity * unit_price) stored, created_at timestamptz not null default now()
);

create table if not exists public.deliveries (
 id uuid primary key default gen_random_uuid(), type text not null check(type in ('Website','QR')),
 website_project_id uuid references public.website_projects(id) on delete cascade,
 qr_project_id uuid references public.qr_projects(id) on delete cascade,
 company_id uuid not null references public.companies(id) on delete cascade,
 lead_id uuid references public.leads(id) on delete set null, deal_id uuid references public.deals(id) on delete set null,
 delivery_status text not null default 'not_ready', payment_status text not null default 'pending',
 approval_status text not null default 'pending', production_status text not null default 'pending',
 delivered_at timestamptz, download_count integer not null default 0,
 responsible_user_id uuid references auth.users(id) on delete set null, notes text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check((type='Website' and website_project_id is not null and qr_project_id is null) or (type='QR' and qr_project_id is not null and website_project_id is null))
);

create table if not exists public.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 type text not null, title text not null, message text, lead_id uuid references public.leads(id) on delete set null,
 company_id uuid references public.companies(id) on delete set null, read_at timestamptz, created_at timestamptz not null default now()
);

create index if not exists deliveries_website_idx on public.deliveries(website_project_id);
create index if not exists deliveries_qr_idx on public.deliveries(qr_project_id);
create index if not exists invoices_company_idx on public.invoices(company_id);
create index if not exists invoice_items_invoice_idx on public.invoice_items(invoice_id);
create index if not exists notifications_user_idx on public.notifications(user_id,created_at desc);
