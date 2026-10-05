-- M14: фото мест редакции. Видны тем, кто видит место; таблица клиенту напрямую закрыта; в списках
-- мест обложка — первое фото редакции.
-- E — место редакции (публичное), A — автор секретного места, B — другой человек.

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

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local');

insert into public.places (id, owner_id, type, name, geom, visibility, status) values
  ('eeeeeeee-0000-0000-0000-000000000001', private.editorial_id(), 'water_body', 'Тестовое озеро редакции',
   'SRID=4326;POINT(77.10 43.90)', 'public', 'published'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'fishing_spot', 'Секрет A',
   'SRID=4326;POINT(77.20 43.90)', 'private', 'published');

insert into public.place_editorial_photos (id, place_id, position, commons_file, author, license, license_url, width, height) values
  ('fffffff0-0000-0000-0000-000000000002', 'eeeeeeee-0000-0000-0000-000000000001', 2, 'File:Lake 2.jpg',
   'Автор 2', 'CC BY-SA 4.0', 'https://creativecommons.org/licenses/by-sa/4.0', 1600, 1200),
  ('fffffff0-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000001', 1, 'File:Lake one.JPG',
   'Автор 1', 'CC0', null, 2000, 1500),
  ('fffffff0-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', 1, 'File:Secret.jpg',
   'Автор 3', 'CC BY 4.0', null, 1200, 900);

select throws_ok(
  $$ insert into public.place_editorial_photos (id, place_id, commons_file, author, license, width, height)
     values (gen_random_uuid(), 'eeeeeeee-0000-0000-0000-000000000001', 'File:Doc.pdf', 'X', 'CC0', 1, 1) $$,
  '23514',
  null,
  'только изображения JPEG и PNG'
);

-- Гость --------------------------------------------------------------------------------------------

set local role anon;
select is(
  (select string_agg(path || ' ' || author || ' ' || source_url, ' | ')
     from public.place_editorial_photos('eeeeeeee-0000-0000-0000-000000000001')),
  'photos/places/fffffff0-0000-0000-0000-000000000001.jpg Автор 1 https://commons.wikimedia.org/wiki/File:Lake_one.JPG | '
  || 'photos/places/fffffff0-0000-0000-0000-000000000002.jpg Автор 2 https://commons.wikimedia.org/wiki/File:Lake_2.jpg',
  'гостю — фото публичного места по порядку, со ссылкой на Commons'
);
select throws_ok(
  $$ select * from public.place_editorial_photos $$,
  '42501',
  null,
  'таблица напрямую закрыта'
);
reset role;

-- Видимость места ----------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select count(*)::integer from public.place_editorial_photos('aaaaaaaa-0000-0000-0000-000000000001')),
  0,
  'фото чужого секретного места не видны'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select count(*)::integer from public.place_editorial_photos('aaaaaaaa-0000-0000-0000-000000000001')),
  1,
  'свои — видны'
);

select pg_temp.act_as_admin();
update public.places set deleted_at = now() where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select count(*)::integer from public.place_editorial_photos('aaaaaaaa-0000-0000-0000-000000000001')),
  0,
  'удалённое место — без фото'
);

-- Обложка в списках --------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select s.photo_path from public.places_search('Тестовое озеро редакции', null, null, null, null, 5) s
    where s.id = 'eeeeeeee-0000-0000-0000-000000000001'),
  'photos/places/fffffff0-0000-0000-0000-000000000001_thumb.jpg',
  'обложка в поиске — первое фото редакции'
);

select pg_temp.act_as_admin();
delete from public.place_editorial_photos where place_id = 'eeeeeeee-0000-0000-0000-000000000001';
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select s.photo_path from public.places_search('Тестовое озеро редакции', null, null, null, null, 5) s
    where s.id = 'eeeeeeee-0000-0000-0000-000000000001'),
  null,
  'без фото редакции и посетителей — без обложки'
);

-- Каскад: место удалено из базы — фото тоже.
select pg_temp.act_as_admin();
insert into public.place_editorial_photos (id, place_id, commons_file, author, license, width, height)
values ('fffffff0-0000-0000-0000-000000000009', 'eeeeeeee-0000-0000-0000-000000000001', 'File:X.jpg', 'X', 'CC0', 1, 1);
delete from public.places where id = 'eeeeeeee-0000-0000-0000-000000000001';
select is(
  (select count(*)::integer from public.place_editorial_photos where id = 'fffffff0-0000-0000-0000-000000000009'),
  0,
  'фото удаляются вместе с местом'
);

select * from finish();
rollback;
