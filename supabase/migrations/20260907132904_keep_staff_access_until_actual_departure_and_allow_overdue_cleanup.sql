create or replace function private.profile_has_effective_access(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
    from public.profiles p
    left join public.teachers t on t.id = p.id
    left join public.students s on s.id = p.id
    where p.id = p_profile_id
      and p.is_active = true
      and (
        p.role = 'master'::public.user_role
        or (
          p.role in ('teacher'::public.user_role,'manager'::public.user_role)
          and t.id is not null
        )
        or (
          p.role = 'student'::public.user_role
          and s.id is not null
          and s.status = 'active'::public.student_status
          and (
            s.withdrawal_date is null
            or (pg_catalog.now() at time zone 'Asia/Seoul')::date < s.withdrawal_date
          )
        )
      )
  );
$function$;

create or replace function private.staff_departure_blocker_summary(
  p_staff_id uuid,
  p_withdrawal_date date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_today date;
  v_cutoff_date date;
  v_cutoff_at timestamptz;

  v_assignment_count integer;
  v_series_count integer;
  v_lesson_count integer;
  v_student_ids uuid[];
  v_lesson_ids uuid[];
begin
  if p_staff_id is null or p_withdrawal_date is null then
    raise exception using
      errcode='P0001',
      message='FORESTRING_STAFF_DEPARTURE_CONTEXT_REQUIRED';
  end if;

  v_today := (pg_catalog.now() at time zone 'Asia/Seoul')::date;
  v_cutoff_date := greatest(p_withdrawal_date, v_today);
  v_cutoff_at := greatest(
    pg_catalog.now(),
    (p_withdrawal_date::timestamp at time zone 'Asia/Seoul')
  );

  select count(*)::integer,
         array_agg(distinct a.student_id)
  into v_assignment_count, v_student_ids
  from public.teacher_student_assignments a
  where a.teacher_id = p_staff_id
    and (a.ends_on is null or a.ends_on >= v_cutoff_date);

  select count(*)::integer
  into v_series_count
  from public.lesson_series ls
  where ls.teacher_id = p_staff_id
    and (ls.effective_until is null or ls.effective_until >= v_cutoff_date);

  select count(*)::integer,
         array_agg(l.id order by l.starts_at)
  into v_lesson_count, v_lesson_ids
  from public.lessons l
  where l.teacher_id = p_staff_id
    and l.status = 'scheduled'::public.lesson_status
    and l.ends_at > v_cutoff_at;

  return jsonb_build_object(
    'assignmentCount', coalesce(v_assignment_count,0),
    'studentIds', coalesce(to_jsonb(v_student_ids),'[]'::jsonb),
    'seriesCount', coalesce(v_series_count,0),
    'scheduledLessonCount', coalesce(v_lesson_count,0),
    'scheduledLessonIds', coalesce(to_jsonb(v_lesson_ids),'[]'::jsonb),
    'canFinalize',
      coalesce(v_assignment_count,0)=0
      and coalesce(v_series_count,0)=0
      and coalesce(v_lesson_count,0)=0
  );
end;
$function$;

create or replace function public.assert_assignment_before_teacher_withdrawal()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_withdrawal_date date;
  v_today date;
begin
  select t.withdrawal_date
  into v_withdrawal_date
  from public.teachers t
  where t.id = new.teacher_id;

  if v_withdrawal_date is null then
    return new;
  end if;

  v_today := (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  if tg_op = 'UPDATE'
     and old.teacher_id = new.teacher_id
     and old.starts_on = new.starts_on
     and v_withdrawal_date <= v_today
     and new.ends_on is not null
     and new.ends_on < v_today
     and (old.ends_on is null or new.ends_on < old.ends_on) then
    return new;
  end if;

  if new.starts_on >= v_withdrawal_date
     or new.ends_on is null
     or new.ends_on >= v_withdrawal_date then
    raise exception using
      errcode='P0001',
      message='FORESTRING_ASSIGNMENT_ON_OR_AFTER_TEACHER_WITHDRAWAL';
  end if;

  return new;
end;
$function$;

create or replace function public.assert_series_before_teacher_withdrawal()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_withdrawal_date date;
  v_today date;
begin
  select t.withdrawal_date
  into v_withdrawal_date
  from public.teachers t
  where t.id = new.teacher_id;

  if v_withdrawal_date is null then
    return new;
  end if;

  v_today := (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  if tg_op = 'UPDATE'
     and old.teacher_id = new.teacher_id
     and old.effective_from = new.effective_from
     and v_withdrawal_date <= v_today
     and new.effective_until is not null
     and new.effective_until < v_today
     and (old.effective_until is null or new.effective_until < old.effective_until) then
    return new;
  end if;

  if new.effective_from >= v_withdrawal_date
     or new.effective_until is null
     or new.effective_until >= v_withdrawal_date then
    raise exception using
      errcode='P0001',
      message='FORESTRING_SERIES_ON_OR_AFTER_TEACHER_WITHDRAWAL';
  end if;

  return new;
end;
$function$;