-- Погода в отчёте (план: docs/02-plan/README.md, релиз 1.1 — «погода у места»; спецификация —
-- docs/04-beta/M19-weather.md).
--
-- Телефон берёт погоду у места из Open-Meteo и кладёт снимок в `conditions.weather` отчёта:
-- температура, ветер, порывы, направление, давление у земли, код погоды WMO. Отдельной колонки нет —
-- `conditions` уже отдаётся всеми запросами отчётов (карточка места, лента, поездка, профиль).
--
-- Здесь — только проверка: в `weather` разрешены эти шесть чисел в правдоподобных пределах (иначе
-- 22023), а весь `conditions` — не больше 2 КБ (раньше размер не ограничивался).

create function private.weather_snapshot_valid(p jsonb) returns boolean
language sql
immutable
set search_path = ''
as $$
  select p is null or (
    jsonb_typeof(p) = 'object'
    and not exists (
      select 1
        from jsonb_each(p) as e(key, value)
       where case
               when e.key not in ('temperature', 'wind_speed', 'wind_gusts', 'wind_direction', 'pressure', 'code')
                 then true
               when jsonb_typeof(e.value) <> 'number'
                 then true
               else not case e.key
                 when 'temperature' then (e.value #>> '{}')::numeric between -70 and 60
                 when 'wind_speed' then (e.value #>> '{}')::numeric between 0 and 100
                 when 'wind_gusts' then (e.value #>> '{}')::numeric between 0 and 150
                 when 'wind_direction' then (e.value #>> '{}')::numeric between 0 and 360
                 when 'pressure' then (e.value #>> '{}')::numeric between 500 and 1100
                 else (e.value #>> '{}')::numeric between 0 and 99
               end
             end
    )
  );
$$;

-- Проверка — триггером: ограничение CHECK выполнялось бы с правами клиента, а схема `private` ему
-- закрыта.
create function private.checkins_weather_guard() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.weather_snapshot_valid(new.conditions -> 'weather') then
    raise exception 'invalid weather' using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke execute on function
  private.weather_snapshot_valid(jsonb),
  private.checkins_weather_guard()
from public, anon, authenticated;

create trigger checkins_weather_guard before insert or update of conditions on public.checkins
  for each row execute function private.checkins_weather_guard();

alter table public.checkins
  add constraint checkins_conditions_size check (octet_length(conditions::text) <= 2048);
