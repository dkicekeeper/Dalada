-- Раздел «Фото» в профиле: только свои фото (отчёты, уловы, отзывы), без удалённых, новые сверху,
-- страницы по курсору; название чужого места — только пока оно видно.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(7);

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

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local');

-- B — автор публичного места; A отмечается там и в своём месте.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.places (id, type, name, geom, visibility)
values ('aaaaaaaa-0000-0000-0000-000000000002', 'fishing_spot', 'Чужое', 'SRID=4326;POINT(77.10 43.90)', 'public');
select pg_temp.act_as_admin();
update public.places set status = 'published' where id = 'aaaaaaaa-0000-0000-0000-000000000002';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Своё', 'SRID=4326;POINT(77.00 43.90)', 'private');
insert into public.checkins (id, place_id, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'private'),
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', 'public');
insert into public.media (id, checkin_id) values
  ('eeeeeeee-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001'),
  ('eeeeeeee-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000002'),
  ('eeeeeeee-0000-0000-0000-000000000003', 'cccccccc-0000-0000-0000-000000000002');
update public.media set deleted_at = now() where id = 'eeeeeeee-0000-0000-0000-000000000003';
create temp table review_id as
  select public.save_review('aaaaaaaa-0000-0000-0000-000000000002', 5, 'Хорошо') as id;
insert into public.media (id, review_id)
values ('eeeeeeee-0000-0000-0000-000000000004', (select id from review_id));

-- Время загрузки — по порядку (created_at выставляет триггер, в одной транзакции оно одинаковое).
select pg_temp.act_as_admin();
set local session_replication_role = replica;
update public.media set created_at = now() - make_interval(mins => 10 - right(id::text, 1)::integer);
set local session_replication_role = origin;

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::integer from public.my_photos()), 0, 'у B своих фото нет — чужие не видны');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select array_agg(id) from public.my_photos(10, 'eeeeeeee-0000-0000-0000-000000000004')),
  array['eeeeeeee-0000-0000-0000-000000000002', 'eeeeeeee-0000-0000-0000-000000000001']::uuid[],
  'курсор — id: время берётся из базы'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select array_agg(id order by created_at desc, id desc) from public.my_photos()),
  array['eeeeeeee-0000-0000-0000-000000000004', 'eeeeeeee-0000-0000-0000-000000000002',
        'eeeeeeee-0000-0000-0000-000000000001']::uuid[],
  'свои фото отчётов и отзыва, новые сверху, без удалённого'
);
select is(
  (select array_agg(place_name order by created_at desc) from public.my_photos()),
  array['Чужое', 'Чужое', 'Своё'],
  'с названием места'
);
select is(
  (select array_agg(id) from public.my_photos(10, 'eeeeeeee-0000-0000-0000-000000000002')),
  array['eeeeeeee-0000-0000-0000-000000000001']::uuid[],
  'следующая страница — после последнего показанного'
);

-- B скрыл своё место — название пропадает, фото остаётся.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
update public.places set visibility = 'private' where id = 'aaaaaaaa-0000-0000-0000-000000000002';
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select place_name from public.my_photos() where id = 'eeeeeeee-0000-0000-0000-000000000002'),
  null,
  'чужое место больше не видно — без названия'
);

select pg_temp.act_as_anon();
select throws_ok($$ select * from public.my_photos() $$, '42501', null, 'гостю нельзя');

select * from finish();
rollback;
