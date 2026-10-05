-- Смотритель и рекорды места: считаются только публичные подтверждённые отчёты за 60 дней (от трёх),
-- обойти, а не догнать; рекорды — самый тяжёлый улов вида с фото, без скрытого размера; закрытое
-- место и заблокированные — пусто.

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

-- n отчётов автора в месте с телефоном рядом (подтверждаются — моложе 72 часов): по одному в час,
-- начиная с hours_ago.
create function pg_temp.checkins(uid uuid, place uuid, n integer, hours_ago integer, vis public.visibility default 'public')
returns void language plpgsql as $$
begin
  perform pg_temp.act_as(uid);
  for i in 0 .. n - 1 loop
    insert into public.checkins (place_id, at, geom, visibility)
    values (place, now() - make_interval(hours => hours_ago + i), 'SRID=4326;POINT(77.00 43.90)', vis);
  end loop;
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'd@test.local');

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Залив', 'SRID=4326;POINT(77.00 43.90)', 'public'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'fishing_spot', 'Тихое', 'SRID=4326;POINT(77.00 43.90)', 'friends');
select pg_temp.act_as_admin();
update public.places set status = 'published';

-- A — 4 отчёта, B — 3; C — 5 без подтверждения и 5 «только я»: не считаются.
select pg_temp.checkins('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001', 4, 1);
select pg_temp.checkins('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001', 3, 1);
select pg_temp.checkins('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000001', 5, 1, 'private');
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
insert into public.checkins (place_id) select 'aaaaaaaa-0000-0000-0000-000000000001' from generate_series(1, 5);

-- Смотритель ------------------------------------------------------------------------------------

select pg_temp.act_as_anon();
select is(
  (select user_id || ':' || checkins from public.place_steward('aaaaaaaa-0000-0000-0000-000000000001')),
  '11111111-1111-1111-1111-111111111111:4',
  'смотритель — у кого больше публичных подтверждённых отчётов'
);

-- B догоняет до 4: равенство — смотритель остаётся (начал раньше).
select pg_temp.checkins('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001', 1, 0);
select pg_temp.act_as_anon();
select is(
  (select user_id from public.place_steward('aaaaaaaa-0000-0000-0000-000000000001')),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'догнать мало — нужно обойти'
);
select pg_temp.checkins('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001', 1, 0);
select pg_temp.act_as_anon();
select is(
  (select user_id from public.place_steward('aaaaaaaa-0000-0000-0000-000000000001')),
  '22222222-2222-2222-2222-222222222222'::uuid,
  'обошёл — новый смотритель'
);

-- Старше 60 дней не считаются (подтверждение сохраняем — в обход триггеров).
select pg_temp.act_as_admin();
set local session_replication_role = replica;
update public.checkins set at = now() - interval '70 days'
 where owner_id = '22222222-2222-2222-2222-222222222222' and at > now() - interval '30 minutes';
set local session_replication_role = origin;
select pg_temp.act_as_anon();
select is(
  (select user_id from public.place_steward('aaaaaaaa-0000-0000-0000-000000000001')),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'отчёты старше 60 дней не в счёт'
);

-- Не публичное место — пусто.
select pg_temp.checkins('44444444-4444-4444-4444-444444444444', 'aaaaaaaa-0000-0000-0000-000000000002', 3, 1, 'friends');
select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select is((select count(*)::integer from public.place_steward('aaaaaaaa-0000-0000-0000-000000000002')), 0, 'не публичное место — пусто');

-- Заблокированному — нет.
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
insert into public.blocks (blocked_id) values ('11111111-1111-1111-1111-111111111111');
select is((select count(*)::integer from public.place_steward('aaaaaaaa-0000-0000-0000-000000000001')), 0, 'заблокировавшему — не показываем');

-- Рекорды ---------------------------------------------------------------------------------------

-- A: щука 2 кг с фото; B: щука 3 кг, размер скрыт; C: щука 2,5 кг без фото; B: окунь 300 г с фото.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.catches (id, checkin_id, species_id, weight_g, visibility)
select 'dddddddd-0000-0000-0000-000000000001', id, 'pike', 2000, 'public'
  from public.checkins where owner_id = '11111111-1111-1111-1111-111111111111' order by at desc limit 1;
insert into public.media (id, checkin_id, catch_id)
select 'eeeeeeee-0000-0000-0000-000000000001', checkin_id, id from public.catches where id = 'dddddddd-0000-0000-0000-000000000001';

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.catches (id, checkin_id, species_id, weight_g, visibility, hide_size)
select 'dddddddd-0000-0000-0000-000000000002', id, 'pike', 3000, 'public', true
  from public.checkins where owner_id = '22222222-2222-2222-2222-222222222222'
   and place_id = 'aaaaaaaa-0000-0000-0000-000000000001' order by at desc limit 1;
insert into public.media (checkin_id, catch_id)
select checkin_id, id from public.catches where id = 'dddddddd-0000-0000-0000-000000000002';
insert into public.catches (id, checkin_id, species_id, weight_g, visibility)
select 'dddddddd-0000-0000-0000-000000000003', id, 'perch', 300, 'public'
  from public.checkins where owner_id = '22222222-2222-2222-2222-222222222222'
   and place_id = 'aaaaaaaa-0000-0000-0000-000000000001' order by at desc limit 1;
insert into public.media (checkin_id, catch_id)
select checkin_id, id from public.catches where id = 'dddddddd-0000-0000-0000-000000000003';

select pg_temp.act_as_admin();
insert into public.catches (id, owner_id, checkin_id, species_id, weight_g, visibility)
select 'dddddddd-0000-0000-0000-000000000004', owner_id, id, 'pike', 2500, 'public'
  from public.checkins where owner_id = '33333333-3333-3333-3333-333333333333' and verified limit 1;

select pg_temp.act_as_anon();
select is(
  (select count(*)::integer from public.place_records('aaaaaaaa-0000-0000-0000-000000000001')),
  2,
  'по рекорду на вид'
);
select is(
  (select catch_id from public.place_records('aaaaaaaa-0000-0000-0000-000000000001') where species_id = 'pike'),
  'dddddddd-0000-0000-0000-000000000001'::uuid,
  'рекорд щуки — с фото и открытым размером (скрытый и без фото не в счёт)'
);
select is(
  (select photo_thumb_path from public.place_records('aaaaaaaa-0000-0000-0000-000000000001') where species_id = 'pike'),
  '11111111-1111-1111-1111-111111111111/eeeeeeee-0000-0000-0000-000000000001_thumb.jpg',
  'с превью фото'
);
select ok(
  rls.can_read_media_object('11111111-1111-1111-1111-111111111111/eeeeeeee-0000-0000-0000-000000000001_thumb.jpg'),
  'и гость может его открыть'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select ok(
  not exists (select 1 from public.place_records('aaaaaaaa-0000-0000-0000-000000000001') where author_id = '11111111-1111-1111-1111-111111111111'),
  'заблокированного автора в рекордах нет'
);
select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select is((select count(*)::integer from public.place_records('aaaaaaaa-0000-0000-0000-000000000002')), 0, 'не публичное место — пусто');

select * from finish();
rollback;
