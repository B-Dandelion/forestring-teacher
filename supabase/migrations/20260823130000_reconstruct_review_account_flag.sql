-- Reconstruct a historical Production schema change that was applied outside
-- the recorded Supabase migration history.
--
-- Production currently has public.profiles.is_review_account as:
--   boolean NOT NULL DEFAULT false
--
-- Several later committed migrations depend on this column. A fresh local
-- replay therefore needs the column before those migrations are applied.
--
-- IF NOT EXISTS keeps this migration safe if the historical column is already
-- present in an environment.

alter table public.profiles
  add column if not exists is_review_account boolean not null default false;
