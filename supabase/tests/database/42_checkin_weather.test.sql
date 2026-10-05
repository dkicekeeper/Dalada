-- Погода в отчёте: снимок в conditions.weather — только шесть чисел в пределах; отдаётся вместе с
-- отчётом; conditions не больше 2 КБ. A — автор отчёта, B — читатель.

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

create function pg_temp.act_as_admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Залив', 'SRID=4326;POINT(77.00 43.90)', 'public');
select pg_temp.act_as_admin();
update public.places set status = 'published' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

-- Можно ------------------------------------------------------------------------------------------

select lives_ok(
  $$ insert into public.checkins (id, place_id, visibility, conditions)
     values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'public',
             '{"bite": "good", "weather": {"temperature": 18.3, "wind_speed": 3.1, "wind_gusts": 6.2,
               "wind_direction": 45, "pressure": 918.4, "code": 2}}') $$,
  'отчёт со снимком погоды'
);
select lives_ok(
  $$ insert into public.checkins (place_id, visibility, conditions)
     values ('aaaaaaaa-0000-0000-0000-000000000001', 'public', '{"bite": "weak"}') $$,
  'и без погоды — как раньше'
);
select lives_ok(
  $$ update public.checkins set conditions = '{"weather": {"temperature": -12, "pressure": 1030}}'
      where id = 'cccccccc-0000-0000-0000-000000000001' $$,
  'правка: часть полей'
);
update public.checkins
   set conditions = '{"bite": "good", "weather": {"temperature": 18.3, "wind_speed": 3.1, "pressure": 918.4, "code": 2}}'
 where id = 'cccccccc-0000-0000-0000-000000000001';

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select conditions -> 'weather' ->> 'pressure' from public.place_reports('aaaaaaaa-0000-0000-0000-000000000001')
    where checkin_id = 'cccccccc-0000-0000-0000-000000000001'),
  '918.4',
  'погода приходит вместе с отчётом'
);

-- Нельзя -----------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok(
  $$ insert into public.checkins (place_id, conditions)
     values ('aaaaaaaa-0000-0000-0000-000000000001', '{"weather": {"temperature": 18, "city": 1}}') $$,
  '22023', null,
  'лишнее поле в погоде'
);
select throws_ok(
  $$ insert into public.checkins (place_id, conditions)
     values ('aaaaaaaa-0000-0000-0000-000000000001', '{"weather": {"temperature": "тепло"}}') $$,
  '22023', null,
  'не число'
);
select throws_ok(
  $$ insert into public.checkins (place_id, conditions)
     values ('aaaaaaaa-0000-0000-0000-000000000001', '{"weather": {"pressure": 5000}}') $$,
  '22023', null,
  'давление вне пределов'
);
select throws_ok(
  $$ insert into public.checkins (place_id, conditions)
     values ('aaaaaaaa-0000-0000-0000-000000000001', '{"weather": [1, 2]}') $$,
  '22023', null,
  'погода — не объект'
);
select throws_ok(
  $$ update public.checkins set conditions = '{"weather": {"wind_direction": 400}}'
      where id = 'cccccccc-0000-0000-0000-000000000001' $$,
  '22023', null,
  'и при правке'
);
select throws_ok(
  $$ insert into public.checkins (place_id, conditions)
     values ('aaaaaaaa-0000-0000-0000-000000000001', jsonb_build_object('bite', repeat('x', 3000))) $$,
  '23514', null,
  'conditions больше 2 КБ'
);

select * from finish();
rollback;
