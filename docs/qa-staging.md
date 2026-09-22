# Forestring Local Staging

## Purpose

This environment is the Phase 1 QA foundation for Forestring.

It exists to test the real application path without touching Production:

```text
Flutter
  -> Supabase Auth
  -> RLS / RPC
  -> PostgreSQL
```

The local database must contain synthetic QA data only. Do not copy real students,
teachers, schedules, credentials, phone numbers, or other production data into it.

## Environment boundary

| Environment | Backend | Data |
| --- | --- | --- |
| Production | Supabase Cloud: Forestring production project | Real academy data |
| Staging | Local Supabase CLI stack | Synthetic QA data only |
| Review account | Existing safe demo/review flow | Demo repository/data |

The review account and staging QA accounts serve different purposes. Review mode is
for safe product demonstration. Staging is for real backend flow verification,
destructive testing, bug reproduction, and later E2E automation.

## Prerequisites

- Supabase CLI
- Docker-compatible runtime
- Flutter toolchain

The repository already contains `supabase/config.toml` and the production migration
history. Local staging is rebuilt from those committed migrations.

## First setup

From the repository root:

```bash
chmod +x tool/staging_start.sh tool/run_staging.sh
./tool/staging_start.sh
```

The setup script:

1. starts the local Supabase stack,
2. destroys/recreates the local database,
3. reapplies all migrations,
4. applies `supabase/seed.sql`,
5. prints local service URLs and keys.

A successful `supabase db reset` is the first reproducibility checkpoint for Phase 1.

## Flutter staging config

Create a local, ignored config file:

```bash
cp env/staging.example.json env/staging.json
```

Then run `supabase status` and copy the local publishable/anon key into
`env/staging.json`.

Default local API URLs:

- iOS simulator / macOS / Windows / web: `http://127.0.0.1:54321`
- Android emulator: `http://10.0.2.2:54321`
- Physical device: handled later as a separate device-QA task; do not expose the local
  Supabase stack to public networks.

Run the Teacher app against local staging:

```bash
./tool/run_staging.sh
```

The script refuses to run if `env/staging.json` points somewhere other than the
expected local Supabase hosts. This is a guardrail against accidentally performing QA
against Production.

## Reset rule

Before a deterministic QA run:

```bash
supabase db reset
```

This must always mean:

```text
empty local database
  -> all committed migrations
  -> committed synthetic seed
  -> known QA starting state
```

Never run `supabase db reset --linked` as part of this QA workflow. The linked cloud
project is Production and must not be destructively reset.

## Phase 1 checkpoints

- [ ] `supabase start` succeeds locally.
- [ ] `supabase db reset` replays the complete migration chain successfully.
- [ ] Flutter Teacher app connects to local staging.
- [ ] Flutter Student app connects to the same local staging backend.
- [ ] Synthetic QA accounts exist for Student / Teacher / Manager / Master.
- [ ] A deterministic QA seed can be reset repeatedly.
- [ ] Staging is visually distinguishable from Production.

## Next task

After the migration chain is verified locally, design the minimal synthetic fixture set:
QA branches, four role accounts, semester/closure state, regular/flex lessons, and
lesson-right states required for manual QA and E2E scenarios.
