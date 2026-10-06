-- Серии (план: docs/02-plan/05-cross-cutting.md, «Геймификация» — «Серии: недели подряд с поездкой
-- (с „заморозкой“ на запреты и зиму)», 1.1; спецификация — docs/04-beta/M28-streaks.md).
--
-- Неделя (пн–вс по Алматы) засчитана, если в ней есть своя поездка или отчёт. Серия — сколько
-- засчитанных недель подряд до текущей. Пропущенная неделя обрывает серию, кроме «замороженной»:
-- зима (декабрь–февраль) и запрет на лов, который действует там, где вы отчитывались. Замороженная
-- неделя серию не обрывает и не прибавляет. Текущая неделя без выезда серию не обрывает — до
-- воскресенья ещё можно успеть. Видно только владельцу.

-- Почему неделя заморожена: 'winter', 'ban' или null. Месяц недели — по её четвергу.
create function private.streak_freeze(p_user uuid, p_week date) returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when extract(month from p_week + 3) in (12, 1, 2) then 'winter'
    when exists (
      select 1
        from public.regulations r
        cross join lateral (
          select make_date(extract(year from p_week + 3)::integer, r.start_month, r.start_day) as starts,
                 make_date(extract(year from p_week + 3)::integer, r.end_month, r.end_day) as ends
        ) d
       where r.kind = 'fishing_ban'
         and r.start_month is not null and r.start_day is not null
         and r.end_month is not null and r.end_day is not null
         and d.starts <= d.ends
         and d.starts <= p_week + 6
         and d.ends >= p_week
         and exists (
           select 1
             from public.checkins c
             join public.places p on p.id = c.place_id
             join public.rule_zones z on z.id = any (r.zone_ids)
            where c.owner_id = p_user
              and c.deleted_at is null
              and extensions.st_intersects(z.geom, p.geom))
    ) then 'ban'
  end;
$$;

-- Серия по неделям: засчитанные, замороженные и текущая неделя → текущая и лучшая серии.
create function private.streak_count(p_active date[], p_frozen date[], p_this_week date)
returns table (current_weeks integer, best_weeks integer)
language plpgsql
immutable
set search_path = ''
as $$
declare
  w date;
  run integer := 0;
  best integer := 0;
begin
  if coalesce(cardinality(p_active), 0) = 0 then
    return query select 0, 0;
    return;
  end if;
  w := (select min(a) from unnest(p_active) a);
  while w < p_this_week loop
    if w = any (p_active) then
      run := run + 1;
      best := greatest(best, run);
    elsif not (w = any (coalesce(p_frozen, '{}'))) then
      run := 0;
    end if;
    w := w + 7;
  end loop;
  if p_this_week = any (p_active) then
    run := run + 1;
  end if;
  return query select run, greatest(best, run);
end;
$$;

revoke execute on function private.streak_freeze(uuid, date), private.streak_count(date[], date[], date)
  from public, anon, authenticated;

-- Своя серия: текущая и лучшая, засчитана ли эта неделя и почему она заморожена.
create function public.my_streak()
returns table (current_weeks integer, best_weeks integer, this_week_done boolean, freeze_reason text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  this_week date := date_trunc('week', now() at time zone 'Asia/Almaty')::date;
  active date[];
  frozen date[];
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;

  select array_agg(distinct x.week) into active
    from (
      select date_trunc('week', t.started_at at time zone 'Asia/Almaty')::date as week
        from public.trips t
       where t.owner_id = me and t.deleted_at is null
      union all
      select date_trunc('week', c.at at time zone 'Asia/Almaty')::date
        from public.checkins c
       where c.owner_id = me and c.deleted_at is null
    ) x
   where x.week <= this_week;

  -- Замороженные — только пропущенные недели с первой засчитанной.
  select array_agg(w::date) into frozen
    from generate_series((select min(a) from unnest(active) a), this_week - 7, interval '7 days') w
   where not (w::date = any (active))
     and private.streak_freeze(me, w::date) is not null;

  return query
    select s.current_weeks, s.best_weeks, coalesce(this_week = any (active), false),
           private.streak_freeze(me, this_week)
      from private.streak_count(active, frozen, this_week) s;
end;
$$;

revoke execute on function public.my_streak() from public, anon;
grant execute on function public.my_streak() to authenticated;
