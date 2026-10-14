-- -----------------------------------------------------------------------------
-- Autenticacion de dos factores
-- -----------------------------------------------------------------------------

alter table users
  add column if not exists two_factor_method text default 'email',
  add column if not exists two_factor_secret text,
  add column if not exists two_factor_pending_method text,
  add column if not exists two_factor_pending_secret text,
  add column if not exists two_factor_recovery_codes jsonb not null default '[]'::jsonb,
  add column if not exists two_factor_failed_attempts int not null default 0,
  add column if not exists two_factor_locked_until timestamptz;

alter table users
  add constraint users_two_factor_method_check
  check (two_factor_method in ('email', 'totp'));

alter table users
  add constraint users_two_factor_pending_method_check
  check (two_factor_pending_method is null or two_factor_pending_method in ('email', 'totp'));

create table if not exists auth_two_factor_challenges (
  id uuid primary key default uuid_generate_v4(),
  user_id bigint not null references users(id) on delete cascade,
  institution_id bigint not null references institutions(id) on delete cascade,
  method text not null check (method in ('email', 'totp')),
  code_hash text,
  session_payload jsonb not null,
  auth_user_payload jsonb not null,
  failed_attempts int not null default 0,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_auth_2fa_challenges_user
  on auth_two_factor_challenges(user_id, created_at desc);

create index if not exists idx_auth_2fa_challenges_active
  on auth_two_factor_challenges(id)
  where consumed_at is null;
