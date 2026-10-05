-- Метрики продукта: North Star по неделям, когорты (воронка, W1 / W4), здоровье контента, поездки
-- за месяц. Служебные аккаунты и удалённое не считаются; клиенту функции недоступны.
--
-- Время в тесте — от понедельника текущей недели по Алматы (W): A и B зарегистрировались на неделе
-- W-42, D и E — сейчас, C — аккаунт для проверки Apple (почта), его не считаем. Даты созданий
-- выставляем при выключенных триггерах (session_replication_role = replica): иначе created_at = now().

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(19);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

-- Момент на неделе: W + p_days дней, p_hours часов по Алматы.
create function pg_temp.at(p_days integer, p_hours integer default 10) returns timestamptz
language sql stable as $$
  select ((private.metrics_week(now()) + p_days)::timestamp + make_interval(hours => p_hours)) at time zone 'Asia/Almaty'
$$;

create function pg_temp.w(p_days integer) returns date language sql stable as $$
  select private.metrics_week(now()) + p_days
$$;

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a@test.local'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'b@test.local'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'd@test.local'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'e@test.local');
insert into auth.users (id, email, raw_app_meta_data) values
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'review@test.local', '{"provider": "email", "providers": ["email"]}');

select pg_temp.act_as('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
insert into public.places (id, type, name, geom, visibility) values
  ('11111111-0000-0000-0000-000000000001', 'fishing_spot', 'Открытое 1', 'SRID=4326;POINT(77.10 43.90)', 'public'),
  ('11111111-0000-0000-0000-000000000002', 'fishing_spot', 'Открытое 2', 'SRID=4326;POINT(77.20 43.90)', 'public'),
  ('11111111-0000-0000-0000-000000000003', 'fishing_spot', 'Своё', 'SRID=4326;POINT(77.30 43.90)', 'private');
reset role;

set local session_replication_role = replica;

-- Новые публичные места ждут модерации; эти два — уже опубликованы.
update public.places set status = 'published'
 where id in ('11111111-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000002');

update public.profiles set created_at = pg_temp.at(-42) where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
update public.profiles set created_at = pg_temp.at(-41) where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
update public.profiles set created_at = pg_temp.at(-42) where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

-- A: чекин на первой неделе, поездка через неделю (W1), улов через четыре (W4); друг B.
insert into public.checkins (owner_id, place_id, at, visibility, created_at) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-0000-0000-0000-000000000001', pg_temp.at(-41), 'friends', pg_temp.at(-41));
insert into public.trips (owner_id, title, started_at, ended_at, created_at) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Через неделю', pg_temp.at(-35), pg_temp.at(-35, 14), pg_temp.at(-35, 15));
insert into public.catches (owner_id, species_id, created_at) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'pike', pg_temp.at(-14));
insert into public.friendships (user_id, friend_id, created_at) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', pg_temp.at(-40)),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', pg_temp.at(-40));

-- B: удалённый чекин через неделю не в счёт; отзыв на третьей неделе — ни W1, ни W4.
insert into public.checkins (owner_id, place_id, at, created_at, deleted_at) values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-0000-0000-0000-000000000001', pg_temp.at(-35), pg_temp.at(-35), pg_temp.at(-34));
insert into public.reviews (owner_id, place_id, rating, created_at) values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-0000-0000-0000-000000000001', 5, pg_temp.at(-28));

-- D: четыре чекина за эту неделю (свежий публичный, свежий для друзей, в приватном месте, старый
-- по времени) и две поездки, плюс удалённая.
insert into public.checkins (owner_id, place_id, at, visibility) values
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '11111111-0000-0000-0000-000000000001', now() - interval '1 day', 'public'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '11111111-0000-0000-0000-000000000002', now() - interval '2 days', 'friends'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '11111111-0000-0000-0000-000000000003', now() - interval '1 day', 'public'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '11111111-0000-0000-0000-000000000002', now() - interval '9 days', 'public');
insert into public.trips (owner_id, title, started_at, ended_at, deleted_at) values
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'Первая', now(), now(), null),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'Вторая', now(), now(), null),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'Удалённая', now(), now(), now());

-- E: одна поездка.
insert into public.trips (owner_id, title, started_at, ended_at) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'Одна', now(), now());

-- C (аккаунт для проверки): свежий публичный чекин и две поездки — нигде не считаются.
insert into public.checkins (owner_id, place_id, at, visibility) values
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '11111111-0000-0000-0000-000000000002', now() - interval '1 day', 'public');
insert into public.trips (owner_id, title, started_at, ended_at) values
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Демо 1', now(), now()),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Демо 2', now(), now());

set local session_replication_role = origin;

-- North Star по неделям ----------------------------------------------------------------------------

select is(
  (select array_agg(complete order by week_start desc) from private.metrics_weekly(8)),
  array[false, true, true, true, true, true, true, true],
  'восемь недель, текущая — первой и неполная'
);
select is(
  (select row(active_users, new_users, checkins, catches, trips, reviews, new_friends)::text
     from private.metrics_weekly(8) where week_start = pg_temp.w(0)),
  '(2,2,4,0,3,0,0)',
  'эта неделя: D и E; аккаунт для проверки, редакция и удалённая поездка не в счёт'
);
select is(
  (select row(active_users, new_users, checkins, new_friends)::text
     from private.metrics_weekly(8) where week_start = pg_temp.w(-42)),
  '(1,2,1,1)',
  'неделя W-42: регистрация A и B, чекин A, пара друзей — один раз'
);
select is(
  (select row(active_users, checkins, trips)::text
     from private.metrics_weekly(8) where week_start = pg_temp.w(-35)),
  '(1,0,1)',
  'неделя W-35: поездка A; удалённый чекин B не в счёт'
);
select is(
  (select row(active_users, reviews)::text from private.metrics_weekly(8) where week_start = pg_temp.w(-28)),
  '(1,1)',
  'неделя W-28: отзыв B'
);
select is(
  (select row(active_users, catches)::text from private.metrics_weekly(8) where week_start = pg_temp.w(-14)),
  '(1,1)',
  'неделя W-14: улов A'
);

-- Когорты ------------------------------------------------------------------------------------------

select is(
  (select array_agg(cohort_week order by cohort_week desc) from private.metrics_cohorts(8)),
  array[pg_temp.w(0), pg_temp.w(-42)],
  'две когорты: служебные аккаунты не в счёт'
);
select is(
  (select row(users, activated, with_friend, w1, w4)::text from private.metrics_cohorts(8) where cohort_week = pg_temp.w(-42)),
  '(2,1,2,1,1)',
  'когорта W-42: активен в первые 7 дней только A, друг у обоих, A вернулся на 1-й и 4-й неделе'
);
select is(
  (select array[w1_share, w4_share] from private.metrics_cohorts(8) where cohort_week = pg_temp.w(-42)),
  array[0.5, 0.5]::numeric[],
  'доли W1 и W4 — от размера когорты'
);
select is(
  (select row(users, activated, with_friend)::text from private.metrics_cohorts(8) where cohort_week = pg_temp.w(0)),
  '(2,2,0)',
  'когорта этой недели: D и E уже активны'
);
select ok(
  (select w1 is null and w4 is null and w1_share is null and w4_share is null
     from private.metrics_cohorts(8) where cohort_week = pg_temp.w(0)),
  'W1 и W4 пустые, пока неделя не закончилась'
);
select is(
  (select count(*)::integer from private.metrics_cohorts(1)),
  1,
  'p_weeks ограничивает когорты'
);

-- Здоровье контента --------------------------------------------------------------------------------

select is(
  (select row(fresh_public, fresh_any)::text from private.metrics_content_health()),
  '(1,2)',
  'свежий публичный отчёт — в одном месте, любой видимости — в двух; приватное место, старый чекин и аккаунт для проверки не в счёт'
);
select is(
  (select public_places - (select count(*)::integer from public.places p
                            where p.owner_id = private.editorial_id() and p.visibility = 'public'
                              and p.status = 'published' and p.deleted_at is null)
     from private.metrics_content_health()),
  2,
  'публичные места: редакционные и два открытых, без приватного'
);
select is(
  (select fresh_public_share = round(1::numeric / public_places, 3) from private.metrics_content_health()),
  true,
  'доля — от всех публичных мест'
);
select is(
  (select row(fresh_public, fresh_any)::text from private.metrics_content_health(now() + interval '30 days')),
  '(0,0)',
  'через месяц свежих отчётов нет'
);

-- Поездки за месяц ---------------------------------------------------------------------------------

select is(
  (select row(with_trip, with_two_trips)::text from private.metrics_monthly_trips(3)
    where month_start = date_trunc('month', now() at time zone 'Asia/Almaty')::date),
  '(2,1)',
  'этот месяц: поездки у D и E, две — у D; удалённая и демо не в счёт'
);
select ok(
  (select active_users >= 2 and share = round(1::numeric / active_users, 3) from private.metrics_monthly_trips(3)
    where month_start = date_trunc('month', now() at time zone 'Asia/Almaty')::date),
  'доля с двумя поездками — от активных за месяц'
);

-- Доступ -------------------------------------------------------------------------------------------

select is(
  (select count(*)::integer
     from unnest(array['anon', 'authenticated']) r,
          unnest(array[
            'private.metrics_activity()', 'private.metrics_weekly(integer)', 'private.metrics_cohorts(integer)',
            'private.metrics_content_health(timestamptz)', 'private.metrics_monthly_trips(integer)',
            'private.metrics_excluded_users()'
          ]) f
    where has_function_privilege(r, f, 'execute')),
  0,
  'клиенту метрики недоступны'
);

select * from finish();
rollback;
