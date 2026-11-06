-- Подборка редакции «Подлёдная рыбалка» для вкладки «Места» — к событию App Store «Первый лёд»
-- (docs/05-release/promotion.md, «События в App Store»). Известные водоёмы, куда ездят на лёд:
-- восток, север, Астана, Костанай и юг (Капшагай, Балхаш, Алаколь в морозную зиму). Заповедники и
-- нацпарки (Маркаколь, Бурабай) не берём: там свои правила лова.
--
-- Места по расстоянию от человека, как у других подборок. Сезонная: весной редакция снимает её
-- (published = false в Studio), к следующей зиме — включает. Состав правит в Studio.

insert into public.place_collections (slug, title, position) values
  ('ice_fishing',
   '{"ru": "Подлёдная рыбалка", "kk": "Мұз астынан балық аулау", "en": "Ice fishing"}',
   5)
on conflict (slug) do nothing;

insert into public.place_collection_items (collection_id, place_id, position)
select c.id, p.id, x.position
  from public.place_collections c
  join (values
    -- Восток
    ('22b8b8ae-bfa8-40de-8e51-f66e570cdb35'::uuid, 1),   -- Бухтарминское водохранилище
    ('566ca4f7-7f00-4bdf-a436-b594a3a08f49'::uuid, 2),   -- Шульбинское водохранилище
    ('b64a27e0-ebbb-453d-ba9f-57626a5d6f7a'::uuid, 3),   -- Усть-Каменогорское водохранилище
    ('1c76f71b-ab38-4de0-9f8b-7c43ce9a4d89'::uuid, 4),   -- Озеро Зайсан
    -- Север и Астана
    ('34cc0dc9-7ef9-43ee-bf3f-a867214432a3'::uuid, 5),   -- Вячеславское водохранилище
    ('e0dd6ef9-0956-40c1-8979-3cb9d2ef9367'::uuid, 6),   -- Селетинское водохранилище
    ('8751e034-c74e-4eee-93a4-3786063ec4c9'::uuid, 7),   -- Сергеевское водохранилище (СКО)
    -- Костанай
    ('9d907bdf-db52-4a7a-b6ee-f939d145c99d'::uuid, 8),   -- Верхнетобольское водохранилище
    ('0afd69c5-e99a-4e3a-ace6-ff033087048f'::uuid, 9),   -- Каратомарское водохранилище
    -- Юг
    ('8843e17d-55fb-43ed-97df-959faa0b2e8b'::uuid, 10),  -- Капчагайское водохранилище
    ('34727383-fa9e-45a2-b1e3-60676a68275f'::uuid, 11),  -- Балхаш
    ('40db63d1-4f49-4c5f-a994-d08fd3b1d93f'::uuid, 12)   -- Алаколь
  ) as x (id, position) on true
  join public.places p
    on p.id = x.id
   and p.owner_id = private.editorial_id()
   and p.deleted_at is null
   and p.status = 'published'
   and p.visibility = 'public'
 where c.slug = 'ice_fishing'
on conflict do nothing;
