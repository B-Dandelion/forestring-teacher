select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as identity_args,
  md5(p.prosrc) as raw_body_hash,
  md5(
    regexp_replace(
      regexp_replace(replace(p.prosrc, chr(13), ''), '--[^' || chr(10) || ']*', '', 'g'),
      '[[:space:]]+',
      '',
      'g'
    )
  ) as normalized_body_hash,
  p.prosecdef as security_definer,
  p.provolatile as volatility,
  p.proleakproof as leakproof,
  p.proparallel as parallel,
  coalesce(array_to_string(p.proconfig, ','),'') as proconfig,
  l.lanname as language,
  pg_get_function_result(p.oid) as result_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_language l on l.oid = p.prolang
where n.nspname in ('public', 'private')
order by n.nspname, p.proname, pg_get_function_identity_arguments(p.oid);
