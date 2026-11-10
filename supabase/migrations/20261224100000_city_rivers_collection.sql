-- Подборка редакции «Реки в городах» для вкладки «Места»: участки рек в черте областных центров, где
-- рыбачит больше всего горожан (docs/05-release/content.md, волна 4). Описания и рыба — по статьям о
-- реках; сроки запретов карточка показывает сама («Правила здесь»), в описании — только отсылка.
--
-- Места по расстоянию от человека, как у других подборок. Состав правит редакция в Studio.

insert into public.place_collections (slug, title, position) values
  ('city_rivers',
   '{"ru": "Реки в городах", "kk": "Қаладағы өзендер", "en": "Rivers in cities"}',
   15)
on conflict (slug) do nothing;

insert into public.place_collection_items (collection_id, place_id, position)
select c.id, p.id, x.position
  from public.place_collections c
  join (values
    -- Восток
    ('f7c28a67-d096-4c65-b64b-40a02288ef74'::uuid, 1),   -- Иртыш в Усть-Каменогорске
    ('03208900-900f-4a55-979a-11b6565e5283'::uuid, 2),   -- Ульба в Усть-Каменогорске
    ('d1e73c32-6a79-4e20-a10b-4ca8d9ffe4a6'::uuid, 3),   -- Иртыш в Семее
    ('ed822946-5ea8-4a91-98bd-79c4ab12f4b2'::uuid, 4),   -- Иртыш в Павлодаре
    -- Север и Астана
    ('764ff2de-47db-4e40-8510-7aa93ef95fc9'::uuid, 5),   -- Есиль в Астане
    ('812f4f79-5463-44fe-8818-f29f9fdde6d3'::uuid, 6),   -- Есиль в Петропавловске
    ('b5f9743c-02e7-461c-87af-52025a590034'::uuid, 7),   -- Тобол в Костанае
    -- Запад
    ('8fd0c881-b160-48ac-a5bf-ab178de12b45'::uuid, 8),   -- Урал в Уральске
    ('4fe692c8-6149-40f9-95e7-2c08e4e827a6'::uuid, 9),   -- Урал в Атырау
    ('b9a21bf1-cdfd-481a-967b-8c02a1aa8046'::uuid, 10),  -- Илек в Актобе
    -- Юг
    ('f876ffd4-21f0-4ff1-92ee-88cd4723e3f7'::uuid, 11),  -- Сырдарья в Кызылорде
    ('df530771-9657-4291-932f-a5101627bdd9'::uuid, 12)   -- Талас в Таразе
  ) as x (id, position) on true
  join public.places p
    on p.id = x.id
   and p.owner_id = private.editorial_id()
   and p.deleted_at is null
   and p.status = 'published'
   and p.visibility = 'public'
 where c.slug = 'city_rivers'
on conflict do nothing;
