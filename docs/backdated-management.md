# Backdated student management

Branch: `codex/backdate`.

## Withdrawal behavior

The user-approved terminal policy supersedes the original conservative history
vetoes. For today/past dates, `schedule_student_withdrawal` records the selected
date and finalizes atomically. Existing past scheduled/canceled lessons,
assignments, regular-schedule versions, completed plans, and old pending
withdrawal snapshots do not prevent withdrawal. Withdrawal day is the first day
outside enrollment; the earliest permitted date remains one day after the latest
enrollment period began. Current role/branch/enrollment validation remains.

Finalization archives the original lesson rows on/after 00:00 Asia/Seoul on the
selected date, then deletes them from the operational lesson table. Earlier
lessons remain. The deletion therefore changes history/statistics computed from
those lesson rows, including already-past lessons, as requested by the user.

`private.student_withdrawal_finalization_archives` captures original student,
rights, legacy credits, assignments, series, slots, and plan state. The existing
private lesson-snapshot table holds each removed lesson and linked right state,
associated through `finalization_id`. Open snapshots from prior withdrawal
reservations are finalized without changing their lesson/right payloads or
restoring old right states. Final archives and their lesson snapshots reject
updates/deletes and are unavailable to client roles. Cancellation/audit ledgers
remain intact. No general-purpose automatic undo is exposed.

All available/reserved rights retire, including unused carryovers. A consumed
right used only by a removed lesson/held reservation also retires; consumed rights
still used by preserved earlier scheduled lessons retain their history. Remaining
unused legacy credits expire. Completed semester plans stay completed and no
replacement rights are issued. Reactivation does not restore finalized snapshots
or revive revoked rights.

Future reservations remain reversible: postponing/canceling them follows existing
restore/credit behavior, with the account active until the effective date. Only
finalization closes the account and zeros usable rights. Delayed cron uses the
same archival finalizer. Repeating a finalized date is idempotent. Dependent row
locks use NOWAIT and a retry error to avoid reversed lock-order deadlocks. Any
failure rolls back archive creation, date/enrollment changes, lesson deletion,
right retirement, and account deactivation together.

## Additional lesson behavior

Managers/masters can register a standalone makeup lesson in a past semester or at
an earlier time today. Existing active student/teacher/branch scope, withdrawal
boundaries, overlap constraints, personal blocked periods, work-hour warnings,
and the intentional allowance during branch closures remain in place. Student
self-service booking rules are unchanged.

Past input additionally requires a matching student enrollment period in the
current branch. Enrollment gaps are rejected. Withdrawn students and inactive
teachers/branches are not newly exposed for historical input.

With deduction disabled, only the new lesson and its audit are added; settled
rights are not recomputed. With deduction enabled for past input, the matching
semester plan must be planned/active and is locked against settlement. One
available right of the same branch, semester, student, and duration is consumed.
Completed plans, expired/revoked rights, and rights from other semesters are not
reopened. Existing audit/notification behavior is retained; the lesson date is
the effective date while audit/consumption timestamps record the actual write.
Historical teacher statistics include the new lesson.

## Verification and rollout

Start the existing local Docker/Supabase environment, then run:

```powershell
.\tool\verify_backdate.ps1
flutter test --no-pub
flutter analyze --no-pub
```

The SQL runner accepts only a local Docker context, clones schema and permissions
without copying row data, applies the three migrations in a disposable database,
and runs independent synthetic rollback fixtures. It preserves the source local
database. The generated database is removed afterward; schema-only diagnostics
remain under ignored `build/backdate_qa/`. Managed-role default privileges are
omitted from the clone because the local postgres role cannot change those
owners; existing object ACLs and postgres defaults are retained.

For production release, the feature was moved onto the latest `origin/main`
(`ffbfa7f`, version `3.3.1+64`). The release version is `3.3.2+65`. Existing
production screens, notification/QA features, and the 45-minute duration preset
are preserved. The QA sandbox implements the new availability query locally and
never sends it to the production database. Relevant production function,
trigger, and constraint definitions were inspected read-only again before rollout.

Production backend rollout was approved by the user and completed on 2026-10-26:

- `20261026134010_support_backdated_student_withdrawal.sql`
- `20261026134021_support_backdated_makeup_lessons.sql`

The user approved the terminal-policy relaxation on 2026-10-27 (Asia/Seoul).
It is deployed as `20261026231956_finalize_withdrawal_with_archived_history.sql`
(migration versions use UTC). Post-deployment metadata confirms that the
history veto is absent, the archival finalizer is active, and private archive
tables/helpers remain inaccessible to client roles. Future preclear/restore,
withdrawal cancellation, reactivation, and the makeup RPCs were not replaced.
The change defines future requests; no existing students were bulk-finalized.

The production migration ledger and local filenames match. The original rollout
changed three RPC definitions; the terminal-policy update changes only the
scheduler/finalizer and adds private archival objects. Preclear/restore,
cancellation, reactivation, and makeup definitions retain their prior hashes.
Anonymous execution remains denied and authenticated/service-role RPC access is
preserved. No production student, lesson, cancellation, or lesson-right rows were
directly edited or used for test writes. The policy applies when the user submits
a withdrawal, not as a bulk update. Previous function definitions are saved in
ignored `build/terminal_withdrawal/production_before.sql` (and the original
rollout backup in `build/backdate_release/production_before_functions.sql`).

The Flutter client accepts the atomic `finalized` response for past/today withdrawal
and keeps the legacy today-finalization fallback. The already-deployed app can
use the relaxed backend immediately. At the user's request, this policy update
does not change Flutter source, QA sandbox behavior, Dart tests, or app version.
Existing client explanatory text and sandbox behavior remain as released; the
production policy is verified with SQL fixtures. No mobile release is required.

The isolated SQL runner passed the original conservative-withdrawal fixtures
before applying the terminal-policy migration, then the terminal-withdrawal and
makeup suites. Terminal cases cover scheduled/canceled lesson archival, completed
plans, prior preclear snapshots, carryovers, legacy credits, future reservation
restoration, idempotency, archive access/immutability, rollback, and cron execution.
A separate two-session settlement-lock check passed in the original rollout.
No production business rows were used for testing. Do not apply the migrations
again; all three are already present in production.
