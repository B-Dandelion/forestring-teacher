do $migration$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(
    'public.change_regular_schedule(uuid,uuid,integer,time without time zone,integer,date)'::regprocedure
  ) into v_def;

  if position('v_effective_week_start date;' in v_def) = 0 then
    v_new := replace(
      v_def,
      '  v_today date;' || chr(10) || chr(10) || '  v_slot public.regular_schedule_slots%rowtype;',
      '  v_today date;' || chr(10) || chr(10) ||
      '  v_effective_week_start date;' || chr(10) || chr(10) ||
      '  v_slot public.regular_schedule_slots%rowtype;'
    );
    if v_new = v_def then
      raise exception 'FORESTRING_MIGRATION_MARKER_NOT_FOUND: declare effective week';
    end if;
    v_def := v_new;

    v_new := replace(
      v_def,
      '  -- ==========================================================' || chr(10) ||
      '  -- 4. STUDENT',
      '  -- The selected effective date represents its calendar week.' || chr(10) ||
      '  -- Recurring schedule reconciliation therefore begins from' || chr(10) ||
      '  -- the Monday containing that date, never before slot start.' || chr(10) ||
      '  v_effective_week_start :=' || chr(10) ||
      '    greatest(' || chr(10) ||
      '      pg_catalog.date_trunc(''week'', p_effective_on::timestamp)::date,' || chr(10) ||
      '      v_slot.starts_on' || chr(10) ||
      '    );' || chr(10) || chr(10) ||
      '  -- ==========================================================' || chr(10) ||
      '  -- 4. STUDENT'
    );
    if v_new = v_def then
      raise exception 'FORESTRING_MIGRATION_MARKER_NOT_FOUND: week start';
    end if;
    v_def := v_new;

    v_new := replace(
      v_def,
      '    and ls.effective_from <=' || chr(10) || '        p_effective_on',
      '    and ls.effective_from <=' || chr(10) || '        v_effective_week_start'
    );
    if v_new = v_def then raise exception 'FORESTRING_MIGRATION_MARKER_NOT_FOUND: series lookup from'; end if;
    v_def := v_new;

    v_new := replace(
      v_def,
      '      or ls.effective_until >=' || chr(10) || '         p_effective_on',
      '      or ls.effective_until >=' || chr(10) || '         v_effective_week_start'
    );
    if v_new = v_def then raise exception 'FORESTRING_MIGRATION_MARKER_NOT_FOUND: series lookup until'; end if;
    v_def := v_new;

    v_new := replace(
      v_def,
      '      and ls.effective_from >' || chr(10) || '          p_effective_on',
      '      and ls.effective_from >' || chr(10) || '          v_effective_week_start'
    );
    if v_new = v_def then raise exception 'FORESTRING_MIGRATION_MARKER_NOT_FOUND: future version'; end if;
    v_def := v_new;

    v_new := replace(
      v_def,
      '  if v_old_series.effective_from =' || chr(10) || '     p_effective_on then',
      '  if v_old_series.effective_from =' || chr(10) || '     v_effective_week_start then'
    );
    if v_new = v_def then raise exception 'FORESTRING_MIGRATION_MARKER_NOT_FOUND: in place'; end if;
    v_def := v_new;

    v_new := replace(
      v_def,
      '      effective_until =' || chr(10) || '        p_effective_on - 1',
      '      effective_until =' || chr(10) || '        v_effective_week_start - 1'
    );
    if v_new = v_def then raise exception 'FORESTRING_MIGRATION_MARKER_NOT_FOUND: close old series'; end if;
    v_def := v_new;

    v_new := replace(
      v_def,
      '        p_effective_on,' || chr(10) || '        v_new_effective_until,',
      '        v_effective_week_start,' || chr(10) || '        v_new_effective_until,'
    );
    if v_new = v_def then raise exception 'FORESTRING_MIGRATION_MARKER_NOT_FOUND: new series start'; end if;
    v_def := v_new;

    v_new := replace(
      v_def,
      '          ) >=' || chr(10) || '              p_effective_on',
      '          ) >=' || chr(10) || '              v_effective_week_start'
    );
    if v_new = v_def then raise exception 'FORESTRING_MIGRATION_MARKER_NOT_FOUND: ordinal week boundary'; end if;
    v_def := v_new;

    v_new := replace(
      v_def,
      '      )::date >=' || chr(10) || '          p_effective_on',
      '      )::date >=' || chr(10) || '          v_effective_week_start'
    );
    if v_new = v_def then raise exception 'FORESTRING_MIGRATION_MARKER_NOT_FOUND: lesson week boundary'; end if;
    v_def := v_new;

    v_new := replace(
      v_def,
      '          v_semester_start,' || chr(10) || '          p_effective_on',
      '          v_semester_start,' || chr(10) || '          v_effective_week_start'
    );
    if v_new = v_def then raise exception 'FORESTRING_MIGRATION_MARKER_NOT_FOUND: candidate week boundary'; end if;
    v_def := v_new;

    v_new := replace(
      v_def,
      '      ''reconciledLessonCount'',' || chr(10) || '        v_reconciled_count',
      '      ''requestedEffectiveOn'',' || chr(10) || '        p_effective_on,' || chr(10) || chr(10) ||
      '      ''effectiveWeekStart'',' || chr(10) || '        v_effective_week_start,' || chr(10) || chr(10) ||
      '      ''reconciledLessonCount'',' || chr(10) || '        v_reconciled_count'
    );
    if v_new = v_def then raise exception 'FORESTRING_MIGRATION_MARKER_NOT_FOUND: audit week fields'; end if;
    v_def := v_new;

    v_new := replace(
      v_def,
      '    ''effectiveOn'',' || chr(10) || '      p_effective_on,' || chr(10) || chr(10) ||
      '    ''teacherId'',',
      '    ''effectiveOn'',' || chr(10) || '      p_effective_on,' || chr(10) || chr(10) ||
      '    ''effectiveWeekStart'',' || chr(10) || '      v_effective_week_start,' || chr(10) || chr(10) ||
      '    ''teacherId'','
    );
    if v_new = v_def then raise exception 'FORESTRING_MIGRATION_MARKER_NOT_FOUND: result week field'; end if;
    v_def := v_new;

    execute v_def;
  end if;

  select pg_get_functiondef(
    'public.change_regular_schedule(uuid,uuid,integer,time without time zone,integer,date)'::regprocedure
  ) into v_def;

  if position('v_effective_week_start date;' in v_def) = 0
     or position('date_trunc(''week'', p_effective_on::timestamp)' in v_def) = 0
     or position('''effectiveWeekStart''' in v_def) = 0 then
    raise exception 'FORESTRING_REGULAR_SCHEDULE_WEEK_BOUNDARY_NOT_ENFORCED';
  end if;
end;
$migration$;
