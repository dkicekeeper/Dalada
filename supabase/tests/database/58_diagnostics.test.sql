-- Отчёты о сбоях: только вошедшим; в таблице нет того, кто прислал; не больше 20 в день на аккаунт;
-- неподходящие пропускаются; клиент таблицу не читает; удаление аккаунта убирает его счётчик.
-- A — присылает отчёты.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(9);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end $$;

create function pg_temp.act_as_admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.report(kind text) returns jsonb language sql as $$
  select jsonb_build_object('kind', kind, 'app_version', '1.0 (139)', 'os_version', 'iOS 26.0',
                            'device_model', 'iPhone17,1', 'signature', 'crash exc=1 sig=11', 'payload', '{}')
$$;

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'a@test.local');

select pg_temp.act_as_anon();
select throws_ok(
  $$ select public.report_diagnostics(jsonb_build_array(pg_temp.report('crash'))) $$,
  '42501', null,
  'гость отчёты не присылает'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  public.report_diagnostics(jsonb_build_array(pg_temp.report('crash'), pg_temp.report('hang'), pg_temp.report('nope'))),
  2,
  'сохранены два, неизвестный вид пропущен'
);
select throws_ok(
  $$ select public.report_diagnostics('{"kind": "crash"}') $$,
  '22023', null,
  'нужен массив'
);
select throws_ok($$ select count(*) from private.diagnostics $$, '42501', null, 'клиент таблицу не читает');

select is(
  public.report_diagnostics((select jsonb_agg(pg_temp.report('hang')) from generate_series(1, 30))),
  18,
  'за день — не больше 20 на аккаунт'
);
select is(public.report_diagnostics(jsonb_build_array(pg_temp.report('crash'))), 0, 'дальше — ничего');

select pg_temp.act_as_admin();
select is((select count(*)::integer from private.diagnostics), 20, 'в таблице 20 отчётов');
select hasnt_column('private', 'diagnostics', 'user_id', 'кто прислал — не хранится');

delete from auth.users where id = '11111111-1111-1111-1111-111111111111';
select is((select count(*)::integer from private.diagnostics_quota), 0, 'удаление аккаунта убирает счётчик');

select * from finish();
rollback;
