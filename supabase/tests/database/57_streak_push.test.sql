-- «Серия под угрозой»: серия от двух недель, на этой неделе выезда нет, неделя не заморожена — одно
-- уведомление в неделю; выезд на этой неделе — нет; без телефона — нет. my_streak — как раньше.
-- A — серия 2 недели без выезда сейчас; B — выезжал и на этой неделе; C — без телефона.

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

create function pg_temp.trip(uid uuid, days_ago integer) returns void language plpgsql as $$
begin
  perform pg_temp.act_as(uid);
  insert into public.trips (title, started_at, ended_at, visibility)
  values ('Выезд', now() - make_interval(days => days_ago), now() - make_interval(days => days_ago) + interval '1 hour', 'private');
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.local');
insert into public.devices (user_id, token, environment) values
  ('11111111-1111-1111-1111-111111111111', repeat('a1', 32), 'production'),
  ('22222222-2222-2222-2222-222222222222', repeat('b2', 32), 'production');

select pg_temp.trip('11111111-1111-1111-1111-111111111111', 7);
select pg_temp.trip('11111111-1111-1111-1111-111111111111', 14);
select pg_temp.trip('22222222-2222-2222-2222-222222222222', 7);
select pg_temp.trip('22222222-2222-2222-2222-222222222222', 14);
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select pg_temp.trip('22222222-2222-2222-2222-222222222222', 0);
select pg_temp.trip('33333333-3333-3333-3333-333333333333', 7);
select pg_temp.trip('33333333-3333-3333-3333-333333333333', 14);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is((select current_weeks || ':' || this_week_done from public.my_streak()), '2:false', 'my_streak как раньше');

select pg_temp.act_as_admin();
select private.streak_reminders();
-- Ждём уведомление, только если эта неделя не заморожена (зима, запрет) — иначе его быть не должно.
select is(
  (select count(*)::integer from private.push_outbox where user_id = '11111111-1111-1111-1111-111111111111' and kind = 'streak'),
  (select case when freeze_reason is null then 1 else 0 end from private.user_streak('11111111-1111-1111-1111-111111111111')),
  'серия под угрозой — уведомление (если неделя не заморожена)'
);
select is(
  (select count(*)::integer from private.push_outbox where user_id = '22222222-2222-2222-2222-222222222222' and kind = 'streak'),
  0,
  'выезжал на этой неделе — нет'
);
select is(
  (select count(*)::integer from private.push_outbox where user_id = '33333333-3333-3333-3333-333333333333' and kind = 'streak'),
  0,
  'без телефона — нет'
);
select private.streak_reminders();
select ok(
  (select count(*) from private.push_outbox where user_id = '11111111-1111-1111-1111-111111111111' and kind = 'streak') <= 1,
  'не чаще раза в неделю'
);

select * from finish();
rollback;
