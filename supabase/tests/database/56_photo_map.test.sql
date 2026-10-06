-- «Мои фото» на карте: только свои; точка отчёта, без неё — точка места; удалённое место без точки
-- отчёта — не на карте; чужому — пусто.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(5);

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
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Залив', 'SRID=4326;POINT(77.00 43.90)', 'private'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'fishing_spot', 'Удалённое', 'SRID=4326;POINT(77.50 43.90)', 'private');
insert into public.checkins (id, place_id, geom, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'SRID=4326;POINT(77.001 43.901)', 'private'),
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', null, 'private'),
  ('cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000002', null, 'private');
insert into public.media (id, checkin_id) values
  ('eeeeeeee-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001'),
  ('eeeeeeee-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000002'),
  ('eeeeeeee-0000-0000-0000-000000000003', 'cccccccc-0000-0000-0000-000000000003');
select pg_temp.act_as_admin();
update public.places set deleted_at = now() where id = 'aaaaaaaa-0000-0000-0000-000000000002';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is((select count(*)::integer from public.my_photo_points()), 2, 'фото без точки (место удалено) — не на карте');
select is(
  (select lon || ' ' || lat from public.my_photo_points() where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  '77.001 43.901',
  'точка отчёта'
);
select is(
  (select lon || ' ' || lat from public.my_photo_points() where id = 'eeeeeeee-0000-0000-0000-000000000002'),
  '77 43.9',
  'без точки отчёта — точка места'
);
select is(
  (select place_name from public.my_photo_points() where id = 'eeeeeeee-0000-0000-0000-000000000002'),
  'Залив',
  'с названием места'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::integer from public.my_photo_points()), 0, 'чужие фото — нет');

select * from finish();
rollback;
