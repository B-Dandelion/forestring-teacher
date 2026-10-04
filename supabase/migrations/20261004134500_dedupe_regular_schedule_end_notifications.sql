-- ============================================================
-- Forestring v3.4
-- Avoid Push storms when a regular schedule is ended.
--
-- end_regular_schedule() may emit one LESSON_CANCELED audit per
-- future lesson. Suppress those internal child events and emit one
-- schedule-level notification from REGULAR_SCHEDULE_ENDED instead.
-- ============================================================

create or replace function private.enqueue_teacher_notification_from_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_teacher_id uuid;
  v_before_teacher_id uuid;
  v_lesson_id uuid;
  v_lesson_type public.lesson_type;
  v_starts_at timestamptz;
  v_ends_at timestamptz;

  v_event_key text;
  v_title text;
  v_body text;
  v_student_name text;
  v_data jsonb := '{}'::jsonb;
begin
  if new.event_type not in (
    'LESSON_MANUALLY_UPDATED',
    'REGULAR_SCHEDULE_CHANGED',
    'REGULAR_SCHEDULE_ENDED',
    'LESSON_CANCELED',
    'MAKEUP_LESSON_CREATED',
    'MAKEUP_LESSON_CANCELED',
    'LESSON_RIGHT_BOOKED'
  ) then
    return new;
  end if;

  select p.display_name
  into v_student_name
  from public.profiles p
  where p.id = new.subject_profile_id;

  if new.event_type = 'LESSON_MANUALLY_UPDATED' then
    begin
      v_teacher_id := nullif(new.details ->> 'teacherId', '')::uuid;
    exception
      when invalid_text_representation then
        return new;
    end;

    v_event_key := 'lesson_schedule_changed';
    v_title := '수업 일정이 변경되었습니다';
    v_body :=
      coalesce(v_student_name, '학생') ||
      ' 학생의 변경된 일정을 확인해주세요.';

    v_data :=
      jsonb_build_object(
        'eventKey', v_event_key,
        'auditEventId', new.id,
        'studentId', new.subject_profile_id,
        'lessonId', new.details ->> 'lessonId',
        'branchId', new.branch_id,
        'before', new.details -> 'before',
        'after', new.details -> 'after'
      );

  elsif new.event_type = 'REGULAR_SCHEDULE_CHANGED' then
    begin
      v_teacher_id :=
        nullif(new.details #>> '{after,teacherId}', '')::uuid;

      v_before_teacher_id :=
        nullif(new.details #>> '{before,teacherId}', '')::uuid;
    exception
      when invalid_text_representation then
        return new;
    end;

    -- Teacher reassignment is covered by the assignment trigger.
    -- Avoid a duplicate "schedule changed" Push to the new teacher.
    if v_before_teacher_id is distinct from v_teacher_id then
      return new;
    end if;

    v_event_key := 'lesson_schedule_changed';
    v_title := '정규 수업 일정이 변경되었습니다';
    v_body :=
      coalesce(v_student_name, '학생') ||
      ' 학생의 변경된 정규 일정을 확인해주세요.';

    v_data :=
      jsonb_build_object(
        'eventKey', v_event_key,
        'auditEventId', new.id,
        'studentId', new.subject_profile_id,
        'branchId', new.branch_id,
        'scheduleSlotId', new.details ->> 'scheduleSlotId',
        'before', new.details -> 'before',
        'after', new.details -> 'after'
      );

  elsif new.event_type = 'REGULAR_SCHEDULE_ENDED' then
    -- Ending one regular schedule may internally cancel many future
    -- lesson rows. Those child cancellations are suppressed below so
    -- the teacher receives one schedule-level notification instead.
    begin
      select ls.teacher_id
      into v_teacher_id
      from public.lesson_series ls
      where ls.schedule_slot_id =
        nullif(new.details ->> 'scheduleSlotId', '')::uuid
      order by
        ls.effective_from desc,
        ls.id
      limit 1;
    exception
      when invalid_text_representation then
        v_teacher_id := null;
    end;

    if v_teacher_id is null then
      select a.teacher_id
      into v_teacher_id
      from public.teacher_student_assignments a
      where a.student_id = new.subject_profile_id
        and a.starts_on <= new.effective_on
        and (
          a.ends_on is null
          or a.ends_on >= new.effective_on - 1
        )
      order by
        case
          when a.ends_on is null
            or a.ends_on >= new.effective_on
          then 0
          else 1
        end,
        a.starts_on desc,
        a.id
      limit 1;
    end if;

    if v_teacher_id is null then
      return new;
    end if;

    v_event_key := 'lesson_schedule_changed';
    v_title := '정규 수업 일정이 종료되었습니다';
    v_body :=
      coalesce(v_student_name, '학생') ||
      ' 학생의 변경된 정규 일정을 확인해주세요.';

    v_data :=
      jsonb_build_object(
        'eventKey', v_event_key,
        'auditEventId', new.id,
        'studentId', new.subject_profile_id,
        'branchId', new.branch_id,
        'scheduleSlotId', new.details ->> 'scheduleSlotId',
        'effectiveOn', new.effective_on,
        'hardDeleted', new.details -> 'hardDeleted',
        'canceledLessonCount', new.details -> 'canceledLessonCount'
      );

  elsif new.event_type = 'LESSON_CANCELED' then
    -- end_regular_schedule() calls cancel_lesson() for every untouched
    -- future occurrence. Sending one Push per occurrence would create
    -- notification storms, so REGULAR_SCHEDULE_ENDED above owns that
    -- user-facing notification.
    if new.details ->> 'reason' = 'regular_schedule_ended' then
      return new;
    end if;

    begin
      v_lesson_id := nullif(new.details ->> 'lessonId', '')::uuid;
    exception
      when invalid_text_representation then
        return new;
    end;

    select
      l.teacher_id,
      l.lesson_type,
      l.starts_at,
      l.ends_at
    into
      v_teacher_id,
      v_lesson_type,
      v_starts_at,
      v_ends_at
    from public.lessons l
    where l.id = v_lesson_id;

    if not found then
      return new;
    end if;

    v_event_key := 'lesson_canceled';
    v_title := '수업이 취소되었습니다';
    v_body :=
      coalesce(v_student_name, '학생') ||
      ' 학생의 취소된 수업을 확인해주세요.';

    v_data :=
      jsonb_build_object(
        'eventKey', v_event_key,
        'auditEventId', new.id,
        'studentId', new.subject_profile_id,
        'lessonId', v_lesson_id,
        'lessonType', v_lesson_type,
        'branchId', new.branch_id,
        'startsAt', v_starts_at,
        'endsAt', v_ends_at,
        'cancellationOrigin', new.details ->> 'cancellationOrigin'
      );

  elsif new.event_type in (
    'MAKEUP_LESSON_CREATED',
    'MAKEUP_LESSON_CANCELED'
  ) then
    begin
      v_teacher_id := nullif(new.details ->> 'teacherId', '')::uuid;
    exception
      when invalid_text_representation then
        return new;
    end;

    if new.event_type = 'MAKEUP_LESSON_CREATED' then
      v_event_key := 'makeup_created';
      v_title := '보강 수업이 등록되었습니다';
      v_body :=
        coalesce(v_student_name, '학생') ||
        ' 학생의 보강 수업을 확인해주세요.';
    else
      v_event_key := 'makeup_canceled';
      v_title := '보강 수업이 취소되었습니다';
      v_body :=
        coalesce(v_student_name, '학생') ||
        ' 학생의 취소된 보강 수업을 확인해주세요.';
    end if;

    v_data :=
      jsonb_build_object(
        'eventKey', v_event_key,
        'auditEventId', new.id,
        'studentId', new.subject_profile_id,
        'lessonId', new.details ->> 'lessonId',
        'branchId', new.branch_id,
        'startsAt', new.details -> 'startsAt',
        'endsAt', new.details -> 'endsAt'
      );

  elsif new.event_type = 'LESSON_RIGHT_BOOKED' then
    begin
      v_lesson_id := nullif(new.details ->> 'lessonId', '')::uuid;
    exception
      when invalid_text_representation then
        return new;
    end;

    select
      l.teacher_id,
      l.lesson_type,
      l.starts_at,
      l.ends_at
    into
      v_teacher_id,
      v_lesson_type,
      v_starts_at,
      v_ends_at
    from public.lessons l
    where l.id = v_lesson_id;

    if not found
       or v_lesson_type <> 'flex'::public.lesson_type then
      return new;
    end if;

    v_event_key := 'flex_booking';
    v_title := '자율 학생이 수업을 예약했습니다';
    v_body :=
      coalesce(v_student_name, '학생') ||
      ' 학생의 새 예약을 확인해주세요.';

    v_data :=
      jsonb_build_object(
        'eventKey', v_event_key,
        'auditEventId', new.id,
        'studentId', new.subject_profile_id,
        'lessonId', v_lesson_id,
        'branchId', new.branch_id,
        'startsAt', v_starts_at,
        'endsAt', v_ends_at
      );
  end if;

  if v_teacher_id is null
     or v_event_key is null then
    return new;
  end if;

  perform private.enqueue_teacher_notification(
    v_teacher_id,
    v_event_key,
    'audit_event',
    new.id,
    'audit:' || new.id::text || ':' || v_teacher_id::text || ':' || v_event_key,
    v_title,
    v_body,
    v_data
  );

  return new;
end;
$$;



