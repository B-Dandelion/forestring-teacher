# Backdated student management

Branch: `codex/backdate`.

## Withdrawal behavior

The existing `schedule_student_withdrawal` RPC gains a separate branch for a newly
requested date before today in Asia/Seoul. It locks the student and checks the
current enrollment period, actual lesson history (including canceled lessons),
historical assignments/schedules, completed semester settlement, and any open
withdrawal snapshots before changing the date.

Conflicting history is rejected with `FORESTRING_STUDENT_WITHDRAWAL_HISTORY_CONFLICT`
and counts in the error detail. Existing records are not edited to force a match.
Withdrawal day remains the first day outside enrollment; the earliest permitted
backdate is one day after the current enrollment period began.

If validation succeeds, the RPC writes the date and calls the existing finalizer
in the same transaction. It skips the reversible future-reservation preclear step.
Future manual makeup reservations release their held rights before unused rights
are revoked. Any failure rolls back the complete request.

Today/future reservation, moving/canceling a future withdrawal, the existing
finalizer, and delayed cron cleanup retain their existing behavior. Repeating the
same effective date uses the finalizer's existing idempotent result. The new date
cannot replace a different withdrawal date that has already become effective.
New backdated paths acquire dependent rows without waiting. If settlement or
another edit holds a conflicting lock, the whole request rolls back and returns
`FORESTRING_STUDENT_SETTLEMENT_BUSY` so the user can retry. Existing lifecycle
lock ordering and cron behavior are preserved.

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
without copying row data, applies the two migrations in a disposable database,
and runs independent synthetic rollback fixtures. It preserves the source local
database. The generated database is removed afterward; schema-only diagnostics
remain under ignored `build/backdate_qa/`. Managed-role default privileges are
omitted from the clone because the local postgres role cannot change those
owners; existing object ACLs and postgres defaults are retained.

The source branch was advanced to the locally known
`origin/qa/staging-foundation` (`7727641`). Production has later migrations that
are not all represented as local files. The relevant production function,
trigger, and constraint definitions were inspected read-only, and the makeup RPC
preserves the production 45-minute duration preset.

Before production deployment, review the current live definitions again and
approve the database change separately. Apply backend migrations before shipping
the Flutter build. The Flutter client accepts the atomic `finalized` response for
past withdrawal and keeps the legacy today-finalization fallback. An older
backend rejects past writes safely. No production migration or data mutation was
performed during implementation.

Implementation validation passed: all 20 Flutter tests, full-project Flutter
analysis with no issues, both isolated SQL suites, and a separate two-session
settlement-lock check. The latter verified that both new past-date paths return
the retry error within a three-second statement timeout and leave student,
lesson, audit, and right rows unchanged.
