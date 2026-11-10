-- Справочник рыб: ещё 9 видов (волна 6 плана наполнения, docs/05-release/content.md) — 27 → 36.
-- Семь из них уже были в промысловой мере Правил рыболовства, но только текстом правила: шемая,
-- белоглазка, вобла, густера, берш, пелядь, елец. Теперь их мера — в min_sizes правил, и форма улова
-- предупредит, если рыба меньше меры. Ещё два вида — голавль и ротан — нужны для отчётов.
--
-- Названия и латынь — по статьям русской Википедии и связанным статьям казахской: голавль —
-- «Құсбас», густера — «Балпан балық», белоглазка — «Шегірбалық», берш — «Беріш». Статей на казахском
-- о ельце, ротане, вобле и шемае нет — пока заимствованные названия; на вычитку специалистом.
-- Вобла и шемая — подвиды каспийской плотвы и шемаи; латынь — вида.

insert into public.fish_species (id, name_ru, name_kk, name_en, name_latin, sort_order) values
  ('dace',            'Елец',        'Елец',         'Common dace',     'Leuciscus leuciscus',  270),
  ('chub',            'Голавль',     'Құсбас',       'European chub',   'Squalius cephalus',    280),
  ('silver_bream',    'Густера',     'Балпан балық', 'Silver bream',    'Blicca bjoerkna',      290),
  ('white_eye_bream', 'Белоглазка',  'Шегірбалық',   'White-eye bream', 'Ballerus sapa',        300),
  ('caspian_roach',   'Вобла',       'Вобла',        'Caspian roach',   'Rutilus caspicus',     310),
  ('shemaya',         'Шемая',       'Шемая',        'Shemaya',         'Alburnus chalcoides',  320),
  ('volga_zander',    'Берш',        'Беріш',        'Volga zander',    'Sander volgensis',     330),
  ('peled',           'Пелядь',      'Пелядь',       'Peled',           'Coregonus peled',      340),
  ('rotan',           'Ротан',       'Ротан',        'Chinese sleeper', 'Perccottus glenii',    350)
on conflict (id) do nothing;

-- Мера этих видов — из текста правил в min_sizes; из текста перечисления убраны.

update public.regulations
   set min_sizes = min_sizes || '{"shemaya": 17, "white_eye_bream": 18}'::jsonb,
       body_ru = 'Шардаринское водохранилище и Сырдарья от водохранилища до границы с Узбекистаном. Рыбу меньше меры (от вершины рыла до основания средних лучей хвостового плавника) нужно отпустить.',
       body_kk = 'Шардара су қоймасы және Сырдария су қоймасынан Өзбекстан шекарасына дейін. Өлшемнен кіші балықты (тұмсық ұшынан құйрық қанатының ортаңғы сәулелерінің негізіне дейін) босату керек.',
       body_en = 'Shardara Reservoir and the Syr Darya from the reservoir to the Uzbekistan border. Release fish shorter than the minimum (measured from the tip of the snout to the base of the middle tail rays).'
 where id = 'min_size_shardara';

update public.regulations
   set min_sizes = min_sizes || '{"shemaya": 17, "white_eye_bream": 18}'::jsonb,
       body_ru = 'Сырдарья от Шардаринского водохранилища до Кызылординской области, реки Келес и Арысь, водоёмы Туркестанской области. Рыбу меньше меры (от вершины рыла до основания средних лучей хвостового плавника) нужно отпустить.',
       body_kk = 'Сырдария Шардара су қоймасынан Қызылорда облысына дейін, Келес және Арыс өзендері, Түркістан облысының су айдындары. Өлшемнен кіші балықты (тұмсық ұшынан құйрық қанатының ортаңғы сәулелерінің негізіне дейін) босату керек.',
       body_en = 'The Syr Darya from Shardara Reservoir to Kyzylorda Region, the Keles and Arys rivers and the waters of Turkestan Region. Release fish shorter than the minimum (measured from the tip of the snout to the base of the middle tail rays).'
 where id = 'min_size_turkestan';

update public.regulations
   set min_sizes = min_sizes || '{"peled": 22}'::jsonb,
       body_ru = 'Водоёмы Нура-Сарысуского бассейна. Щука — 25 см для любительского лова (для промыслового — 35 см). Ещё: сиг гибридный — 22 см. На канале имени Каныша Сатпаева — те же меры для сазана, судака, щуки, линя, белого амура и толстолобика. Рыбу меньше меры (от вершины рыла до основания средних лучей хвостового плавника) нужно отпустить.',
       body_kk = 'Нұра-Сарысу бассейнінің су айдындары. Шортан — әуесқойлық аулау үшін 25 см (кәсіптік аулау үшін — 35 см). Сондай-ақ: будан ақсаха — 22 см. Қаныш Сәтбаев атындағы каналда сазан, көксерке, шортан, оңғақ, ақ амур және дөңмаңдай үшін өлшем осындай. Өлшемнен кіші балықты (тұмсық ұшынан құйрық қанатының ортаңғы сәулелерінің негізіне дейін) босату керек.',
       body_en = 'Waters of the Nura-Sarysu basin. Pike: 25 cm for amateur fishing (35 cm for commercial fishing). Also: hybrid whitefish 22 cm. On the Kanysh Satpayev Canal the same minimums apply to carp, zander, pike, tench, grass carp and silver carp. Release fish shorter than the minimum (measured from the tip of the snout to the base of the middle tail rays).'
 where id = 'min_size_nura_sarysu';

update public.regulations
   set min_sizes = min_sizes || '{"peled": 26}'::jsonb,
       body_ru = 'Водоёмы Костанайской области, кроме Верхнетобольского и Каратомарского водохранилищ. Ещё: ряпушка — 16 см, рак — 9 см (от середины глаза до конца хвостовой пластинки). Рыбу меньше меры (от вершины рыла до основания средних лучей хвостового плавника) нужно отпустить.',
       body_kk = 'Қостанай облысының су айдындары, Жоғарғы Тобыл және Қаратомар су қоймаларынан басқа. Сондай-ақ: ряпушка — 16 см, шаян — 9 см (көздің ортасынан құйрық пластинасының ұшына дейін). Өлшемнен кіші балықты (тұмсық ұшынан құйрық қанатының ортаңғы сәулелерінің негізіне дейін) босату керек.',
       body_en = 'Waters of Kostanay Region except the Verkhnetobolsk and Karatomar reservoirs. Also: small vendace (ryapushka) 16 cm, crayfish 9 cm (from the middle of the eye to the end of the tail plate). Release fish shorter than the minimum (measured from the tip of the snout to the base of the middle tail rays).'
 where id = 'min_size_kostanay';

update public.regulations
   set min_sizes = min_sizes || '{"peled": 26}'::jsonb,
       body_ru = 'Верхнетобольское и Каратомарское водохранилища. Ещё: ряпушка — 16 см, рак — 9 см (от середины глаза до конца хвостовой пластинки). Рыбу меньше меры (от вершины рыла до основания средних лучей хвостового плавника) нужно отпустить.',
       body_kk = 'Жоғарғы Тобыл және Қаратомар су қоймалары. Сондай-ақ: ряпушка — 16 см, шаян — 9 см (көздің ортасынан құйрық пластинасының ұшына дейін). Өлшемнен кіші балықты (тұмсық ұшынан құйрық қанатының ортаңғы сәулелерінің негізіне дейін) босату керек.',
       body_en = 'The Verkhnetobolsk and Karatomar reservoirs. Also: small vendace (ryapushka) 16 cm, crayfish 9 cm (from the middle of the eye to the end of the tail plate). Release fish shorter than the minimum (measured from the tip of the snout to the base of the middle tail rays).'
 where id = 'min_size_kostanay_reservoirs';

update public.regulations
   set min_sizes = min_sizes || '{"caspian_roach": 17, "silver_bream": 17, "white_eye_bream": 22}'::jsonb,
       body_ru = 'Казахстанский сектор Каспийского моря. Судак — 37 см в Северном Каспии, морской судак в Среднем Каспии — 30 см; сазан — 40 см, в восточной части Каспия — 30 см. Ещё: сельдь — 20 см, пузанок — 14 см, кефаль — 24 см, кильки анчоусовидная и большеглазая — 7 см, рак — 9 см. Рыбу меньше меры (от вершины рыла до основания средних лучей хвостового плавника) нужно отпустить.',
       body_kk = 'Каспий теңізінің қазақстандық секторы. Көксерке — Солтүстік Каспийде 37 см, Орта Каспийдегі теңіз көксеркесі — 30 см; сазан — 40 см, Каспийдің шығыс бөлігінде — 30 см. Сондай-ақ: майшабақ — 20 см, пузанок — 14 см, кефаль — 24 см, анчоус тәрізді және үлкенкөз килька — 7 см, шаян — 9 см. Өлшемнен кіші балықты (тұмсық ұшынан құйрық қанатының ортаңғы сәулелерінің негізіне дейін) босату керек.',
       body_en = 'Kazakhstan''s sector of the Caspian Sea. Zander: 37 cm in the North Caspian, sea zander in the Middle Caspian 30 cm; carp: 40 cm, 30 cm in the eastern Caspian. Also: Caspian herring 20 cm, Caspian shad (puzanok) 14 cm, mullet 24 cm, anchovy and big-eye kilka 7 cm, crayfish 9 cm. Release fish shorter than the minimum (measured from the tip of the snout to the base of the middle tail rays).'
 where id = 'min_size_caspian';

update public.regulations
   set min_sizes = min_sizes || '{"caspian_roach": 18, "silver_bream": 17, "white_eye_bream": 22, "volga_zander": 26}'::jsonb,
       body_ru = 'Жайык и другие водоёмы Урало-Каспийского бассейна в Атырауской области. Рыбу меньше меры (от вершины рыла до основания средних лучей хвостового плавника) нужно отпустить.',
       body_kk = 'Атырау облысындағы Жайық және Орал-Каспий бассейнінің басқа су айдындары. Өлшемнен кіші балықты (тұмсық ұшынан құйрық қанатының ортаңғы сәулелерінің негізіне дейін) босату керек.',
       body_en = 'The Zhaiyk and other waters of the Ural-Caspian basin in Atyrau Region. Release fish shorter than the minimum (measured from the tip of the snout to the base of the middle tail rays).'
 where id = 'min_size_atyrau';

update public.regulations
   set min_sizes = min_sizes || '{"caspian_roach": 17}'::jsonb,
       body_ru = 'Жайык и другие водоёмы Урало-Каспийского бассейна в Западно-Казахстанской области. Ещё: рак — 9 см (от середины глаза до конца хвостовой пластинки). Рыбу меньше меры (от вершины рыла до основания средних лучей хвостового плавника) нужно отпустить.',
       body_kk = 'Батыс Қазақстан облысындағы Жайық және Орал-Каспий бассейнінің басқа су айдындары. Сондай-ақ: шаян — 9 см (көздің ортасынан құйрық пластинасының ұшына дейін). Өлшемнен кіші балықты (тұмсық ұшынан құйрық қанатының ортаңғы сәулелерінің негізіне дейін) босату керек.',
       body_en = 'The Zhaiyk and other waters of the Ural-Caspian basin in West Kazakhstan Region. Also: crayfish 9 cm (from the middle of the eye to the end of the tail plate). Release fish shorter than the minimum (measured from the tip of the snout to the base of the middle tail rays).'
 where id = 'min_size_wko';

update public.regulations
   set min_sizes = min_sizes || '{"dace": 19}'::jsonb,
       body_ru = 'Водоёмы Шу-Таласского бассейна. Рыбу меньше меры (от вершины рыла до основания средних лучей хвостового плавника) нужно отпустить.',
       body_kk = 'Шу-Талас бассейнінің су айдындары. Өлшемнен кіші балықты (тұмсық ұшынан құйрық қанатының ортаңғы сәулелерінің негізіне дейін) босату керек.',
       body_en = 'Waters of the Shu-Talas basin. Release fish shorter than the minimum (measured from the tip of the snout to the base of the middle tail rays).'
 where id = 'min_size_shu_talas';
