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

  -- The user-facing effective boundary is the actual appointment date.
  -- Individually rescheduled lessons keep using occurrence_at only for
  -- entitlement ordering so their one-off move does not redefine the
  -- recurring baseline.
  v_old := $old$          and (
            position_lesson.occurrence_at
            at time zone 'Asia/Seoul'
          )::date >=
              p_effective_on$old$;

  v_new := $new$          and (
            case
              when position_lesson.rescheduled_by is null then
                (position_lesson.starts_at at time zone 'Asia/Seoul')::date
              else
                (position_lesson.occurrence_at at time zone 'Asia/Seoul')::date
            end
          ) >=
              p_effective_on$new$;

  if position(v_old in v_def) = 0 then
    raise exception 'FORESTRING_REGULAR_SCHEDULE_ORDINAL_BOUNDARY_PATCH_NOT_FOUND';
  end if;

  v_def := replace(v_def, v_old, v_new);

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

  -- A recurring schedule change establishes a new recurring baseline for
  -- untouched/default-following lessons. Keep occurrence_at aligned with that
  -- baseline and series_id aligned with the series version, while one-off
  -- reschedules/cancellations remain outside this mutation.
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

  -- Keep the embedded documentation consistent with the implemented model.
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

  if position(
       E'l.starts_at\n        at time zone ''Asia/Seoul'''
       in v_def
     ) = 0
     or position(
       E'position_lesson.starts_at at time zone ''Asia/Seoul'''
       in v_def
     ) = 0
     or position(
       E'series_id =\n          v_new_series_id'
       in v_def
     ) = 0
     or position(
       E'occurrence_at =\n          v_new_starts_at'
       in v_def
     ) = 0 then
    raise exception 'FORESTRING_REGULAR_SCHEDULE_ACTUAL_BOUNDARY_VERIFY_FAILED';
  end if;
end;
$mig$;
