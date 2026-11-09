-- Справочник рыб: виды севера, востока и горных рек (волна 6 плана наполнения,
-- docs/05-release/content.md). Без них места на Иртыше и Тоболе не могли отметить налима, язя,
-- сига и рипуса, а уловы — хариуса и тайменя. Приложение берёт справочник из базы — новые виды
-- появятся в выборе улова и в «Сведениях» места без обновления приложения.
--
-- Казахские названия — черновик на вычитку специалистом (как и у первых 17 видов).
-- Промысловая мера (min_length_cm) — по-прежнему в правилах рыболовства (regulations).

insert into public.fish_species (id, name_ru, name_kk, name_en, name_latin, sort_order) values
  ('burbot',    'Налим',        'Налим',       'Burbot',          'Lota lota',                  170),
  ('ide',       'Язь',          'Аққайран',    'Ide',             'Leuciscus idus',             180),
  ('ruffe',     'Ёрш',          'Таутан',      'Ruffe',           'Gymnocephalus cernua',       190),
  ('rudd',      'Красноперка',  'Қызылқанат',  'Rudd',            'Scardinius erythrophthalmus', 200),
  ('sabrefish', 'Чехонь',       'Қылышбалық',  'Sabrefish',       'Pelecus cultratus',          210),
  ('whitefish', 'Сиг',          'Ақсаха',      'Whitefish',       'Coregonus lavaretus',        220),
  ('vendace',   'Рипус',        'Рипус',       'Vendace',         'Coregonus albula',           230),
  ('grayling',  'Хариус',       'Хариус',      'Arctic grayling', 'Thymallus arcticus',         240),
  ('taimen',    'Таймень',      'Таймень',     'Taimen',          'Hucho taimen',               250),
  ('lenok',     'Ленок',        'Ленок',       'Lenok',           'Brachymystax lenok',         260)
on conflict (id) do nothing;
