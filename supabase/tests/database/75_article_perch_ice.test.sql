-- Статья «Окунь со льда» (миграция …_article_perch_ice.sql): опубликована на трёх языках четвёртой,
-- после «Зимнего судака», и говорит о правилах по первоисточникам.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(3);

set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select is(
  (select array_agg(id order by sort_order, id) from (select id, sort_order from public.articles order by sort_order, id limit 4) a),
  array['ice_fishing_basics', 'pike_tip_ups', 'zander_winter', 'perch_ice'],
  'окунь — четвёртый, после «Зимнего судака»'
);
select ok(
  (select title_kk <> '' and title_en <> '' and body_kk <> '' and body_en <> ''
     from public.articles where id = 'perch_ice'),
  'статья на трёх языках'
);
select ok(
  (select body_ru like '%Промысловой меры для окуня нет%' and body_ru like '%До 5 кг рыбы за выезд%'
          and body_ru like '%зимовальных ямах%' and body_en like '%no minimum size for perch%'
     from public.articles where id = 'perch_ice'),
  'мера, норма за выезд и зимовальные ямы — в тексте'
);

select * from finish();
rollback;
