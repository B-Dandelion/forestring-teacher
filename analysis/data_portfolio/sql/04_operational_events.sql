-- Forestring Data Portfolio
-- 04_operational_events.sql
-- 최근 30/60일 audit event의 구성과 actor role을 익명 aggregate로 확인한다.

with e as (
  select event_type, actor_id, created_at
  from public.audit_events
  where created_at >= now() - interval '60 days'
)
select
  event_type,
  count(*) as events_60d,
  count(*) filter (where created_at >= now() - interval '30 days') as events_30d
from e
group by event_type
order by events_60d desc, event_type;

select
  coalesce(
    p.role::text,
    case when a.actor_id is null then 'system/null' else 'unknown' end
  ) as actor_type,
  count(*) as events_30d
from public.audit_events a
left join public.profiles p on p.id = a.actor_id
where a.created_at >= now() - interval '30 days'
group by 1
order by events_30d desc;

-- 주의:
-- audit event 1건 = 운영자가 클릭한 동작 1회라고 가정하지 않는다.
-- 하나의 도메인 동작이 여러 audit event를 만들 수 있으므로,
-- 운영 비용 proxy를 만들 때는 primary event set을 별도로 정의해야 한다.
