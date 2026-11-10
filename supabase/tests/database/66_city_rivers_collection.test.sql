-- Подборка редакции «Реки в городах» (миграция …_city_rivers_collection.sql): есть, в ней двенадцать
-- участков рек редакции, ice_fishing по-прежнему первая, гость видит подборку во вкладке «Места».

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(4);

select is(
  (select title ->> 'ru' from public.place_collections where slug = 'city_rivers'),
  'Реки в городах',
  'подборка есть'
);

select is(
  (select count(*)::int
     from public.place_collection_items ci
     join public.place_collections c on c.id = ci.collection_id
     join public.places p on p.id = ci.place_id
    where c.slug = 'city_rivers'
      and p.owner_id = private.editorial_id()
      and p.type = 'water_body'),
  12,
  'двенадцать участков рек редакции'
);

select is(
  (select array_agg(slug order by position, slug) from (select slug, position from public.place_collections where published order by position, slug limit 3) s),
  array['ice_fishing', 'waters_near_almaty', 'city_rivers'],
  'после подлёдной и водоёмов у Алматы'
);

set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select ok(
  exists (
    select 1
      from jsonb_array_elements(public.places_discover() -> 'recommended') r
     where r ->> 'slug' = 'city_rivers'
       and jsonb_array_length(r -> 'places') > 0
  ),
  'гость видит подборку во вкладке «Места»'
);

select * from finish();
rollback;
