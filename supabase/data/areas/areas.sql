-- Геометрии слоёв карты (M16) из osm_src.areas_raw → osm_src.areas.
-- Нацпарки и заповедник — контуры из OSM, упрощённые до ≈ 100 м. Погранполоса с Китаем (2 км) и
-- погранзона с Кыргызстаном (25 км) — полосы внутрь Казахстана от общего участка государственной
-- границы в пределах Алматинской области и Жетісу (постановление Правительства РК № 356).
set search_path = extensions, public;
drop table if exists osm_src.areas;
create table osm_src.areas (id text primary key, geom geometry);

-- Буфер в метрах (через географию).
create function pg_temp.corridor(line geometry, meters double precision) returns geometry language sql as $$
  select st_buffer(line::geography, meters, 'quad_segs=4')::geometry
$$;

-- Контур: исправленный, упрощённый, только полигоны.
create function pg_temp.outline(g geometry) returns geometry language sql as $$
  select st_multi(st_collectionextract(st_makevalid(st_simplifypreservetopology(st_makevalid(g), 0.001)), 3))
$$;

insert into osm_src.areas
select key, pg_temp.outline(geom)
  from osm_src.areas_raw
 where key in ('ile_alatau', 'altyn_emel', 'charyn', 'kolsai', 'zhongar_alatau', 'almaty_reserve',
               'bayanaul', 'burabay', 'kokshetau', 'tarbagatai', 'karkaraly', 'katon_karagay', 'buiratau',
               'sairam_ugam', 'aksu_zhabagly', 'korgalzhyn', 'naurzum', 'ustyurt');

-- Регион приложения: Алматинская область и Жетісу (граница с Китаем — до ≈ 46° с. ш.).
create temp table region as select st_makeenvelope(73.0, 42.0, 83.0, 46.0, 4326) g;
create temp table kz as select st_makevalid(geom) g from osm_src.areas_raw where key = 'kz';

-- Общий участок границы: линия границы Казахстана в 3 км от соседа (контуры двух стран из OSM
-- упрощены по-разному и не совпадают точно).
create temp table border as
select key, st_intersection(st_intersection(st_boundary(kz.g), st_buffer(st_makevalid(n.geom), 0.03)), region.g) g
  from osm_src.areas_raw n, kz, region
 where n.key in ('cn', 'kg');

insert into osm_src.areas
select 'border_strip_cn', st_multi(st_collectionextract(st_makevalid(st_intersection(pg_temp.corridor(b.g, 2000), kz.g)), 3))
  from border b, kz where b.key = 'cn';

-- С Кыргызстаном — восточнее 75° в. д.: западнее граница уже Жамбылской области.
insert into osm_src.areas
select 'border_zone_kg', st_multi(st_collectionextract(st_makevalid(st_intersection(
         pg_temp.corridor(st_intersection(b.g, st_makeenvelope(75.0, 42.0, 83.0, 46.0, 4326)), 25000), kz.g)), 3))
  from border b, kz where b.key = 'kg';

select id, st_npoints(geom) points, round((st_area(geom::geography) / 1e6)::numeric) km2 from osm_src.areas order by id;
