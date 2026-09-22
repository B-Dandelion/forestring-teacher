with
schemas as (
  select oid, nspname
  from pg_namespace
  where nspname in ('public', 'private')
),
table_state as (
  select
    'table_state'::text as category,
    count(*)::int as object_count,
    md5(coalesce(string_agg(
      concat_ws('|',
        n.nspname,
        c.relname,
        c.relkind,
        c.relrowsecurity,
        c.relforcerowsecurity
      ),
      E'\n' order by n.nspname, c.relname
    ), '')) as fingerprint
  from pg_class c
  join schemas n on n.oid = c.relnamespace
  where c.relkind in ('r', 'p', 'v', 'm', 'S')
),
columns as (
  select
    'columns'::text as category,
    count(*)::int as object_count,
    md5(coalesce(string_agg(
      concat_ws('|',
        n.nspname,
        c.relname,
        a.attnum,
        a.attname,
        format_type(a.atttypid, a.atttypmod),
        a.attnotnull,
        a.attidentity,
        a.attgenerated,
        coalesce(pg_get_expr(ad.adbin, ad.adrelid), '')
      ),
      E'\n' order by n.nspname, c.relname, a.attnum
    ), '')) as fingerprint
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join schemas n on n.oid = c.relnamespace
  left join pg_attrdef ad
    on ad.adrelid = a.attrelid
   and ad.adnum = a.attnum
  where a.attnum > 0
    and not a.attisdropped
    and c.relkind in ('r', 'p', 'v', 'm')
),
constraints as (
  select
    'constraints'::text as category,
    count(*)::int as object_count,
    md5(coalesce(string_agg(
      concat_ws('|',
        n.nspname,
        c.relname,
        con.conname,
        con.contype,
        pg_get_constraintdef(con.oid, true)
      ),
      E'\n' order by n.nspname, c.relname, con.conname
    ), '')) as fingerprint
  from pg_constraint con
  join pg_class c on c.oid = con.conrelid
  join schemas n on n.oid = c.relnamespace
),
indexes as (
  select
    'indexes'::text as category,
    count(*)::int as object_count,
    md5(coalesce(string_agg(
      concat_ws('|',
        n.nspname,
        c.relname,
        ic.relname,
        pg_get_indexdef(i.indexrelid)
      ),
      E'\n' order by n.nspname, c.relname, ic.relname
    ), '')) as fingerprint
  from pg_index i
  join pg_class c on c.oid = i.indrelid
  join schemas n on n.oid = c.relnamespace
  join pg_class ic on ic.oid = i.indexrelid
),
functions as (
  select
    'functions'::text as category,
    count(*)::int as object_count,
    md5(coalesce(string_agg(
      concat_ws('|',
        n.nspname,
        p.proname,
        pg_get_function_identity_arguments(p.oid),
        p.prokind,
        p.prosecdef,
        p.provolatile,
        p.proleakproof,
        p.proparallel,
        coalesce(array_to_string(p.proconfig, ','), ''),
        l.lanname,
        pg_get_function_result(p.oid),
        regexp_replace(
          regexp_replace(
            replace(p.prosrc, chr(13), ''),
            '--[^' || chr(10) || ']*',
            '',
            'g'
          ),
          '[[:space:]]+',
          '',
          'g'
        )
      ),
      E'\n' order by n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)
    ), '')) as fingerprint
  from pg_proc p
  join schemas n on n.oid = p.pronamespace
  join pg_language l on l.oid = p.prolang
),
policies as (
  select
    'policies'::text as category,
    count(*)::int as object_count,
    md5(coalesce(string_agg(
      concat_ws('|',
        schemaname,
        tablename,
        policyname,
        permissive,
        array_to_string(roles, ','),
        cmd,
        coalesce(qual, ''),
        coalesce(with_check, '')
      ),
      E'\n' order by schemaname, tablename, policyname
    ), '')) as fingerprint
  from pg_policies
  where schemaname in ('public', 'private')
),
triggers as (
  select
    'triggers'::text as category,
    count(*)::int as object_count,
    md5(coalesce(string_agg(
      concat_ws('|',
        n.nspname,
        c.relname,
        t.tgname,
        pg_get_triggerdef(t.oid, true)
      ),
      E'\n' order by n.nspname, c.relname, t.tgname
    ), '')) as fingerprint
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join schemas n on n.oid = c.relnamespace
  where not t.tgisinternal
)
select * from table_state
union all select * from columns
union all select * from constraints
union all select * from indexes
union all select * from functions
union all select * from policies
union all select * from triggers
order by category;
