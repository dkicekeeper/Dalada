-- Промысловая мера во всех бассейнах (миграция …_min_sizes_kazakhstan.sql): меры есть везде, виды —
-- из справочника, у Павлодарской области и водохранилищ Костаная — свои зоны со своей мерой и
-- прежними запретами.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(10);

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end $$;

-- Мера вида в точке (null — меры нет).
create function pg_temp.size_at(lon double precision, lat double precision, species text) returns integer
language sql as $$
  select max((r.min_sizes ->> species)::integer)
    from public.regulations_at(lon, lat, '2027-01-15') r
   where r.min_sizes ? species;
$$;

select is(
  (select array_agg(distinct basin order by basin) from public.regulations where kind = 'min_size'),
  array['aral_syrdarya', 'balkhash_alakol', 'esil', 'nura_sarysu', 'shu_talas', 'tobyl_torgay',
        'zaysan_ertis', 'zhaiyk_caspian'],
  'промысловая мера — во всех восьми бассейнах'
);
select is_empty(
  $$ select r.id, k.key from public.regulations r cross join jsonb_object_keys(r.min_sizes) k(key)
      where not exists (select 1 from public.fish_species s where s.id = k.key) $$,
  'в мерах — только виды из справочника рыб'
);
select is_empty(
  $$ select a.id, b.id from public.rule_zones a join public.rule_zones b
         on a.id < b.id and a.id in ('pavlodar_waters', 'verkhnetobolsk', 'karatomar', 'irtysh_east_waters', 'kostanay_waters')
        and extensions.st_intersects(a.geom, b.geom)
      where extensions.st_area(extensions.st_intersection(a.geom, b.geom)::extensions.geography) > 1e6 $$,
  'новые зоны вырезаны из прежних и не накрывают соседей (больше 1 км²)'
);

select pg_temp.act_as_anon();

select is(
  (select array_agg(regulation_id order by regulation_id)
     from public.regulations_at(62.28007, 52.519677, '2027-05-01') where zone_id is not null),
  array['kostanay_crayfish', 'kostanay_spawning', 'min_size_kostanay_reservoirs'],
  'Верхнетобольское водохранилище: запреты Костанайской области и мера водохранилища'
);
select ok(
  pg_temp.size_at(62.28007, 52.519677, 'common_carp') = 45
  and pg_temp.size_at(62.865113, 52.79965, 'common_carp') = 45
  and pg_temp.size_at(63.6, 53.2, 'common_carp') = 26,
  'сазан: 45 см на Верхнетобольском и Каратомарском водохранилищах, 26 см у Костаная'
);
select ok(
  (select active from public.regulations_at(76.95, 52.29, '2027-05-01') where regulation_id = 'irtysh_east_spawning')
  and pg_temp.size_at(76.95, 52.29, 'zander') = 32,
  'Павлодар, 1 мая: нерестовый запрет прежний, судак — 32 см'
);
select is(
  pg_temp.size_at(80.25, 50.41, 'zander'),
  null::integer,
  'Семей: у водоёмов области Абай меры в Правилах нет'
);
select is(
  pg_temp.size_at(71.43, 51.13, 'pike'),
  42,
  'Астана (Есильский бассейн): щука — 42 см'
);
select is(
  pg_temp.size_at(73.1, 49.8, 'pike'),
  25,
  'Караганда (Нура-Сарысуский бассейн): щука — 25 см для любительского лова'
);
select is(
  (select array_agg(r.regulation_id order by r.regulation_id)
     from public.rule_zones z
     cross join lateral public.regulations_at(
       extensions.st_x(extensions.st_pointonsurface(z.geom)), extensions.st_y(extensions.st_pointonsurface(z.geom)), '2027-01-15') r
    where z.id = 'zhaiyk_wko' and r.kind = 'min_size'),
  array['min_size_wko'],
  'Жайык в ЗКО: мера Западно-Казахстанской области'
);

select * from finish();
rollback;
