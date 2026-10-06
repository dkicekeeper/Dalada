-- Уведомления сборки 135: друг начал показывать, где он (не чаще раза в 6 часов, настройка);
-- приглашение в общие сборы (только приглашённым); «вы — смотритель места» (один раз, пока статус не
-- перешёл к другому).
-- A — показывает и зовёт; B — друг; C — друг с выключенной настройкой; D и E — авторы отчётов.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(12);

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

create function pg_temp.pushes(uid uuid, k text) returns integer language sql as $$
  select count(*)::integer from private.push_outbox where user_id = uid and kind::text = k
$$;

create function pg_temp.checkins(uid uuid, place uuid, n integer, hours_ago integer) returns void
language plpgsql as $$
begin
  perform pg_temp.act_as(uid);
  for i in 0 .. n - 1 loop
    insert into public.checkins (place_id, at, geom, visibility)
    values (place, now() - make_interval(hours => hours_ago + i), 'SRID=4326;POINT(77.00 43.90)', 'public');
  end loop;
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'd@test.local'),
  ('55555555-5555-5555-5555-555555555555', 'e@test.local');

insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111'),
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111');
insert into public.devices (user_id, token, environment)
select id, repeat(left(id::text, 2), 32), 'production' from auth.users;
update public.profiles set notify_live_share = false where id = '33333333-3333-3333-3333-333333333333';

-- Трансляция ------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select public.start_live_share(array[
  '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333'
]::uuid[]);
select pg_temp.act_as_admin();
select is(pg_temp.pushes('22222222-2222-2222-2222-222222222222', 'live_share'), 1, 'друг узнаёт, что ему показывают, где я');
select is(
  (select payload ->> 'username' is not distinct from (select username from public.profiles where id = '11111111-1111-1111-1111-111111111111')
     from private.push_outbox where user_id = '22222222-2222-2222-2222-222222222222' and kind = 'live_share'),
  true,
  'в уведомлении — кто показывает'
);
select is(pg_temp.pushes('33333333-3333-3333-3333-333333333333', 'live_share'), 0, 'выключил в настройках — нет');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select public.start_live_share(array['22222222-2222-2222-2222-222222222222']::uuid[]);
select pg_temp.act_as_admin();
select is(pg_temp.pushes('22222222-2222-2222-2222-222222222222', 'live_share'), 1, 'включил снова через минуту — второго нет');

-- Общие сборы ------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
create temp table packing as
  select public.share_packing('Капшагай', null, '[{"title": "Палатка"}]',
    array['22222222-2222-2222-2222-222222222222']::uuid[]) as id;
select pg_temp.act_as_admin();
select is(pg_temp.pushes('22222222-2222-2222-2222-222222222222', 'packing_invite'), 1, 'приглашённому — уведомление');
select is(
  (select payload ->> 'packing_id' from private.push_outbox
    where user_id = '22222222-2222-2222-2222-222222222222' and kind = 'packing_invite'),
  (select id::text from packing),
  'со ссылкой на сборы'
);
select is(pg_temp.pushes('11111111-1111-1111-1111-111111111111', 'packing_invite'), 0, 'автору — нет');

-- Смотритель -------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Залив', 'SRID=4326;POINT(77.00 43.90)', 'public');
select pg_temp.act_as_admin();
update public.places set status = 'published';

select pg_temp.checkins('44444444-4444-4444-4444-444444444444', 'aaaaaaaa-0000-0000-0000-000000000001', 2, 10);
select pg_temp.act_as_admin();
select is(pg_temp.pushes('44444444-4444-4444-4444-444444444444', 'steward'), 0, 'два отчёта — ещё не смотритель');

select pg_temp.checkins('44444444-4444-4444-4444-444444444444', 'aaaaaaaa-0000-0000-0000-000000000001', 2, 20);
select pg_temp.act_as_admin();
select is(pg_temp.pushes('44444444-4444-4444-4444-444444444444', 'steward'), 1, 'третий — смотритель, четвёртый — без повтора');
select is(
  (select payload ->> 'place_id' from private.push_outbox
    where user_id = '44444444-4444-4444-4444-444444444444' and kind = 'steward'),
  'aaaaaaaa-0000-0000-0000-000000000001',
  'со ссылкой на место'
);

-- E обходит D (5 против 4) — уведомление E; D догоняет обратно — снова D.
select pg_temp.checkins('55555555-5555-5555-5555-555555555555', 'aaaaaaaa-0000-0000-0000-000000000001', 5, 30);
select pg_temp.act_as_admin();
select is(pg_temp.pushes('55555555-5555-5555-5555-555555555555', 'steward'), 1, 'обошёл — новый смотритель узнаёт');

select pg_temp.checkins('44444444-4444-4444-4444-444444444444', 'aaaaaaaa-0000-0000-0000-000000000001', 2, 40);
select pg_temp.act_as_admin();
select is(pg_temp.pushes('44444444-4444-4444-4444-444444444444', 'steward'), 2, 'вернул статус — снова уведомление');

select * from finish();
rollback;
