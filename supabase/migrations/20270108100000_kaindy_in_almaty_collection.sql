-- Озеро Каинды (затопленный еловый лес, национальный парк «Көлсай көлдері») появилось на карте в волне 4д
-- (docs/05-release/content.md). В подборку «Водоёмы рядом с Алматы» оно не попало: подборку собрали один
-- раз по кругу 120 км от Алматы, а Каинды — в ~130 км по прямой, в 8 км от Кольсайских озёр, которые в ней
-- есть. Добавляем в конец подборки; состав дальше правит редакция в Studio.

insert into public.place_collection_items (collection_id, place_id, position)
select c.id, p.id,
       coalesce((select max(i.position) from public.place_collection_items i where i.collection_id = c.id), 0) + 1
  from public.place_collections c
  join public.places p
    on p.id = 'f5d3fb79-ac06-4a62-a39f-484da2360283'
   and p.owner_id = private.editorial_id()
   and p.deleted_at is null
   and p.status = 'published'
   and p.visibility = 'public'
 where c.slug = 'waters_near_almaty'
on conflict do nothing;
