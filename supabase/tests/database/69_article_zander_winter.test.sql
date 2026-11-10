-- Статья «Зимний судак» (миграция …_article_zander_winter.sql): опубликована на трёх языках третьей,
-- после «Подлёдной рыбалки» и «Жерлиц», и называет зимние запреты из слоя правил.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(3);

set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select is(
  (select array_agg(id order by sort_order, id) from (select id, sort_order from public.articles order by sort_order, id limit 4) a),
  array['ice_fishing_basics', 'pike_tip_ups', 'zander_winter', 'ice_safety'],
  'зимний судак — третий, перед «Безопасностью на льду»'
);
select ok(
  (select title_kk <> '' and title_en <> '' and body_kk <> '' and body_en <> ''
     from public.articles where id = 'zander_winter'),
  'статья на трёх языках'
);
select ok(
  (select body_ru like '%зимовальных ямах%' and body_ru like '%10 ноября по 10 декабря%' and body_ru like '%45 см в Костанайской%'
     from public.articles where id = 'zander_winter'),
  'зимовальные ямы, осенний запрет на Бухтарме и промысловая мера — в тексте'
);

select * from finish();
rollback;
