-- Уровни: очки за публичный вклад, уровень и порог следующего; разбирать правки — с «Эксперта»: только
-- «правки полей» к чужим местам и не свои; принятая меняет место и даёт автору очки; автор правки не
-- видит, кто разобрал.
-- X — владелец мест; E — эксперт (10 мест = 200); K — знаток (3 места = 60); N — предлагает правки.

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

create function pg_temp.places(uid uuid, n integer) returns void language plpgsql as $$
begin
  perform pg_temp.act_as(uid);
  for i in 1 .. n loop
    insert into public.places (type, name, geom, visibility)
    values ('fishing_spot', 'Место ' || i, extensions.st_setsrid(extensions.st_makepoint(76 + i * 0.01, 43.5), 4326), 'public');
  end loop;
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'x@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'e@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'k@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'n@test.local');
update public.profiles set username = 'nnn' where id = '44444444-4444-4444-4444-444444444444';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Залив', 'SRID=4326;POINT(77.00 43.90)', 'public');
select pg_temp.places('22222222-2222-2222-2222-222222222222', 10);
select pg_temp.places('33333333-3333-3333-3333-333333333333', 3);
select pg_temp.act_as_admin();
update public.places set status = 'published';

-- Уровни -----------------------------------------------------------------------------------------

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(
  (select points || ':' || level || ':' || next_level_points || ':' || can_review from public.my_contribution()),
  '60:knower:200:false',
  'знаток: 3 места — 60 очков, до эксперта 200, правки не разбирает'
);
select throws_ok($$ select * from public.suggestion_review_queue() $$, '42501', null, 'очередь — не для знатока');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select level from public.my_contribution()), 'expert', '10 мест — эксперт');

-- Правки -----------------------------------------------------------------------------------------

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
create temp table edit as
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'edit', '{"name": "Залив Тихий"}', 'так называют местные') as id;
grant select on edit to authenticated;
create temp table closed as
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'closed', null, 'закрыли') as id;
grant select on closed to authenticated;

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select string_agg(author_username || ':' || (changes ->> 'name'), ',') from public.suggestion_review_queue()),
  'nnn:Залив Тихий',
  'в очереди — только «правка полей»'
);
select is((select review_queue from public.my_contribution()), 1, 'и счётчик очереди');
select throws_ok(
  $$ select public.review_suggestion((select id from closed), true) $$,
  'P0002', null,
  '«закрыто» эксперт не решает'
);
select lives_ok($$ select public.review_suggestion((select id from edit), true, 'верно') $$, 'принял');

select pg_temp.act_as_admin();
select is((select name from public.places where id = 'aaaaaaaa-0000-0000-0000-000000000001'), 'Залив Тихий', 'место поменялось');
select is((select status::text from public.place_suggestions where id = (select id from edit)), 'accepted', 'правка принята');
select is(
  (select reviewer_id from private.suggestion_reviews where suggestion_id = (select id from edit)),
  '22222222-2222-2222-2222-222222222222'::uuid,
  'редакция видит, кто разобрал'
);

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select is((select edits from public.my_contribution()), 1, 'автору правки — очки за принятую');
select throws_ok(
  $$ select reviewed_by from public.place_suggestions $$,
  '42703', null,
  'автор не видит, кто разобрал'
);

select * from finish();
rollback;
