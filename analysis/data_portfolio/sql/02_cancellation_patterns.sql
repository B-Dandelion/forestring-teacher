-- Forestring Data Portfolio
-- 02_cancellation_patterns.sql
-- v3 분석 시작일은 migration 시작 시점인 2026-08-17로 둔다.

with base as (
  select
    starts_at,
    starts_at at time zone 'Asia/Seoul' as local_start,
    lesson_type::text as lesson_type,
    status::text as status
  from public.lessons
  where starts_at >= timestamptz '2026-08-17 00:00:00+09'
    and starts_at < now()
),
recent30 as (
  select *
  from base
  where starts_at >= now() - interval '30 days'
)
select
  extract(isodow from local_start)::int as isodow,
  count(*) as lessons,
  count(*) filter (where status='canceled') as canceled,
  round(100.0 * count(*) filter (where status='canceled') / nullif(count(*),0), 2) as cancel_rate_pct
from recent30
group by 1
order by 1;

with recent30 as (
  select
    starts_at at time zone 'Asia/Seoul' as local_start,
    status::text as status
  from public.lessons
  where starts_at >= greatest(
    timestamptz '2026-08-17 00:00:00+09',
    now() - interval '30 days'
  )
    and starts_at < now()
)
select
  extract(hour from local_start)::int as hour_of_day,
  count(*) as lessons,
  count(*) filter (where status='canceled') as canceled,
  round(100.0 * count(*) filter (where status='canceled') / nullif(count(*),0), 2) as cancel_rate_pct
from recent30
group by 1
order by 1;

-- cancellation event가 존재하는 표본에 한해 lead time을 본다.
with cancels as (
  select
    origin::text as origin,
    counts_toward_limit,
    extract(epoch from (lesson_starts_at - canceled_at))/3600.0 as lead_hours
  from public.lesson_cancellation_events
  where canceled_at >= timestamptz '2026-08-17 00:00:00+09'
    and canceled_at < now()
)
select
  count(*) as n,
  round(percentile_cont(0.25) within group (order by lead_hours)::numeric, 2) as p25_hours,
  round(percentile_cont(0.50) within group (order by lead_hours)::numeric, 2) as median_hours,
  round(percentile_cont(0.75) within group (order by lead_hours)::numeric, 2) as p75_hours,
  count(*) filter (where lead_hours between 0 and 24) as within_24h,
  count(*) filter (where lead_hours between 0 and 48) as within_48h,
  count(*) filter (where lead_hours < 0) as recorded_after_lesson_start
from cancels;
