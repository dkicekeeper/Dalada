-- Уведомление о реакции: автору поездки, отчёта, отзыва и ответа в обсуждении — что за запись и
-- куда вести; одно в сутки от одного человека об одной записи; не при выключенной настройке.
-- A — автор всего, B и C ставят реакции.

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

-- Уведомления A о реакциях на запись.
create function pg_temp.pushes(p_target uuid) returns jsonb language sql as $$
  select coalesce(jsonb_agg(o.payload - 'actor_id' - 'actor' order by o.id), '[]'::jsonb)
    from private.push_outbox o
   where o.user_id = '11111111-1111-1111-1111-111111111111' and o.kind = 'reaction'
     and o.payload ->> 'target_id' = p_target::text
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.local');
update public.profiles set username = 'bob' where id = '22222222-2222-2222-2222-222222222222';
insert into public.devices (token, user_id, environment)
values (repeat('a1', 32), '11111111-1111-1111-1111-111111111111', 'production');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Залив', 'SRID=4326;POINT(77.00 43.90)', 'public');
select pg_temp.act_as_admin();
update public.places set status = 'published' where id = 'aaaaaaaa-0000-0000-0000-000000000001';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.trips (id, title, started_at, ended_at, visibility)
values ('bbbbbbbb-0000-0000-0000-000000000001', 'Капшагай', now() - interval '2 hours', now(), 'public');
insert into public.checkins (id, place_id, visibility)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'public');
create temp table review_id as
  select public.save_review('aaaaaaaa-0000-0000-0000-000000000001', 5, 'Хорошо') as id;
insert into public.threads (id, place_id, title, body)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Дорога', 'Как проехать?');
insert into public.thread_posts (id, thread_id, body)
values ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001', 'Через мост');

-- B ставит реакции ------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select public.set_reaction('trip', 'bbbbbbbb-0000-0000-0000-000000000001', true);
select public.set_reaction('trip', 'bbbbbbbb-0000-0000-0000-000000000001', false);
select public.set_reaction('trip', 'bbbbbbbb-0000-0000-0000-000000000001', true);
select public.set_reaction('checkin', 'cccccccc-0000-0000-0000-000000000001', true);
select public.set_reaction('review', (select id from review_id), true);
select public.set_reaction('post', 'eeeeeeee-0000-0000-0000-000000000001', true);

select pg_temp.act_as_admin();
select is(
  pg_temp.pushes('bbbbbbbb-0000-0000-0000-000000000001'),
  '[{"target_kind": "trip", "target_id": "bbbbbbbb-0000-0000-0000-000000000001", "title": "Капшагай", "username": "bob"}]'::jsonb,
  'респект поездке — автору, с названием; снял и поставил снова — одно уведомление'
);
select is(
  pg_temp.pushes('cccccccc-0000-0000-0000-000000000001') -> 0 ->> 'place_id',
  'aaaaaaaa-0000-0000-0000-000000000001',
  'респект отчёту — с местом'
);
select is(
  pg_temp.pushes('cccccccc-0000-0000-0000-000000000001') -> 0 ->> 'title',
  'Залив',
  'и названием места'
);
select is(
  pg_temp.pushes((select id from review_id)) -> 0 ->> 'target_kind',
  'review',
  '«полезно» отзыву'
);
select is(
  pg_temp.pushes('eeeeeeee-0000-0000-0000-000000000001') -> 0 ->> 'thread_id',
  'dddddddd-0000-0000-0000-000000000001',
  'респект ответу — со ссылкой на обсуждение'
);
select is(
  (select count(*)::integer from private.push_outbox where user_id = '22222222-2222-2222-2222-222222222222'),
  0,
  'тому, кто ставит, уведомлений нет'
);

-- C — другой человек: у него своё уведомление ---------------------------------------------------

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select public.set_reaction('trip', 'bbbbbbbb-0000-0000-0000-000000000001', true);
select pg_temp.act_as_admin();
select is(
  jsonb_array_length(pg_temp.pushes('bbbbbbbb-0000-0000-0000-000000000001')),
  2,
  'другой человек — своё уведомление'
);

-- A выключил уведомления о реакциях.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
update public.profiles set notify_reactions = false where id = '11111111-1111-1111-1111-111111111111';
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select public.set_reaction('checkin', 'cccccccc-0000-0000-0000-000000000001', true);
select pg_temp.act_as_admin();
select is(
  jsonb_array_length(pg_temp.pushes('cccccccc-0000-0000-0000-000000000001')),
  1,
  'настройка выключена — уведомления нет'
);

select is(
  has_function_privilege('authenticated', 'private.reactions_push()', 'execute'),
  false,
  'триггерную функцию клиент не вызывает'
);

select * from finish();
rollback;
