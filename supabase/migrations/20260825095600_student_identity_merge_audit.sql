create table if not exists private.student_identity_merge_audit (
  merge_batch_id uuid not null,
  old_student_id uuid not null,
  canonical_student_id uuid not null,
  display_name text not null,
  old_legacy_id text,
  canonical_legacy_id text,
  profile_snapshot jsonb not null,
  student_snapshot jsonb not null,
  merged_at timestamptz not null default now(),
  primary key (merge_batch_id, old_student_id)
);

create index if not exists student_identity_merge_audit_old_idx
  on private.student_identity_merge_audit(old_student_id);
create index if not exists student_identity_merge_audit_canonical_idx
  on private.student_identity_merge_audit(canonical_student_id);
