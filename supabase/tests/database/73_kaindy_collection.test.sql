-- Озеро Каинды (миграции …_editorial_places.sql волны 4д и …_kaindy_in_almaty_collection.sql): место
-- редакции есть, с описанием, и стоит в подборке «Водоёмы рядом с Алматы» последним.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(3);

select ok(
  exists (
    select 1 from public.places
     where id = 'f5d3fb79-ac06-4a62-a39f-484da2360283'
       and owner_id = private.editorial_id()
       and name = 'Каинды'
       and description like '%Кеминского землетрясения%'
       and deleted_at is null
  ),
  'место редакции «Каинды» с описанием'
);

select is(
  (select ci.position
     from public.place_collection_items ci
     join public.place_collections c on c.id = ci.collection_id
    where c.slug = 'waters_near_almaty'
      and ci.place_id = 'f5d3fb79-ac06-4a62-a39f-484da2360283'),
  (select max(ci.position)
     from public.place_collection_items ci
     join public.place_collections c on c.id = ci.collection_id
    where c.slug = 'waters_near_almaty'),
  'Каинды — последним в «Водоёмах рядом с Алматы»'
);

select ok(
  exists (
    select 1
      from public.place_collection_items ci
      join public.place_collections c on c.id = ci.collection_id
      join public.places p on p.id = ci.place_id
     where c.slug = 'waters_near_almaty'
       and p.name = 'Кольсай №1'
  ),
  'Кольсай №1 по-прежнему в подборке'
);

select * from finish();
rollback;
