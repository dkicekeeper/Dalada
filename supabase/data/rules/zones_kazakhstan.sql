-- M34: зоны правил остальных бассейнов (приказ № 78, главы 2 и 4–9) из osm_src.kz_raw
-- (fetch_osm_kz.sh) → osm_src.zones. Зоны «все водоёмы области» — контур области без водоёмов
-- со своими сроками. Границы приблизительные: текст правила важнее линии на карте.
set search_path = extensions, public;
create table if not exists osm_src.zones (id text primary key, geom geometry);
delete from osm_src.zones where id in (
  'shardara', 'shardara_rest', 'turkestan_waters', 'arys_keles', 'syrdarya_kyzylorda', 'small_aral',
  'kyzylorda_waters', 'bukhtarma_upper', 'bukhtarma_kaiyndy', 'bukhtarma_deep', 'kara_ertis',
  'ust_kamenogorsk', 'shulba', 'irtysh_east_waters', 'esil_waters', 'nura_sarysu_waters',
  'kostanay_south', 'kostanay_waters', 'aktobe_waters', 'zhaiyk_wko', 'wko_waters', 'zhaiyk_atyrau',
  'zhaiyk_mouth', 'kigash', 'atyrau_waters', 'asa', 'shu_talas_rivers', 'shu_talas_waters');

create function pg_temp.corridor(line geometry, meters double precision) returns geometry language sql as $$
  select st_buffer(line::geography, meters, 'quad_segs=4')::geometry
$$;
create function pg_temp.raw(k text) returns geometry language sql as $$
  select st_union(st_makevalid(geom)) from osm_src.kz_raw where key = k
$$;
-- Отрезок между двумя точками приказа, продлённый на долю t в обе стороны (чтобы рассечь водоём).
create function pg_temp.cut_line(p geometry, q geometry, t float) returns geometry language sql as $$
  select st_makeline(
    st_translate(p, (st_x(p) - st_x(q)) * t, (st_y(p) - st_y(q)) * t),
    st_translate(q, (st_x(q) - st_x(p)) * t, (st_y(q) - st_y(p)) * t))
$$;
create function pg_temp.pt(lon double precision, lat double precision) returns geometry language sql as $$
  select st_setsrid(st_makepoint(lon, lat), 4326)
$$;
create temp table kz as select pg_temp.raw('kz') g;
-- Уже нанесённые зоны Балхаш-Алакольского бассейна (миграция …_rules.sql).
create temp table balkhash_basin as
  select st_union(geom) g from public.rule_zones where basin = 'balkhash_alakol' and geom is not null;

-- Арало-Сырдарьинский бассейн ----------------------------------------------------------------

-- Зона покоя Шардары (п. 5, пп. 3): Корейский залив → мыс Белый камень → устье Келеса → Азаттык,
-- с зонами затопления; плюс часть водохранилища восточнее линии «Корейский залив — мыс Белый камень».
create temp table shardara_marks as select
  pg_temp.pt(68 + 20/60. + 14.46/3600, 40 + 59/60. + 5.22/3600) a,
  pg_temp.pt(68 + 25/60. + 40.52/3600, 41 + 6/60. + 52.14/3600) b,
  pg_temp.pt(68 + 36/60. + 38.00/3600, 41 + 1/60. + 17.99/3600) c,
  pg_temp.pt(68 + 27/60. + 28.79/3600, 40 + 57/60. + 35.32/3600) d;
insert into osm_src.zones
select 'shardara_rest', st_intersection(st_union(
         st_makepolygon(st_makeline(array[m.a, m.b, m.c, m.d, m.a])),
         -- восточнее прямой a–b: полуплоскость справа от направления a → b
         st_intersection(pg_temp.raw('shardara'),
           st_makepolygon(st_makeline(array[
             st_translate(m.a, -(st_x(m.b) - st_x(m.a)) * 3, -(st_y(m.b) - st_y(m.a)) * 3),
             st_translate(m.b, (st_x(m.b) - st_x(m.a)) * 3, (st_y(m.b) - st_y(m.a)) * 3),
             st_translate(m.b, (st_x(m.b) - st_x(m.a)) * 3 + 1, (st_y(m.b) - st_y(m.a)) * 3 - 1),
             st_translate(m.a, -(st_x(m.b) - st_x(m.a)) * 3 + 1, -(st_y(m.b) - st_y(m.a)) * 3 - 1),
             st_translate(m.a, -(st_x(m.b) - st_x(m.a)) * 3, -(st_y(m.b) - st_y(m.a)) * 3)])))), kz.g)
  from shardara_marks m, kz;
insert into osm_src.zones
select 'shardara', st_difference(st_intersection(pg_temp.raw('shardara'), kz.g), z.geom)
  from kz, osm_src.zones z where z.id = 'shardara_rest';
insert into osm_src.zones
select 'turkestan_waters', st_difference(pg_temp.raw('turkestan'), st_union(pg_temp.raw('shardara'), z.geom))
  from osm_src.zones z where z.id = 'shardara_rest';
insert into osm_src.zones
select 'arys_keles', st_intersection(pg_temp.corridor(st_union(pg_temp.raw('arys'), pg_temp.raw('keles')), 1000), kz.g)
  from kz;
insert into osm_src.zones select 'small_aral', pg_temp.raw('small_aral');
insert into osm_src.zones
select 'syrdarya_kyzylorda',
       st_difference(pg_temp.corridor(st_intersection(pg_temp.raw('syrdarya'), pg_temp.raw('kyzylorda')), 1000),
                     pg_temp.raw('small_aral'));
insert into osm_src.zones
select 'kyzylorda_waters', st_difference(pg_temp.raw('kyzylorda'), st_union(z.geom, pg_temp.raw('small_aral')))
  from osm_src.zones z where z.id = 'syrdarya_kyzylorda';

-- Зайсан-Ертисский бассейн --------------------------------------------------------------------

-- Бухтарма делится двумя линиями приказа: L1 — первая Батинская сопка (п. 10, пп. 1–2), L2 — 3 км
-- выше устья Каиынды (п. 10, пп. 7; п. 11, пп. 1). От Зайсана: верхняя часть → L2 → L1 → ГЭС.
create temp table bukhtarma_lines as select
  pg_temp.cut_line(pg_temp.pt(83 + 40/60. + 23.19/3600, 49 + 0/60. + 2.20/3600),
                   pg_temp.pt(83 + 43/60. + 11.12/3600, 48 + 57/60. + 3.10/3600), 0.3) l1,
  pg_temp.cut_line(pg_temp.pt(83 + 33/60. + 47.09/3600, 48 + 57/60. + 48.59/3600),
                   pg_temp.pt(83 + 35/60. + 24.45/3600, 48 + 55/60. + 52.40/3600), 0.3) l2;
-- Сначала L2: часть у Зайсана — верхняя; остальное делим L1: часть у Усть-Каменогорского
-- водохранилища (под плотиной Бухтарминской ГЭС) — глубоководная, между линиями — у Каиынды.
create temp table bukhtarma_split2 as
select p.geom g, st_distance(p.geom::geography, pg_temp.raw('zaysan')::geography) < 1000 as upper
  from bukhtarma_lines l, st_dump(st_split(pg_temp.raw('bukhtarma'), l.l2)) p
 where st_area(p.geom::geography) > 5e5;
create temp table bukhtarma_split1 as
select p.geom g, st_distance(p.geom::geography, pg_temp.raw('ust_kamenogorsk')::geography) < 1000 as deep
  from bukhtarma_lines l, st_dump(st_split((select st_union(g) from bukhtarma_split2 where not upper), l.l1)) p
 where st_area(p.geom::geography) > 5e5;
insert into osm_src.zones
select 'bukhtarma_upper', st_union(pg_temp.raw('zaysan'), (select st_union(g) from bukhtarma_split2 where upper));
insert into osm_src.zones
select 'bukhtarma_kaiyndy', st_union(g) from bukhtarma_split1 where not deep;
insert into osm_src.zones
select 'bukhtarma_deep', st_union(g) from bukhtarma_split1 where deep;
-- Кара Ертис от Зайсана до границы с КНР (зона покоя, п. 12, пп. 3): полоса 2 км с дельтой.
insert into osm_src.zones
select 'kara_ertis', st_difference(st_intersection(pg_temp.corridor(
         st_intersection(pg_temp.raw('kara_ertis'), st_makeenvelope(84.3, 47.5, 86, 48.6, 4326)), 2000), kz.g),
         pg_temp.raw('zaysan'))
  from kz;
-- Усть-Каменогорское водохранилище и Ертис от его ГЭС до Шульбинского водохранилища.
insert into osm_src.zones
select 'ust_kamenogorsk', st_union(pg_temp.raw('ust_kamenogorsk'),
         st_difference(pg_temp.corridor(st_intersection(pg_temp.raw('irtysh'), st_makeenvelope(81.75, 49.8, 82.75, 50.5, 4326)), 1000),
                       st_union(pg_temp.raw('shulba'), pg_temp.raw('ust_kamenogorsk'))));
-- Шульбинское водохранилище и Ертис от Шульбинской ГЭС до Павлодарской области.
insert into osm_src.zones
select 'shulba', st_difference(st_union(pg_temp.raw('shulba'),
         pg_temp.corridor(st_intersection(pg_temp.raw('irtysh'),
           st_intersection(pg_temp.raw('abai'), st_makeenvelope(70, 45, 81.07, 55, 4326))), 1000)), z.geom)
  from osm_src.zones z where z.id = 'ust_kamenogorsk';
-- Водоёмы Павлодарской, Восточно-Казахстанской областей и области Абай, Ертис до границы с РФ —
-- без водоёмов со своими сроками и без зон Балхаш-Алакольского бассейна.
insert into osm_src.zones
select 'irtysh_east_waters',
       st_difference(st_union(array[pg_temp.raw('pavlodar'), pg_temp.raw('vko'), pg_temp.raw('abai')]),
                     st_union(array[(select st_union(geom) from osm_src.zones
                                      where id in ('bukhtarma_upper', 'bukhtarma_kaiyndy', 'bukhtarma_deep',
                                                   'kara_ertis', 'ust_kamenogorsk', 'shulba')),
                                    b.g]))
  from balkhash_basin b;

-- Есильский бассейн: Астана, Акмолинская и Северо-Казахстанская области -------------------------
insert into osm_src.zones
select 'esil_waters', st_union(array[pg_temp.raw('astana'), pg_temp.raw('akmola'), pg_temp.raw('nko')]);

-- Нура-Сарысуский бассейн: Карагандинская область и Улытау без Балхаша --------------------------
insert into osm_src.zones
select 'nura_sarysu_waters', st_difference(st_union(pg_temp.raw('karaganda'), pg_temp.raw('ulytau')), b.g)
  from balkhash_basin b;

-- Тобыл-Торгайский бассейн ----------------------------------------------------------------------
insert into osm_src.zones
select 'kostanay_south', st_union(array[pg_temp.raw('arkalyk'), pg_temp.raw('amangeldy'), pg_temp.raw('zhangeldy')]);
insert into osm_src.zones
select 'kostanay_waters', st_difference(pg_temp.raw('kostanay'), z.geom) from osm_src.zones z where z.id = 'kostanay_south';
insert into osm_src.zones select 'aktobe_waters', pg_temp.raw('aktobe');

-- Жайык-Каспийский бассейн ----------------------------------------------------------------------
-- Жайык в ЗКО с пойменными водоёмами: полоса 2 км.
insert into osm_src.zones
select 'zhaiyk_wko', pg_temp.corridor(st_intersection(pg_temp.raw('ural'), pg_temp.raw('wko')), 2000);
insert into osm_src.zones
select 'wko_waters', st_difference(pg_temp.raw('wko'), z.geom) from osm_src.zones z where z.id = 'zhaiyk_wko';
-- Жайык в Атырауской области: ниже тони Малая Дамбинская (зимовальная яма, 46°57.240′ с. ш.) —
-- зона покоя до устья (п. 24, пп. 1), выше — до границы ЗКО.
insert into osm_src.zones
select 'zhaiyk_mouth', st_difference(pg_temp.corridor(st_intersection(pg_temp.raw('ural'),
         st_intersection(pg_temp.raw('atyrau'), st_makeenvelope(45, 40, 56, 46 + 57.240/60, 4326))), 1000), z.geom)
  from osm_src.zones z where z.id = 'zhaiyk_wko';
insert into osm_src.zones
select 'zhaiyk_atyrau', st_difference(st_difference(pg_temp.corridor(st_intersection(pg_temp.raw('ural'), pg_temp.raw('atyrau')), 1000),
                                                    z.geom), w.geom)
  from osm_src.zones z, osm_src.zones w where z.id = 'zhaiyk_mouth' and w.id = 'zhaiyk_wko';
insert into osm_src.zones
select 'kigash', st_intersection(pg_temp.corridor(pg_temp.raw('kigash'), 1000), kz.g) from kz;
insert into osm_src.zones
select 'atyrau_waters', st_difference(pg_temp.raw('atyrau'),
         (select st_union(geom) from osm_src.zones where id in ('zhaiyk_mouth', 'zhaiyk_atyrau', 'kigash', 'zhaiyk_wko')));

-- Шу-Таласский бассейн: Жамбылская область --------------------------------------------------------
-- Аса и протоки между озёрами Биликоль, Богетколь и Акколь (сами озёра — по общему сроку бассейна).
-- В OpenStreetMap река нанесена не вся: только этот участок, полоса 1 км.
insert into osm_src.zones select 'asa', pg_temp.corridor(pg_temp.raw('asa'), 1000);
-- Шу выше Тасоткельского водохранилища (восточнее его плотины) и Талас — в Казахстане, полоса 1 км.
insert into osm_src.zones
select 'shu_talas_rivers', st_difference(st_intersection(st_union(
         pg_temp.corridor(st_intersection(pg_temp.raw('shu'), st_makeenvelope(73.9, 42, 76, 44, 4326)), 1000),
         pg_temp.corridor(pg_temp.raw('talas'), 1000)), kz.g), st_union(pg_temp.raw('tasotkel'), z.geom))
  from kz, osm_src.zones z where z.id = 'asa';
insert into osm_src.zones
select 'shu_talas_waters', st_difference(st_difference(pg_temp.raw('zhambyl'),
         (select st_union(geom) from osm_src.zones where id in ('asa', 'shu_talas_rivers'))), b.g)
  from balkhash_basin b;

-- Обработка ------------------------------------------------------------------------------------

-- Класс зоны: область (region), река (river) или водоём (water) — от него зависит упрощение.
-- Порядок — порядок вычитания ниже: сначала то, что вычитают из других.
create temp table kz_zones (ord serial, id text primary key, class text);
insert into kz_zones (id, class) values
  ('shardara_rest', 'water'), ('shardara', 'water'), ('small_aral', 'water'),
  ('bukhtarma_upper', 'water'), ('bukhtarma_kaiyndy', 'water'), ('bukhtarma_deep', 'water'),
  ('ust_kamenogorsk', 'water'), ('shulba', 'water'),
  ('arys_keles', 'river'), ('syrdarya_kyzylorda', 'river'), ('kara_ertis', 'river'), ('zhaiyk_wko', 'river'),
  ('zhaiyk_mouth', 'river'), ('zhaiyk_atyrau', 'river'), ('kigash', 'river'), ('asa', 'river'),
  ('shu_talas_rivers', 'river'),
  ('turkestan_waters', 'region'), ('kyzylorda_waters', 'region'), ('irtysh_east_waters', 'region'),
  ('esil_waters', 'region'), ('nura_sarysu_waters', 'region'), ('kostanay_south', 'region'),
  ('kostanay_waters', 'region'), ('aktobe_waters', 'region'), ('wko_waters', 'region'),
  ('atyrau_waters', 'region'), ('shu_talas_waters', 'region');

-- Что вычесть из зоны после упрощения, чтобы зоны с разными сроками не накрывали друг друга
-- (balkhash — зоны Балхаш-Алакольского бассейна). Реки-зоны покоя (Арысь, Келес) остаются внутри
-- области: там действуют оба правила.
create temp table kz_minus (id text, minus text);
insert into kz_minus values
  ('shardara', 'shardara_rest'),
  ('bukhtarma_kaiyndy', 'bukhtarma_upper'), ('bukhtarma_deep', 'bukhtarma_kaiyndy'),
  ('ust_kamenogorsk', 'bukhtarma_deep'), ('shulba', 'ust_kamenogorsk'),
  ('syrdarya_kyzylorda', 'small_aral'), ('kara_ertis', 'bukhtarma_upper'),
  ('zhaiyk_mouth', 'zhaiyk_wko'), ('zhaiyk_atyrau', 'zhaiyk_wko'), ('zhaiyk_atyrau', 'zhaiyk_mouth'),
  ('shu_talas_rivers', 'asa'),
  ('turkestan_waters', 'shardara'), ('turkestan_waters', 'shardara_rest'),
  ('kyzylorda_waters', 'syrdarya_kyzylorda'), ('kyzylorda_waters', 'small_aral'),
  ('irtysh_east_waters', 'bukhtarma_upper'), ('irtysh_east_waters', 'bukhtarma_kaiyndy'),
  ('irtysh_east_waters', 'bukhtarma_deep'), ('irtysh_east_waters', 'kara_ertis'),
  ('irtysh_east_waters', 'ust_kamenogorsk'), ('irtysh_east_waters', 'shulba'), ('irtysh_east_waters', 'balkhash'),
  ('nura_sarysu_waters', 'balkhash'),
  ('kostanay_waters', 'kostanay_south'),
  ('wko_waters', 'zhaiyk_wko'),
  ('atyrau_waters', 'zhaiyk_wko'), ('atyrau_waters', 'zhaiyk_mouth'), ('atyrau_waters', 'zhaiyk_atyrau'),
  ('atyrau_waters', 'kigash'),
  ('shu_talas_waters', 'asa'), ('shu_talas_waters', 'shu_talas_rivers'), ('shu_talas_waters', 'balkhash'),
  ('turkestan_waters', 'syrdarya_kyzylorda');
-- Соседние области после упрощения заходят друг на друга: каждая следующая — без предыдущих.
insert into kz_minus
select b.id, a.id from kz_zones a join kz_zones b on a.class = 'region' and b.class = 'region' and a.ord < b.ord;

-- Острова внутри водоёмов для правил не важны: только внешние контуры (водохранилища и озёра).
update osm_src.zones z
   set geom = (select st_collect(st_makepolygon(st_exteriorring(d.geom))) from st_dump(st_collectionextract(st_makevalid(z.geom), 3)) d)
 where id in ('shardara', 'small_aral', 'bukhtarma_upper', 'bukhtarma_kaiyndy', 'bukhtarma_deep');

-- Упрощение: области — ~1,5 км (граница области для правил и так приблизительна), реки — ~300 м,
-- водоёмы — ~200 м; сетка ~1 м; только полигоны.
update osm_src.zones z
   set geom = st_multi(st_collectionextract(st_makevalid(st_snaptogrid(st_simplifypreservetopology(z.geom,
                case k.class when 'region' then 0.015 when 'river' then 0.003 else 0.002 end), 0.00001)), 3))
  from kz_zones k where k.id = z.id;

-- Вычитание — по порядку kz_zones, из уже обработанных зон.
do $$
declare
  r record;
begin
  for r in select k.id from kz_zones k where exists (select 1 from kz_minus m where m.id = k.id) order by k.ord loop
    update osm_src.zones z
       set geom = st_multi(st_collectionextract(st_makevalid(st_snaptogrid(st_difference(z.geom, (
             select st_union(case when m.minus = 'balkhash' then (select g from balkhash_basin) else o.geom end)
               from kz_minus m left join osm_src.zones o on o.id = m.minus
              where m.id = r.id)), 0.00001)), 3))
     where z.id = r.id;
  end loop;
end $$;

-- Обрезки: у областей — меньше 100 км² (щели между контурами соседних областей и районов),
-- у водоёмов и рек — меньше 0,5 км².
update osm_src.zones z
   set geom = (select st_multi(st_collect(d.geom)) from st_dump(z.geom) d
                where st_area(d.geom::geography) > case k.class when 'region' then 1e8 else 5e5 end)
  from kz_zones k where k.id = z.id;

-- Ещё раз на сетку и в корректный вид: экспорт округляет координаты до 5 знаков, и кольцо не должно
-- схлопнуться.
update osm_src.zones z
   set geom = st_multi(st_collectionextract(st_makevalid(st_snaptogrid(z.geom, 0.00001)), 3))
  from kz_zones k where k.id = z.id;

select z.id, st_npoints(geom) pts, st_numgeometries(geom) parts, round(st_area(geom::geography)/1e6) km2,
       st_isvalid(geom) valid, st_isvalid(st_geomfromtext(st_astext(geom, 5))) valid_5, length(st_astext(geom, 5)) wkt_chars
  from osm_src.zones z join kz_zones k on k.id = z.id
 order by z.id;
