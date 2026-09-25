-- Forestring Data Portfolio
-- 05_student_lifecycle.sql
-- 월별 학생 lifecycle과 v3 기간 재원기간별 취소 패턴을 탐색한다.

with bounds as (
  select
    date_trunc('month', min(starts_on))::date as min_month,
    date_trunc('month', current_date)::date as max_month
  from public.student_enrollment_periods
),
months as (
  select generate_series(min_month, max_month, interval '1 month')::date as month_start
  from bounds
)
select
  to_char(m.month_start, 'YYYY-MM') as month,
  (
    select count(distinct sep.student_id)
    from public.student_enrollment_periods sep
    where sep.starts_on <= (m.month_start + interval '1 month - 1 day')::date
      and (sep.ends_on is null or sep.ends_on >= (m.month_start + interval '1 month - 1 day')::date)
  ) as active_at_month_end,
  (
    select count(*)
    from public.student_enrollment_periods sep
    where sep.starts_on >= m.month_start
      and sep.starts_on < (m.month_start + interval '1 month')::date
  ) as enrollments,
  (
    select count(*)
    from public.student_enrollment_periods sep
    where sep.ends_on >= m.month_start
      and sep.ends_on < (m.month_start + interval '1 month')::date
  ) as exits
from months m
order by m.month_start;

-- v3 기간의 lesson을 해당 시점 enrollment period와 연결해 tenure cohort를 본다.
with lesson_with_tenure as (
  select
    l.id,
    l.status::text as status,
    (l.starts_at at time zone 'Asia/Seoul')::date as lesson_date,
    sep.starts_on,
    ((l.starts_at at time zone 'Asia/Seoul')::date - sep.starts_on) as tenure_days
  from public.lessons l
  join public.student_enrollment_periods sep
    on sep.student_id = l.student_id
   and sep.starts_on <= (l.starts_at at time zone 'Asia/Seoul')::date
   and (sep.ends_on is null or sep.ends_on >= (l.starts_at at time zone 'Asia/Seoul')::date)
  where l.starts_at >= timestamptz '2026-08-17 00:00:00+09'
    and l.starts_at < now()
),
bucketed as (
  select
    case
      when tenure_days < 31 then '00-30d'
      when tenure_days < 91 then '31-90d'
      when tenure_days < 181 then '91-180d'
      else '181d+'
    end as tenure_bucket,
    status
  from lesson_with_tenure
)
select
  tenure_bucket,
  count(*) as lessons,
  count(*) filter (where status='canceled') as canceled,
  round(100.0 * count(*) filter (where status='canceled') / nullif(count(*),0), 2) as cancel_rate_pct
from bucketed
group by tenure_bucket
order by min(
  case tenure_bucket
    when '00-30d' then 1
    when '31-90d' then 2
    when '91-180d' then 3
    else 4
  end
);
