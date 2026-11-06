-- Подборка редакции «Подлёдная рыбалка» (миграция …_ice_fishing_collection.sql): есть, наверху
-- списка подборок и видна гостю во вкладке «Места».

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(4);

select is(
  (select title ->> 'ru' from public.place_collections where slug = 'ice_fishing'),
  'Подлёдная рыбалка',
  'подборка есть'
);

select is(
  (select count(*)::int
     from public.place_collection_items ci
     join public.place_collections c on c.id = ci.collection_id
     join public.places p on p.id = ci.place_id
    where c.slug = 'ice_fishing'
      and p.owner_id = private.editorial_id()
      and p.type = 'water_body'),
  12,
  'двенадцать водоёмов редакции'
);

select is(
  (select slug from public.place_collections where published order by position, slug limit 1),
  'ice_fishing',
  'первая среди подборок'
);

set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select ok(
  exists (
    select 1
      from jsonb_array_elements(public.places_discover() -> 'recommended') r
     where r ->> 'slug' = 'ice_fishing'
       and jsonb_array_length(r -> 'places') > 0
  ),
  'гость видит подборку во вкладке «Места»'
);

select * from finish();
rollback;
