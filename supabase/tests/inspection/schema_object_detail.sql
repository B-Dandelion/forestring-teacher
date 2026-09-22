select 'function' as kind,
       n.nspname as schema_name,
       p.proname as object_name,
       pg_get_function_identity_arguments(p.oid) as identity_args,
       md5(pg_get_functiondef(p.oid)) as def_hash
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'private')
union all
select 'trigger' as kind,
       n.nspname as schema_name,
       c.relname || '.' || t.tgname as object_name,
       '' as identity_args,
       md5(pg_get_triggerdef(t.oid, true)) as def_hash
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname in ('public', 'private')
  and not t.tgisinternal
order by kind, schema_name, object_name, identity_args;
