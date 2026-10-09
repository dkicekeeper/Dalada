-- M34: запреты по всем бассейнам (приказ № 78): зоны областей, водохранилищ и рек, правила в точке.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(16);

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end $$;

-- Точка внутри зоны.
create function pg_temp.inside(zone text) returns extensions.geometry language sql as $$
  select extensions.st_pointonsurface(geom) from public.rule_zones where id = zone;
$$;

-- Правило в точке зоны на дату: действует ли (null — правила там нет).
create function pg_temp.active_in(zone text, regulation text, day date) returns boolean language sql as $$
  select r.active
    from public.regulations_at(extensions.st_x(pg_temp.inside(zone)), extensions.st_y(pg_temp.inside(zone)), day) r
   where r.regulation_id = regulation;
$$;

-- Справочник -------------------------------------------------------------------------------------

select is(
  (select array_agg(distinct basin order by basin) from public.rule_zones),
  array['aral_syrdarya', 'balkhash_alakol', 'esil', 'nura_sarysu', 'shu_talas', 'tobyl_torgay',
        'zaysan_ertis', 'zhaiyk_caspian'],
  'зоны — по всем восьми бассейнам приказа'
);
select is_empty(
  $$ select z.id from public.rule_zones z
      where not exists (select 1 from public.regulations r where z.id = any (r.zone_ids)) $$,
  'у каждой зоны есть правила'
);
select is_empty(
  $$ select a.id, b.id from public.rule_zones a join public.rule_zones b
         on a.id <> b.id and a.basin <> 'balkhash_alakol' and a.kind = 'region' and b.kind <> 'rest_zone'
        and extensions.st_intersects(a.geom, b.geom)
      where extensions.st_area(extensions.st_intersection(a.geom, b.geom)::extensions.geography) > 1e6 $$,
  'область не накрывает водоёмы и другие области со своими сроками (больше 1 км²)'
);
select is(
  (select count(*)::integer from public.rule_zones where geom is null),
  2,
  'без границы — только зоны в море: Северный Каспий и Мангышлакский архипелаг'
);
select is(
  (select array_agg(id order by id) from public.regulations where basin = 'kazakhstan'),
  array['methods_ban', 'undersize_release'],
  'запрещённые способы и промысловая мера — правила всей страны'
);

-- Правила в точке на дату ------------------------------------------------------------------------

select pg_temp.act_as_anon();
select ok(
  (select active and period_start = '2027-04-10' and period_end = '2027-05-20'
     from public.regulations_at(71.43, 51.13, '2027-05-01') where regulation_id = 'esil_spawning'),
  'Астана, 1 мая: запрет на всех водоёмах Есильского бассейна (10 апреля – 20 мая)'
);
select ok(
  (select active from public.regulations_at(66.9, 50.25, '2027-04-16') where regulation_id = 'kostanay_south_spawning')
  and not (select active from public.regulations_at(63.6, 53.2, '2027-04-16') where regulation_id = 'kostanay_spawning'),
  '16 апреля: у Аркалыка запрет уже идёт (с 15 апреля), в Костанае ещё нет (с 20 апреля)'
);
select is(
  (select array_agg(regulation_id order by regulation_id)
     from public.regulations_at(63.6, 53.2, '2027-04-16') where kind = 'fishing_ban'),
  array['kostanay_spawning'],
  'в Костанае — запрет своей области, без аркалыкского'
);
select ok(
  pg_temp.active_in('bukhtarma_upper', 'bukhtarma_upper_spawning', '2027-05-25')
  and pg_temp.active_in('bukhtarma_deep', 'bukhtarma_deep_spawning', '2027-06-10')
  and pg_temp.active_in('bukhtarma_deep', 'bukhtarma_upper_spawning', '2027-05-25') is null,
  'Бухтарма: верхняя часть закрыта до 30 мая, глубоководная — до 15 июня, у каждой свой срок'
);
select ok(
  pg_temp.active_in('bukhtarma_deep', 'bukhtarma_autumn', '2027-11-20')
  and pg_temp.active_in('bukhtarma_kaiyndy', 'bukhtarma_autumn', '2027-11-20')
  and pg_temp.active_in('bukhtarma_upper', 'bukhtarma_autumn', '2027-11-20') is null,
  'осенний запрет — от Каиынды до ГЭС, выше по течению его нет'
);
select ok(
  pg_temp.active_in('shardara_rest', 'shardara_rest_ban', '2027-09-01')
  and pg_temp.active_in('arys_keles', 'arys_keles_rest', '2027-09-01'),
  'зоны покоя Шардары, Арыси и Келеса — запрет круглый год'
);
select is(
  (select gear::text from public.regulations_at(
       extensions.st_x(pg_temp.inside('zhaiyk_wko')), extensions.st_y(pg_temp.inside('zhaiyk_wko')), '2027-06-10')
    where regulation_id = 'zhaiyk_wko_spawning' and active),
  'amateur',
  'Жайык в ЗКО, 10 июня: запрет для любительских орудий ещё идёт (до 15 июня)'
);
select ok(
  pg_temp.active_in('zhaiyk_wko', 'wko_spawning', '2027-05-01') is null
  and pg_temp.active_in('wko_waters', 'wko_spawning', '2027-05-01'),
  'на Жайыке — свой срок, а не общий для водоёмов ЗКО'
);
select ok(
  pg_temp.active_in('zhaiyk_atyrau', 'zhaiyk_night', '2027-09-01')
  and pg_temp.active_in('atyrau_waters', 'zhaiyk_crayfish', '2027-05-01'),
  'правила всего Жайык-Каспийского бассейна действуют и на реке, и в области'
);
select ok(
  (select active from public.regulations_at(
       extensions.st_x(pg_temp.inside('shu_talas_rivers')), extensions.st_y(pg_temp.inside('shu_talas_rivers')), '2027-06-15')
    where regulation_id = 'shu_talas_rivers_spawning')
  and not (select active from public.regulations_at(71.37, 42.9, '2027-06-15') where regulation_id = 'shu_talas_spawning'),
  '15 июня: Шу и Талас ещё закрыты (до 30 июня), остальные водоёмы бассейна уже нет (до 31 мая)'
);
select is(
  (select array_agg(regulation_id order by regulation_id)
     from public.regulations_at(
       extensions.st_x(pg_temp.inside('kapshagay')), extensions.st_y(pg_temp.inside('kapshagay')), '2027-04-10')
    where zone_id is not null),
  array['kapshagay_spawning', 'min_size_kapshagay'],
  'на Капшагае — только правила Балхаш-Алакольского бассейна'
);

select * from finish();
rollback;
