-- Зоны для промысловой меры (fetch_osm_min_sizes.sh): Павлодарская область — из зоны
-- irtysh_east_waters, Верхнетобольское и Каратомарское водохранилища — из зоны kostanay_waters.
-- Пишет в osm_src.zones пять зон: три новые и две прежние без вырезанного.
set search_path = public, extensions;

create table if not exists osm_src.zones (id text primary key, geom geometry);
delete from osm_src.zones
 where id in ('pavlodar_waters', 'verkhnetobolsk', 'karatomar', 'irtysh_east_waters', 'kostanay_waters');

-- Павлодарская область — часть зоны irtysh_east_waters (контур области упрощён до ~1,5 км, как у
-- остальных областей); обрезки меньше 100 км² отброшены.
insert into osm_src.zones
select 'pavlodar_waters',
       (select st_multi(st_collect(d.geom))
          from st_dump(st_collectionextract(st_makevalid(st_snaptogrid(
                 st_intersection(z.geom, st_simplifypreservetopology(r.geom, 0.015)), 0.00001)), 3)) d
         where st_area(d.geom::geography) > 1e8)
  from public.rule_zones z, osm_src.min_raw r
 where z.id = 'irtysh_east_waters' and r.key = 'pavlodar';

-- Водохранилища: внешний контур без островов, упрощение ~200 м, как у остальных водоёмов.
insert into osm_src.zones
select r.key,
       st_multi(st_collectionextract(st_makevalid(st_snaptogrid(st_simplifypreservetopology(
         (select st_collect(st_makepolygon(st_exteriorring(d.geom)))
            from st_dump(st_collectionextract(st_makevalid(r.geom), 3)) d), 0.002), 0.00001)), 3))
  from osm_src.min_raw r
 where r.key in ('verkhnetobolsk', 'karatomar');

-- Прежние зоны без вырезанного: области не накрывают водоёмы и другие области со своими правилами.
insert into osm_src.zones
select z.id,
       (select st_multi(st_collect(d.geom))
          from st_dump(st_collectionextract(st_makevalid(st_snaptogrid(st_difference(z.geom, (
                 select st_union(o.geom) from osm_src.zones o
                  where o.id = any (case z.id when 'irtysh_east_waters' then array['pavlodar_waters']
                                              else array['verkhnetobolsk', 'karatomar'] end))), 0.00001)), 3)) d
         where st_area(d.geom::geography) > 1e6)
  from public.rule_zones z
 where z.id in ('irtysh_east_waters', 'kostanay_waters');

select id, st_npoints(geom) as points, round((st_area(geom::geography) / 1e6)::numeric) as km2
  from osm_src.zones
 where id in ('pavlodar_waters', 'verkhnetobolsk', 'karatomar', 'irtysh_east_waters', 'kostanay_waters')
 order by id;
