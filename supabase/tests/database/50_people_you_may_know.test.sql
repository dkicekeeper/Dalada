-- «Возможно, вы знакомы»: друзья друзей (число общих) и авторы публичных подтверждённых отчётов в моих
-- местах; без друзей, заблокированных, запросов, людей без username и скрытых; чужие непубличные
-- отчёты не в счёт — и мои непубличные не делают меня подсказкой для других.
-- A — смотрит; B — друг A; C — друг B; D — публичный отчёт там, где был A; E — там же «только я»;
-- F — друг B, заблокирован A; G — друг B, A отправил запрос; H — друг B без username.

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

create function pg_temp.act_as_admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.checkin(uid uuid, vis public.visibility) returns void language plpgsql as $$
begin
  perform pg_temp.act_as(uid);
  insert into public.checkins (place_id, at, geom, visibility)
  values ('aaaaaaaa-0000-0000-0000-000000000001', now() - interval '1 hour', 'SRID=4326;POINT(77.00 43.90)', vis);
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'd@test.local'),
  ('55555555-5555-5555-5555-555555555555', 'e@test.local'),
  ('66666666-6666-6666-6666-666666666666', 'f@test.local'),
  ('77777777-7777-7777-7777-777777777777', 'g@test.local'),
  ('88888888-8888-8888-8888-888888888888', 'h@test.local');
update public.profiles set username = case id
  when '11111111-1111-1111-1111-111111111111' then 'aaa'
  when '22222222-2222-2222-2222-222222222222' then 'bbb'
  when '33333333-3333-3333-3333-333333333333' then 'ccc'
  when '44444444-4444-4444-4444-444444444444' then 'ddd'
  when '55555555-5555-5555-5555-555555555555' then 'eee'
  when '66666666-6666-6666-6666-666666666666' then 'fff'
  when '77777777-7777-7777-7777-777777777777' then 'ggg'
end;

insert into public.friendships (user_id, friend_id)
select x, y from (values
  ('11111111-1111-1111-1111-111111111111'::uuid, '22222222-2222-2222-2222-222222222222'::uuid),
  ('22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333'),
  ('22222222-2222-2222-2222-222222222222', '66666666-6666-6666-6666-666666666666'),
  ('22222222-2222-2222-2222-222222222222', '77777777-7777-7777-7777-777777777777'),
  ('22222222-2222-2222-2222-222222222222', '88888888-8888-8888-8888-888888888888')
) as v(a, b), lateral (values (a, b), (b, a)) as pair(x, y);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Залив', 'SRID=4326;POINT(77.00 43.90)', 'public');
select pg_temp.act_as_admin();
update public.places set status = 'published';

select pg_temp.checkin('11111111-1111-1111-1111-111111111111', 'private');
select pg_temp.checkin('44444444-4444-4444-4444-444444444444', 'public');
select pg_temp.checkin('55555555-5555-5555-5555-555555555555', 'private');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.blocks (blocked_id) values ('66666666-6666-6666-6666-666666666666');
select public.send_friend_request('77777777-7777-7777-7777-777777777777');

-- Подсказки -------------------------------------------------------------------------------------

select is(
  (select string_agg(username || ':' || mutual_friends || ':' || shared_places, ',')
     from public.people_you_may_know()),
  'ccc:1:0,ddd:0:1',
  'друг друга (1 общий) и автор публичного отчёта в моём месте; выше — общие друзья'
);
select ok(
  not exists (select 1 from public.people_you_may_know() where username in ('bbb', 'aaa')),
  'ни друзей, ни себя'
);
select ok(
  not exists (select 1 from public.people_you_may_know() where username = 'eee'),
  'отчёт «только я» — не повод'
);
select ok(
  not exists (select 1 from public.people_you_may_know() where username in ('fff', 'ggg')),
  'ни заблокированных, ни тех, кому уже отправлен запрос'
);
select ok(
  not exists (select 1 from public.people_you_may_know() where id = '88888888-8888-8888-8888-888888888888'),
  'без username — нет'
);

select public.dismiss_friend_suggestion('33333333-3333-3333-3333-333333333333');
select is(
  (select string_agg(username, ',') from public.people_you_may_know()),
  'ddd',
  'скрытый пропал'
);

-- Обратная сторона ------------------------------------------------------------------------------

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select ok(
  not exists (select 1 from public.people_you_may_know() where username = 'aaa'),
  'мой отчёт «только я» не делает меня подсказкой для D'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(
  (select mutual_friends from public.people_you_may_know() where username = 'aaa'),
  1,
  'C видит A через общего друга'
);

select pg_temp.act_as_admin();
set local role anon;
select throws_ok($$ select * from public.people_you_may_know() $$, '42501', null, 'гостю — нет');

select * from finish();
rollback;
