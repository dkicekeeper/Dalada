-- Отчёты iOS о сбоях и зависаниях (MetricKit, docs/05-release/README.md, R1). Приходят, только если
-- человек разрешил в Настройках iOS делиться аналитикой с разработчиками. В отчёте — версия
-- приложения и iOS, модель телефона и стек вызовов; кто прислал, не хранится. Отдельно — счётчик
-- отчётов за день на аккаунт (только число), чтобы один телефон не завалил таблицу.

create table private.diagnostics (
  id bigint generated always as identity primary key,
  received_at timestamptz not null default now(),
  kind text not null check (kind in ('crash', 'hang', 'cpu', 'disk', 'launch')),
  app_version text not null check (length(app_version) between 1 and 32),
  os_version text not null check (length(os_version) between 1 and 64),
  device_model text not null check (length(device_model) between 1 and 64),
  signature text not null check (length(signature) between 1 and 300),
  -- JSON стека вызовов от MetricKit как текст; большой стек приложение не присылает.
  payload text not null check (length(payload) <= 65536)
);

alter table private.diagnostics enable row level security;
revoke all on table private.diagnostics from anon, authenticated;
create index diagnostics_received_at on private.diagnostics (received_at);

create table private.diagnostics_quota (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  reports integer not null default 0,
  primary key (user_id, day)
);

alter table private.diagnostics_quota enable row level security;
revoke all on table private.diagnostics_quota from anon, authenticated;

-- Принимает массив отчётов, сохраняет подходящие (не больше 20 в день на аккаунт), возвращает,
-- сколько сохранено. Неподходящие (неизвестный вид, пустые или длинные поля) молча пропускает:
-- повторять их приложению незачем.
create function public.report_diagnostics(p_items jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_day date := (now() at time zone 'Asia/Almaty')::date;
  v_used integer;
  v_saved integer := 0;
  v_item jsonb;
begin
  if v_user is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'items must be an array' using errcode = '22023';
  end if;

  insert into private.diagnostics_quota (user_id, day) values (v_user, v_day) on conflict do nothing;
  select q.reports into v_used from private.diagnostics_quota q
   where q.user_id = v_user and q.day = v_day for update;

  for v_item in select value from jsonb_array_elements(p_items) limit greatest(20 - v_used, 0) loop
    begin
      insert into private.diagnostics (kind, app_version, os_version, device_model, signature, payload)
      values (v_item ->> 'kind', v_item ->> 'app_version', v_item ->> 'os_version',
              v_item ->> 'device_model', v_item ->> 'signature', coalesce(v_item ->> 'payload', '{}'));
      v_saved := v_saved + 1;
    exception when check_violation or not_null_violation then
      null;
    end;
  end loop;

  update private.diagnostics_quota set reports = reports + v_saved
   where user_id = v_user and day = v_day;
  return v_saved;
end;
$$;

revoke execute on function public.report_diagnostics(jsonb) from public, anon;
grant execute on function public.report_diagnostics(jsonb) to authenticated;

-- Отчёты храним 90 дней, счётчики — до конца следующего дня.
create function private.diagnostics_cleanup()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from private.diagnostics where received_at < now() - interval '90 days';
  delete from private.diagnostics_quota where day < (now() at time zone 'Asia/Almaty')::date - 1;
$$;

revoke execute on function private.diagnostics_cleanup() from public, anon, authenticated;

select cron.schedule('diagnostics-cleanup', '37 3 * * *', 'select private.diagnostics_cleanup()');
