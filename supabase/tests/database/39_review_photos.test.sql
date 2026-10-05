-- Фото к отзывам: только к своему отзыву, до 5; видны тем, кто видит отзыв (и гостю), не видны
-- заблокированному и после удаления отзыва; фото — либо чекина, либо отзыва.
-- A — автор отзыва, B — читатель, E — заблокирован автором.

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
  ('55555555-5555-5555-5555-555555555555', 'e@test.local');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Залив', 'SRID=4326;POINT(77.00 43.90)', 'public');
insert into public.blocks (blocked_id) values ('55555555-5555-5555-5555-555555555555');
select pg_temp.act_as_admin();
update public.places set status = 'published' where id = 'aaaaaaaa-0000-0000-0000-000000000001';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.checkins (id, place_id, visibility)
values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'public');
create temp table review_id as
  select public.save_review('aaaaaaaa-0000-0000-0000-000000000001', 5, 'Хорошо') as id;
grant select on review_id to authenticated, anon;

-- Загрузка ----------------------------------------------------------------------------------------

select throws_ok(
  $$ insert into public.media (checkin_id, review_id)
     values ('cccccccc-0000-0000-0000-000000000001', (select id from review_id)) $$,
  '23514', null,
  'фото принадлежит либо чекину, либо отзыву'
);
select lives_ok(
  $$ insert into public.media (id, review_id, width, height)
     select ('eeeeeeee-0000-0000-0000-00000000000' || n)::uuid, (select id from review_id), 1600, 1200
       from generate_series(1, 5) n $$,
  'к своему отзыву — до 5 фото'
);
select throws_ok(
  $$ insert into public.media (review_id) values ((select id from review_id)) $$,
  '54000', null,
  'шестое — нет'
);
select is(
  (select place_id from public.media where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
  'место берётся из отзыва'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select throws_ok(
  $$ insert into public.media (review_id) values ((select id from review_id)) $$,
  'P0002', null,
  'к чужому отзыву — нельзя'
);

-- Видимость ---------------------------------------------------------------------------------------

select is(
  (select jsonb_array_length(media) from public.place_reviews('aaaaaaaa-0000-0000-0000-000000000001')),
  5,
  'читатель видит фото в отзыве'
);
select is(
  (select media -> 0 ->> 'thumb_path' from public.place_reviews('aaaaaaaa-0000-0000-0000-000000000001')),
  '11111111-1111-1111-1111-111111111111/eeeeeeee-0000-0000-0000-000000000001_thumb.jpg',
  'путь превью — рядом с файлом'
);
select ok(
  rls.can_read_media_object('11111111-1111-1111-1111-111111111111/eeeeeeee-0000-0000-0000-000000000001.jpg'),
  'и может открыть файл'
);

select pg_temp.act_as_anon();
select ok(
  rls.can_read_media_object('11111111-1111-1111-1111-111111111111/eeeeeeee-0000-0000-0000-000000000001_thumb.jpg'),
  'гость — тоже: отзывы публичных мест видны всем'
);

select pg_temp.act_as('55555555-5555-5555-5555-555555555555');
select ok(
  not rls.can_read_media_object('11111111-1111-1111-1111-111111111111/eeeeeeee-0000-0000-0000-000000000001.jpg'),
  'заблокированному — нет'
);

-- Отзыв удалён — фото не видно.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select public.delete_review((select id from review_id));
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select ok(
  not rls.can_read_media_object('11111111-1111-1111-1111-111111111111/eeeeeeee-0000-0000-0000-000000000001.jpg'),
  'после удаления отзыва фото не видно'
);
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select ok(
  rls.can_read_media_object('11111111-1111-1111-1111-111111111111/eeeeeeee-0000-0000-0000-000000000001.jpg'),
  'автору свои файлы видны всегда'
);

select * from finish();
rollback;
