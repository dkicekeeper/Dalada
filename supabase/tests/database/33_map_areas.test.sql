-- M16: слои карты — нацпарки, заповедник, погранполоса и погранзона. Справочник для всех, клиенту —
-- только чтение; геометрии корректные и стоят там, где надо.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(10);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'a@test.local');

-- Гость ------------------------------------------------------------------------------------------

set local role anon;
select is(
  (select string_agg(id, ',' order by sort_order) from public.map_areas),
  'ile_alatau,almaty_reserve,kolsai,charyn,altyn_emel,zhongar_alatau,border_strip_cn,border_zone_kg',
  'гость видит все слои'
);
select is(
  (select tenge from public.mrp_values where year = 2026),
  4325,
  'МРП 2026 года доступен для пересчёта тарифов'
);
reset role;

-- Только чтение ------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok(
  $$ update public.map_areas set fee_car_mrp = 0 where id = 'kolsai' $$,
  '42501', null,
  'менять слои клиент не может'
);
select throws_ok(
  $$ insert into public.mrp_values (year, tenge) values (2027, 1) $$,
  '42501', null,
  'и МРП тоже'
);
reset role;

-- Данные -----------------------------------------------------------------------------------------

select ok(
  (select bool_and(extensions.st_isvalid(geom) and not extensions.st_isempty(geom)) from public.map_areas),
  'все границы корректные и не пустые'
);
select ok(
  (select bool_and(source_title <> '' and verified_on is not null) from public.map_areas),
  'у каждого слоя — первоисточник и дата проверки'
);
select ok(
  (select extensions.st_contains(geom, extensions.st_setsrid(extensions.st_makepoint(78.3247, 42.9876), 4326))
     from public.map_areas where id = 'kolsai'),
  'первое Кольсайское озеро — в границах парка'
);
select is(
  (select count(*)::integer from public.map_areas
    where kind in ('national_park', 'nature_reserve')
      and extensions.st_contains(geom, extensions.st_setsrid(extensions.st_makepoint(76.9458, 43.2380), 4326))),
  0,
  'центр Алматы — не в нацпарке'
);
select ok(
  (select extensions.st_contains(geom, extensions.st_setsrid(extensions.st_makepoint(80.3850, 44.2000), 4326))
     from public.map_areas where id = 'border_strip_cn'),
  'в километре от границы у Хоргоса — погранполоса с Китаем'
);
select ok(
  (select not extensions.st_intersects(geom, extensions.st_setsrid(extensions.st_makepoint(77.05, 43.85), 4326))
     from public.map_areas where id = 'border_zone_kg'),
  'Капшагай — вне погранзоны'
);

select * from finish();
rollback;
