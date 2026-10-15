-- ============================================================
-- Forestring v3
-- Regular schedule effective-date semantics
--
-- User-facing effective dates are evaluated against the actual
-- scheduled appointment (lessons.starts_at).
--
-- occurrence_at remains the provenance anchor only for one-off
-- individually rescheduled lessons. Untouched/default-following
-- recurring lessons advance occurrence_at + series_id whenever
-- their recurring default is changed.
-- ============================================================

do $mig$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
    'public.change_regular_schedule(uuid,uuid,integer,time without time zone,integer,date)'::regprocedure
  )
  into v_def;

  -- Preserve logical entitlement positions across canceled / one-off moved
  -- lessons, but decide which side of effective_on each position belongs to
  -- from the actual recurring appointment. A one-off move must not redefine
  -- the recurring baseline, so only those rows use occurrence_at.
  v_old := $old$          and (
            position_lesson.occurrence_at
            at time zone 'Asia/Seoul'
          )::date >=
              p_effective_on

          and (
            position_lesson.occurrence_at <
              l.occurrence_at

            or (
              position_lesson.occurrence_at =
                l.occurrence_at

              and position_lesson.id <=
                  l.id
            )
          )$old$;

  v_new := $new$          and (
            case
              when position_lesson.rescheduled_by is null then
                (position_lesson.starts_at at time zone 'Asia/Seoul')::date
              else
                (position_lesson.occurrence_at at time zone 'Asia/Seoul')::date
            end
          ) >=
              p_effective_on

          and position_right.sequence_no <=
              r.sequence_no$new$;

  if position(v_old in v_def) = 0 then
    raise exception 'FORESTRING_REGULAR_SCHEDULE_ORDINAL_BOUNDARY_PATCH_NOT_FOUND';
  end if;
  v_def := replace(v_def, v_old, v_new);

  -- The mutation boundary itself follows the actual appointment date.
  v_old := $old$      and (
        l.occurrence_at
        at time zone 'Asia/Seoul'
      )::date >=
          p_effective_on$old$;

  v_new := $new$      and (
        l.starts_at
        at time zone 'Asia/Seoul'
      )::date >=
          p_effective_on$new$;

  if position(v_old in v_def) = 0 then
    raise exception 'FORESTRING_REGULAR_SCHEDULE_ACTUAL_BOUNDARY_PATCH_NOT_FOUND';
  end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$    order by
      r.source_semester_id,
      l.occurrence_at,
      l.id$old$;

  v_new := $new$    order by
      r.source_semester_id,
      r.sequence_no,
      l.id$new$;

  if position(v_old in v_def) = 0 then
    raise exception 'FORESTRING_REGULAR_SCHEDULE_ORDER_PATCH_NOT_FOUND';
  end if;
  v_def := replace(v_def, v_old, v_new);

  -- Default-following recurring lessons now carry the current recurring
  -- identity. Individually moved/canceled lessons are excluded above and keep
  -- their historical provenance.
  v_old := $old$      update public.lessons
      set
        teacher_id =
          p_teacher_id,

        starts_at =
          v_new_starts_at,$old$;

  v_new := $new$      update public.lessons
      set
        series_id =
          v_new_series_id,

        teacher_id =
          p_teacher_id,

        occurrence_at =
          v_new_starts_at,

        starts_at =
          v_new_starts_at,$new$;

  if position(v_old in v_def) = 0 then
    raise exception 'FORESTRING_REGULAR_SCHEDULE_IDENTITY_PATCH_NOT_FOUND';
  end if;
  v_def := replace(v_def, v_old, v_new);

  v_def := replace(
    v_def,
    '--   occurrence >= effective_on',
    '--   actual starts_at date >= effective_on'
  );

  v_def := replace(
    v_def,
    E'-- Existing occurrence_at remains unchanged.\n  -- Existing series_id also remains historical provenance.',
    E'-- Default-following occurrence_at and series_id advance with the recurring rule.\n  -- Individually moved/canceled lessons are excluded and retain their history.'
  );

  v_def := replace(
    v_def,
    E'--   series provenance\n    --   occurrence_at\n    --\n    -- CHANGE:\n    --   actual teacher\n    --   actual start',
    E'--\n    -- CHANGE:\n    --   recurring series version\n    --   recurring occurrence baseline\n    --   actual teacher\n    --   actual start'
  );

  execute v_def;

  select pg_get_functiondef(
    'public.change_regular_schedule(uuid,uuid,integer,time without time zone,integer,date)'::regprocedure
  )
  into v_def;

  if position(E'l.starts_at\n        at time zone ''Asia/Seoul''' in v_def) = 0
     or position('position_right.sequence_no <=' in v_def) = 0
     or position(E'r.sequence_no,\n      l.id' in v_def) = 0
     or position(E'series_id =\n          v_new_series_id' in v_def) = 0
     or position(E'occurrence_at =\n          v_new_starts_at' in v_def) = 0 then
    raise exception 'FORESTRING_REGULAR_SCHEDULE_ACTUAL_BOUNDARY_VERIFY_FAILED';
  end if;
end;
$mig$;


-- ============================================================
-- Calendar rebuild target
--
-- This helper must use the same recurring-position model as
-- change_regular_schedule or a later calendar rebuild can undo
-- a correctly changed schedule.
-- ============================================================

do $mig$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
    'private.regular_right_rebuild_target(uuid,uuid,uuid)'::regprocedure
  )
  into v_def;

  v_old := $old$      r.source_semester_id,
      r.schedule_slot_id,
      l.id as lesson_id,
      l.occurrence_at,
      (l.occurrence_at at time zone 'Asia/Seoul')::date as occurrence_date,$old$;

  v_new := $new$      r.source_semester_id,
      r.schedule_slot_id,
      r.sequence_no,
      l.id as lesson_id,
      l.occurrence_at,
      l.starts_at,
      l.rescheduled_by,
      (l.occurrence_at at time zone 'Asia/Seoul')::date as occurrence_date,
      (
        case
          when l.rescheduled_by is null then l.starts_at
          else l.occurrence_at
        end
        at time zone 'Asia/Seoul'
      )::date as schedule_anchor_date,$new$;

  if position(v_old in v_def) = 0 then
    raise exception 'FORESTRING_REGULAR_REBUILD_BASE_PATCH_NOT_FOUND';
  end if;
  v_def := replace(v_def, v_old, v_new);

  if position('b.occurrence_date >= ls.effective_from' in v_def) = 0
     or position('b.occurrence_date <= ls.effective_until' in v_def) = 0 then
    raise exception 'FORESTRING_REGULAR_REBUILD_VERSION_PATCH_NOT_FOUND';
  end if;

  v_def := replace(
    v_def,
    'b.occurrence_date >= ls.effective_from',
    'b.schedule_anchor_date >= ls.effective_from'
  );
  v_def := replace(
    v_def,
    'b.occurrence_date <= ls.effective_until',
    'b.schedule_anchor_date <= ls.effective_until'
  );

  v_old := $old$          and (l2.occurrence_at at time zone 'Asia/Seoul')::date >= v.effective_from
          and (
            v.effective_until is null
            or (l2.occurrence_at at time zone 'Asia/Seoul')::date <= v.effective_until
          )
          and (
            l2.occurrence_at < v.occurrence_at
            or (l2.occurrence_at = v.occurrence_at and l2.id <= v.lesson_id)
          )$old$;

  v_new := $new$          and (
            case
              when l2.rescheduled_by is null then l2.starts_at
              else l2.occurrence_at
            end
            at time zone 'Asia/Seoul'
          )::date >= v.effective_from
          and (
            v.effective_until is null
            or (
              case
                when l2.rescheduled_by is null then l2.starts_at
                else l2.occurrence_at
              end
              at time zone 'Asia/Seoul'
            )::date <= v.effective_until
          )
          and r2.sequence_no <= v.sequence_no$new$;

  if position(v_old in v_def) = 0 then
    raise exception 'FORESTRING_REGULAR_REBUILD_ORDINAL_PATCH_NOT_FOUND';
  end if;
  v_def := replace(v_def, v_old, v_new);

  execute v_def;

  select pg_get_functiondef(
    'private.regular_right_rebuild_target(uuid,uuid,uuid)'::regprocedure
  )
  into v_def;

  if position('schedule_anchor_date' in v_def) = 0
     or position('r2.sequence_no <= v.sequence_no' in v_def) = 0
     or position('l2.rescheduled_by is null' in v_def) = 0 then
    raise exception 'FORESTRING_REGULAR_REBUILD_ACTUAL_BOUNDARY_VERIFY_FAILED';
  end if;
end;
$mig$;


-- ============================================================
-- End regular schedule
--
-- Ending from a user-selected date uses the same actual-date
-- boundary as changing the recurring schedule.
-- ============================================================

do $mig$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
    'public.end_regular_schedule(uuid,date)'::regprocedure
  )
  into v_def;

  v_old := $old$        and (l.occurrence_at at time zone 'Asia/Seoul')::date >= p_effective_on
        and l.starts_at > pg_catalog.now()
      order by l.occurrence_at,l.id$old$;

  v_new := $new$        and (l.starts_at at time zone 'Asia/Seoul')::date >= p_effective_on
        and l.starts_at > pg_catalog.now()
      order by l.starts_at,l.id$new$;

  if position(v_old in v_def) = 0 then
    raise exception 'FORESTRING_END_REGULAR_ACTUAL_BOUNDARY_PATCH_NOT_FOUND';
  end if;
  v_def := replace(v_def, v_old, v_new);

  execute v_def;

  select pg_get_functiondef(
    'public.end_regular_schedule(uuid,date)'::regprocedure
  )
  into v_def;

  if position(
       '(l.starts_at at time zone ''Asia/Seoul'')::date >= p_effective_on'
       in v_def
     ) = 0 then
    raise exception 'FORESTRING_END_REGULAR_ACTUAL_BOUNDARY_VERIFY_FAILED';
  end if;
end;
$mig$;
