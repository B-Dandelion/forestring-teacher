-- Forestring Data Portfolio
-- 01_baseline.sql
-- Read-only aggregate query. KST 기준.

with past as (
  select
    starts_at,
    starts_at at time zone 'Asia/Seoul' as local_start,
    lesson_type::text as lesson_type,
    status::text as status,
    duration_minutes
  from public.lessons
  where starts_at < now()
)
select
  min(local_start) as min_local_start,
  max(local_start) as max_local_start,
  count(*) as total_lessons,
  count(*) filter (where status='scheduled') as scheduled_lessons,
  count(*) filter (where status='canceled') as canceled_lessons,
  round(
    100.0 * count(*) filter (where status='canceled') / nullif(count(*),0),
    2
  ) as cancel_rate_pct
from past;

-- 월별
with past as (
  select
    starts_at at time zone 'Asia/Seoul' as local_start,
    status::text as status
  from public.lessons
  where starts_at < now()
)
select
  to_char(date_trunc('month', local_start), 'YYYY-MM') as month,
  count(*) as lessons,
  count(*) filter (where status='canceled') as canceled,
  round(100.0 * count(*) filter (where status='canceled') / nullif(count(*),0), 2) as cancel_rate_pct
from past
group by 1
order by 1;
