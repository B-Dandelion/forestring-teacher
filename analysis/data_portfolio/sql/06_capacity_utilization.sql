-- Forestring Data Portfolio
-- 06_capacity_utilization.sql
-- Recorded teacher work-hour capacity vs lessons.
--
-- IMPORTANT:
-- - This is a utilization PROXY, not payroll/productivity.
-- - Only teacher/date combinations with an effective work-hour version are included.
-- - Branch closures are excluded from capacity.
-- - Historical work-hour version coverage is incomplete before 2026-08-24,
--   so the initial portfolio snapshot uses 2026-08-24 ~ 2026-09-20.

with params as (
  select date '2026-08-24' as start_date, date '2026-09-20' as end_date
),
days as (
  select generate_series(start_date,end_date,interval '1 day')::date as d
  from params
),
capacity_segments as (
  select
    d.d,
    v.teacher_id,
    p.branch_id,
    e.weekday,
    extract(epoch from (e.end_time-e.start_time))/60.0 as capacity_minutes
  from days d
  join private.teacher_work_hour_versions v
    on v.effective_from <= d.d
   and (v.effective_until is null or v.effective_until >= d.d)
  join private.teacher_work_hour_entries e
    on e.version_id = v.id
   and e.weekday = extract(isodow from d.d)::smallint
  join public.profiles p
    on p.id = v.teacher_id
  where not exists (
    select 1
    from public.closure_periods cp
    where cp.branch_id = p.branch_id
      and d.d between cp.starts_on and cp.ends_on
  )
),
covered_teacher_days as (
  select distinct d, teacher_id
  from capacity_segments
),
capacity as (
  select d, sum(capacity_minutes) as capacity_minutes
  from capacity_segments
  group by d
),
lesson_daily as (
  select
    (l.starts_at at time zone 'Asia/Seoul')::date as d,
    sum(l.duration_minutes) filter (where l.status::text='scheduled') as scheduled_minutes,
    sum(l.duration_minutes) filter (where l.status::text='canceled') as canceled_minutes,
    count(*) filter (where l.status::text='scheduled') as scheduled_lessons,
    count(*) filter (where l.status::text='canceled') as canceled_lessons
  from public.lessons l
  join covered_teacher_days c
    on c.teacher_id = l.teacher_id
   and c.d = (l.starts_at at time zone 'Asia/Seoul')::date
  where (l.starts_at at time zone 'Asia/Seoul')::date
        between date '2026-08-24' and date '2026-09-20'
  group by 1
),
joined as (
  select
    d.d,
    extract(isodow from d.d)::int as isodow,
    coalesce(c.capacity_minutes,0) as capacity_minutes,
    coalesce(l.scheduled_minutes,0) as scheduled_minutes,
    coalesce(l.canceled_minutes,0) as canceled_minutes,
    coalesce(l.scheduled_lessons,0) as scheduled_lessons,
    coalesce(l.canceled_lessons,0) as canceled_lessons
  from days d
  left join capacity c using(d)
  left join lesson_daily l using(d)
)
select
  isodow,
  round(sum(capacity_minutes)/60.0,2) as capacity_hours,
  round(sum(scheduled_minutes)/60.0,2) as scheduled_hours,
  round(sum(canceled_minutes)/60.0,2) as canceled_hours,
  round(100.0*sum(scheduled_minutes)/nullif(sum(capacity_minutes),0),2)
    as scheduled_utilization_pct,
  round(100.0*sum(scheduled_minutes+canceled_minutes)/nullif(sum(capacity_minutes),0),2)
    as booked_utilization_pct
from joined
group by isodow
order by isodow;

-- Coverage check: how much lesson history is eligible for this proxy?
with l as (
  select
    teacher_id,
    duration_minutes,
    starts_at at time zone 'Asia/Seoul' as local_start
  from public.lessons
  where (starts_at at time zone 'Asia/Seoul')::date
        between date '2026-08-24' and date '2026-09-20'
),
marked as (
  select
    l.*,
    exists (
      select 1
      from private.teacher_work_hour_versions v
      where v.teacher_id=l.teacher_id
        and v.effective_from <= l.local_start::date
        and (v.effective_until is null or v.effective_until >= l.local_start::date)
    ) as has_version
  from l
)
select
  count(*) as total_lessons,
  count(*) filter(where has_version) as covered_lessons,
  round(100.0*count(*) filter(where has_version)/nullif(count(*),0),2) as lesson_coverage_pct,
  sum(duration_minutes) as total_minutes,
  sum(duration_minutes) filter(where has_version) as covered_minutes,
  round(
    100.0*sum(duration_minutes) filter(where has_version)
    / nullif(sum(duration_minutes),0),
    2
  ) as duration_coverage_pct
from marked;
