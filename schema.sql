-- ============================================================
-- feecutter — PostgreSQL schema for Supabase
-- ============================================================

-- Enable UUID generation
create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- users
-- Mirrors auth.users; stores email leads and Pro subscribers.
-- ------------------------------------------------------------
create table if not exists public.users (
  id              uuid primary key references auth.users (id) on delete cascade,
  email           text not null unique,
  stripe_customer_id    text,
  subscription_status   text not null default 'free'
                          check (subscription_status in ('free', 'pro', 'pro_annual', 'cancelled', 'past_due')),
  subscription_period_end timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

alter table public.users enable row level security;

create policy "Users can view their own record"
  on public.users for select
  using (auth.uid() = id);

create policy "Users can update their own record"
  on public.users for update
  using (auth.uid() = id);

-- Service role bypasses RLS for webhook updates (no extra policy needed)

-- ------------------------------------------------------------
-- platform_fee_configs
-- Fee structure per supported platform — editable without redeploy.
-- ------------------------------------------------------------
create table if not exists public.platform_fee_configs (
  id                    uuid primary key default gen_random_uuid(),
  slug                  text not null unique,          -- e.g. 'stripe', 'paypal'
  display_name          text not null,
  logo_url              text,
  base_rate_pct         numeric(6,4) not null,         -- e.g. 2.9
  payment_processing_pct numeric(6,4) not null default 0,
  payout_fee_usd        numeric(8,4) not null default 0,
  fx_markup_pct         numeric(6,4) not null default 0,
  has_free_tier         boolean not null default true,
  notes                 text,
  is_active             boolean not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

alter table public.platform_fee_configs enable row level security;

-- Public read — anyone can see fee configs
create policy "Anyone can read platform fee configs"
  on public.platform_fee_configs for select
  using (true);

-- Only service role / admin can insert or update (enforced via Supabase dashboard role)
create policy "Service role can manage fee configs"
  on public.platform_fee_configs for all
  using (auth.role() = 'service_role');

-- Seed core platforms
insert into public.platform_fee_configs
  (slug, display_name, base_rate_pct, payment_processing_pct, payout_fee_usd, fx_markup_pct, has_free_tier)
values
  ('stripe',     'Stripe',          2.9,  0.30, 0,    1.5,  true),
  ('paypal',     'PayPal',          3.49, 0.49, 0,    4.0,  true),
  ('square',     'Square',          2.6,  0.10, 0,    0,    true),
  ('shopify',    'Shopify Payments', 2.0, 0.00, 0,    1.5,  false),
  ('gumroad',    'Gumroad',         10.0, 0.00, 0,    0,    true),
  ('paddle',     'Paddle',          5.0,  0.50, 0,    0,    false),
  ('braintree',  'Braintree',       2.59, 0.49, 0,    1.0,  true),
  ('amazon_pay', 'Amazon Pay',      2.9,  0.30, 0,    0,    false)
on conflict (slug) do nothing;

-- ------------------------------------------------------------
-- calculations
-- Each fee calculation session — anonymous or authenticated.
-- ------------------------------------------------------------
create table if not exists public.calculations (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid references public.users (id) on delete set null,
  anonymous_session_id text,                           -- client-generated UUID for anon users
  platform_slug       text not null references public.platform_fee_configs (slug),
  revenue_input_usd   numeric(14,2) not null,
  transaction_count   integer,
  effective_rate_pct  numeric(8,4) not null,
  annual_fee_bleed_usd numeric(14,2) not null,
  input_snapshot      jsonb,                           -- raw form inputs for audit
  created_at          timestamptz not null default now()
);

alter table public.calculations enable row level security;

create policy "Users can view their own calculations"
  on public.calculations for select
  using (auth.uid() = user_id);

create policy "Users can insert their own calculations"
  on public.calculations for insert
  with check (auth.uid() = user_id or user_id is null);

create policy "Anonymous calculations are insert-only"
  on public.calculations for select
  using (user_id is not null);  -- anon rows only readable by service role

-- ------------------------------------------------------------
-- saved_reports
-- Full platform comparison report with shareable slug.
-- ------------------------------------------------------------
create table if not exists public.saved_reports (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.users (id) on delete cascade,
  share_slug      text not null unique default encode(gen_random_bytes(8), 'hex'),
  title           text,
  revenue_input_usd numeric(14,2) not null,
  report_data     jsonb not null,                      -- full comparison payload
  is_public       boolean not null default true,       -- shareable link active?
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

alter table public.saved_reports enable row level security;

create policy "Owners can manage their reports"
  on public.saved_reports for all
  using (auth.uid() = user_id);

create policy "Anyone can view public reports by slug"
  on public.saved_reports for select
  using (is_public = true);

-- ------------------------------------------------------------
-- email_captures
-- Raw email capture log from the free report gate.
-- ------------------------------------------------------------
create table if not exists public.email_captures (
  id              uuid primary key default gen_random_uuid(),
  email           text not null,
  source          text not null default 'report_gate', -- e.g. 'report_gate', 'footer', 'exit_intent'
  calculation_id  uuid references public.calculations (id) on delete set null,
  metadata        jsonb,                               -- utm params, referrer, etc.
  converted_at    timestamptz,                         -- set when user creates full account
  created_at      timestamptz not null default now()
);

alter table public.email_captures enable row level security;

-- Only service role reads; inserts allowed from anon (via API route)
create policy "Service role manages email captures"
  on public.email_captures for all
  using (auth.role() = 'service_role');

create policy "Anyone can insert an email capture"
  on public.email_captures for insert
  with check (true);

-- ------------------------------------------------------------
-- Indexes
-- ------------------------------------------------------------
create index if not exists idx_calculations_user_id        on public.calculations (user_id);
create index if not exists idx_calculations_session_id     on public.calculations (anonymous_session_id);
create index if not exists idx_calculations_platform       on public.calculations (platform_slug);
create index if not exists idx_saved_reports_user_id       on public.saved_reports (user_id);
create index if not exists idx_saved_reports_share_slug    on public.saved_reports (share_slug);
create index if not exists idx_email_captures_email        on public.email_captures (email);
create index if not exists idx_email_captures_created_at   on public.email_captures (created_at desc);

-- ------------------------------------------------------------
-- updated_at trigger helper
-- ------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_users_updated_at
  before update on public.users
  for each row execute procedure public.set_updated_at();

create trigger trg_platform_fee_configs_updated_at
  before update on public.platform_fee_configs
  for each row execute procedure public.set_updated_at();

create trigger trg_saved_reports_updated_at
  before update on public.saved_reports
  for each row execute procedure public.set_updated_at();