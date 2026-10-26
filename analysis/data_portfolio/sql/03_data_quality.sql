-- Forestring Data Portfolio
-- 03_data_quality.sql
-- 취소 상태와 immutable cancellation ledger의 coverage를 확인한다.

with canceled as (
  select id, starts_at, canceled_at
  from public.lessons
  where starts_at >= timestamptz '2026-08-17 00:00:00+09'
    and starts_at < now()
    and status::text='canceled'
),
ev as (
  select
    lesson_id,
    count(*) as event_count,
    min(canceled_at) as first_canceled_at,
    bool_or(counts_toward_limit) as any_counts_toward_limit
  from public.lesson_cancellation_events
  where canceled_at >= timestamptz '2026-08-17 00:00:00+09'
    and canceled_at < now()
  group by lesson_id
)
select
  count(*) as canceled_lessons,
  count(*) filter (where ev.lesson_id is not null) as with_cancellation_event,
  count(*) filter (where ev.lesson_id is null) as without_cancellation_event,
  count(*) filter (where canceled.canceled_at is null) as lesson_missing_canceled_at,
  count(*) filter (where ev.event_count > 1) as lessons_with_multiple_events
from canceled
left join ev on ev.lesson_id=canceled.id;
