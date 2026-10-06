-- Приглашение в поездку по ссылке: ссылку берёт только автор (одна, пока действует); по ссылке видно
-- название и автора (и гостю); принявший — участник, автору уходит запрос в друзья; заблокированным и по
-- истёкшей ссылке — нет.
-- A — автор; B — не друг; C — заблокирован A; D — опоздал.

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

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'd@test.local');
update public.profiles set username = 'author' where id = '11111111-1111-1111-1111-111111111111';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.trips (id, title, started_at, ended_at, visibility) values
  ('77777777-0000-0000-0000-000000000001', 'Капшагай', now() - interval '3 hours', now() - interval '1 hour', 'private');
insert into public.blocks (blocked_id) values ('33333333-3333-3333-3333-333333333333');

-- Ссылка ----------------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select throws_ok(
  $$ select public.trip_invite_link('77777777-0000-0000-0000-000000000001') $$,
  'P0002', null,
  'ссылку на чужую поездку не взять'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
create temp table link as select public.trip_invite_link('77777777-0000-0000-0000-000000000001') as token;
grant select on link to authenticated, anon;
select is((select length(token) from link), 32, 'ссылка — длинный случайный токен');
select is(public.trip_invite_link('77777777-0000-0000-0000-000000000001'), (select token from link), 'пока действует — та же');

-- По ссылке видно -------------------------------------------------------------------------------

select pg_temp.act_as_anon();
select is(
  (select title || ':' || owner_username from public.web_trip_invite((select token from link))),
  'Капшагай:author',
  'гость видит название и автора'
);
select is((select count(*)::integer from public.web_trip_invite('nope')), 0, 'по выдуманной — ничего');

-- Принять ---------------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  public.accept_trip_invite_link((select token from link)),
  '77777777-0000-0000-0000-000000000001'::uuid,
  'принял — поездка'
);
select is((select count(*)::integer from public.trip_view('77777777-0000-0000-0000-000000000001')), 1, 'и видит её, хоть она «только я»');
select is((select count(*)::integer from public.my_joined_trips()), 1, 'в «Моих поездках»');

select pg_temp.act_as_admin();
select is(
  (select status from public.friend_requests
    where from_user = '22222222-2222-2222-2222-222222222222' and to_user = '11111111-1111-1111-1111-111111111111'),
  'pending',
  'автору — запрос в друзья'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok(
  $$ select public.accept_trip_invite_link((select token from link)) $$,
  'P0002', null,
  'заблокированному — нет'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  public.accept_trip_invite_link((select token from link)),
  '77777777-0000-0000-0000-000000000001'::uuid,
  'автор открыл свою ссылку — просто поездка'
);

select pg_temp.act_as_admin();
update public.trip_invite_links set expires_at = now() - interval '1 minute';
select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok(
  $$ select public.accept_trip_invite_link((select token from link)) $$,
  'P0002', null,
  'истёкшая ссылка — нет'
);

select * from finish();
rollback;
