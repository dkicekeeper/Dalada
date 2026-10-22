-- Аккаунт для проверки Apple: удалённое демо-содержимое возвращает повторный вызов
-- create_review_account; то, что проверяющие завели и удалили сами, остаётся удалённым; дублей нет.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(7);

create temp table review_id as
select private.create_review_account('review@example.com', 'first-pass-1') as id;

-- Свое место проверяющего — его удаление не откатываем.
insert into public.places (owner_id, type, name, geom, visibility, approximate, status)
select id, 'fishing_spot', 'Проверка удаления', extensions.st_setsrid(extensions.st_makepoint(77.1, 43.9), 4326),
       'private', false, 'published'
  from review_id;

-- Проверяющие удалили всё.
update public.catches set deleted_at = now() where owner_id = (select id from review_id);
update public.checkins set deleted_at = now() where owner_id = (select id from review_id);
update public.places set deleted_at = now() where owner_id = (select id from review_id);
update public.trips set deleted_at = now() where owner_id = (select id from review_id);

select is(
  (select count(*)::integer from public.places where owner_id = (select id from review_id) and deleted_at is null),
  0,
  'до повторного вызова своих мест нет'
);

select lives_ok(
  $$ select private.create_review_account('review@example.com', 'second-pass-2') $$,
  'повторный вызов проходит'
);

select is(
  (select array_agg(name order by name) from public.places
    where owner_id = (select id from review_id) and deleted_at is null),
  array['Секретная коса', 'Стоянка на Или'],
  'оба демо-места вернулись'
);
select ok(
  (select deleted_at is not null from public.places
    where owner_id = (select id from review_id) and name = 'Проверка удаления'),
  'место, которое проверяющий завёл и удалил сам, осталось удалённым'
);
select ok(
  (select count(*) from public.checkins where owner_id = (select id from review_id) and deleted_at is null) >= 1
  and (select count(*) from public.catches where owner_id = (select id from review_id) and deleted_at is null) >= 1,
  'отчёты и уловы демо-аккаунта вернулись'
);
select is(
  (select count(*)::integer from public.trips
    where owner_id = (select id from review_id) and deleted_at is null and title = 'Вечерняя рыбалка на косе'),
  1,
  'поездка вернулась'
);
select is(
  (select count(*)::integer from public.places where owner_id = (select id from review_id)),
  3,
  'содержимое не задвоилось'
);

select * from finish();
rollback;
