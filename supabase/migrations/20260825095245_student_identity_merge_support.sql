create table if not exists private.student_legacy_aliases (
  alias_legacy_id text primary key,
  student_id uuid not null references public.students(id) on delete cascade,
  canonical_legacy_id text not null,
  merged_at timestamptz not null default now(),
  details jsonb not null default '{}'::jsonb
);

create index if not exists student_legacy_aliases_student_idx
  on private.student_legacy_aliases(student_id);

alter table public.lessons
  drop constraint if exists lessons_series_student_identity_fk,
  add constraint lessons_series_student_identity_fk
    foreign key (series_id, student_id)
    references public.lesson_series(id, student_id)
    on update cascade
    on delete restrict;

alter table public.lesson_series
  drop constraint if exists lesson_series_schedule_slot_identity_fk,
  add constraint lesson_series_schedule_slot_identity_fk
    foreign key (schedule_slot_id, student_id, branch_id)
    references public.regular_schedule_slots(id, student_id, branch_id)
    on update cascade
    on delete restrict;

alter table public.lesson_rights
  drop constraint if exists lesson_rights_schedule_slot_identity_fk,
  add constraint lesson_rights_schedule_slot_identity_fk
    foreign key (schedule_slot_id, student_id, branch_id)
    references public.regular_schedule_slots(id, student_id, branch_id)
    on update cascade
    on delete restrict;
