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

- Node.js / npm
- Docker-compatible runtime
- Flutter toolchain

The Supabase CLI is intentionally installed as a project-local npm dev dependency and
locked by `package-lock.json`. After cloning or pulling the repository, install the
exact dependency set with:

```bash
npm ci
```

The repository already contains `supabase/config.toml` and the production migration
history. Local staging is rebuilt from those committed migrations.

## First setup

From the repository root.

macOS / Linux:

```bash
chmod +x tool/staging_start.sh tool/run_staging.sh
./tool/staging_start.sh
```

Windows PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\tool\staging_start.ps1
```

The setup script:

1. starts the local Supabase stack,
2. destroys/recreates the local database,
3. reapplies all migrations,
4. applies `supabase/seed.sql`,
5. prints local service URLs and keys.

The scripts invoke the project-local CLI from `node_modules/.bin`; they do not depend
on a machine-global Supabase CLI installation.

A successful `supabase db reset` is the first reproducibility checkpoint for Phase 1.

## Flutter staging config

Create a local, ignored config file:

```bash
cp env/staging.example.json env/staging.json
```

Then run the project-local CLI and copy the local publishable/anon key into
`env/staging.json`:

```bash
npx supabase status
```

Default local API URLs:

- iOS simulator / macOS / Windows / web: `http://127.0.0.1:54321`
- Android emulator: `http://10.0.2.2:54321`
- Physical device: handled later as a separate device-QA task; do not expose the local
  Supabase stack to public networks.

Run the Teacher app against local staging.

macOS / Linux:

```bash
./tool/run_staging.sh
```

Windows PowerShell:

```powershell
.\tool\run_staging.ps1
```

The script refuses to run if `env/staging.json` points somewhere other than the
expected local Supabase hosts. This is a guardrail against accidentally performing QA
against Production.

## Reset rule

Before a deterministic QA run:

```bash
npx supabase db reset
```

This must always mean:

```text
empty local database
  -> all committed migrations
  -> committed synthetic seed
  -> known QA starting state
```

Never run `npx supabase db reset --linked` as part of this QA workflow. The linked
cloud project is Production and must not be destructively reset.

## Phase 1 checkpoints

- [ ] project-local Supabase CLI is reproducibly installed with `npm ci`.
- [ ] `npx supabase start` succeeds locally.
- [ ] `npx supabase db reset` replays the complete migration chain successfully.
- [ ] Flutter Teacher app connects to local staging.
- [ ] Flutter Student app connects to the same local staging backend.
- [ ] Synthetic QA accounts exist for Student / Teacher / Manager / Master.
- [ ] A deterministic QA seed can be reset repeatedly.
- [ ] Staging is visually distinguishable from Production.

## Next task

After the migration chain is verified locally, design the minimal synthetic fixture set:
QA branches, four role accounts, semester/closure state, regular/flex lessons, and
lesson-right states required for manual QA and E2E scenarios.
