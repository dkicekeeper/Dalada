-- Комментарии в непубличных местах: «только я» — дневник владельца; «друзья» — владелец и друзья;
-- публичным местам — нет (там отзывы и обсуждения); владельцу — уведомление, он может удалить чужой;
-- реакций к месту нет.
-- A — владелец; B — друг; C — не друг.

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
  ('22222222-2222-2222-2222-222222222222', 'b@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.local');
insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');
insert into public.devices (user_id, token, environment) values
  ('11111111-1111-1111-1111-111111111111', repeat('a1', 32), 'production');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Моё', 'SRID=4326;POINT(77.00 43.90)', 'private'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'fishing_spot', 'Наше', 'SRID=4326;POINT(77.10 43.90)', 'friends'),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'fishing_spot', 'Общее', 'SRID=4326;POINT(77.20 43.90)', 'public');
select pg_temp.act_as_admin();
update public.places set status = 'published';

-- Дневник «только я» ----------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ insert into public.comments (target_kind, target_id, body) values ('place', 'aaaaaaaa-0000-0000-0000-000000000001', 'Клёв с 6 утра') $$,
  'владелец пишет в дневник своего места'
);
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*)::integer from public.post_comments('place', 'aaaaaaaa-0000-0000-0000-000000000001')), 0, 'друг дневник не видит');
select throws_ok(
  $$ insert into public.comments (target_kind, target_id, body) values ('place', 'aaaaaaaa-0000-0000-0000-000000000001', 'привет') $$,
  'P0002', null,
  'и не пишет'
);

-- «Друзья» -------------------------------------------------------------------------------------

select lives_ok(
  $$ insert into public.comments (id, target_kind, target_id, body) values
       ('cccccccc-0000-0000-0000-000000000001', 'place', 'aaaaaaaa-0000-0000-0000-000000000002', 'Дорогу размыло') $$,
  'друг пишет в месте «друзья»'
);
select pg_temp.act_as_admin();
select is(
  (select count(*)::integer from private.push_outbox
    where user_id = '11111111-1111-1111-1111-111111111111' and kind = 'comment' and payload ->> 'target_kind' = 'place'),
  1,
  'владельцу — уведомление'
);
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*)::integer from public.post_comments('place', 'aaaaaaaa-0000-0000-0000-000000000002')), 0, 'не другу — не видно');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok($$ select public.delete_comment('cccccccc-0000-0000-0000-000000000001') $$, 'владелец места удаляет чужой комментарий');

-- Публичное место и реакции ----------------------------------------------------------------------

select throws_ok(
  $$ insert into public.comments (target_kind, target_id, body) values ('place', 'aaaaaaaa-0000-0000-0000-000000000003', 'тут') $$,
  'P0002', null,
  'у публичного места — отзывы и обсуждения, не комментарии'
);
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select throws_ok(
  $$ select public.set_reaction('place', 'aaaaaaaa-0000-0000-0000-000000000002', true) $$,
  '23514', null,
  'реакций к месту нет'
);
select is((select count(*)::integer from public.comment_summary(array['place']::public.reaction_target[], array['aaaaaaaa-0000-0000-0000-000000000002']::uuid[])), 1, 'число комментариев видно другу');

select * from finish();
rollback;
