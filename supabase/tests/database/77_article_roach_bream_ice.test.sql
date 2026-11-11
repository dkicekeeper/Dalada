-- Статья «Плотва и лещ со льда» (миграция …_article_roach_bream_ice.sql): шестая в списке, после «Налима
-- зимой» и перед «Безопасностью на льду», на трёх языках, с мерой леща, плотвы и воблы по бассейнам.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(3);

set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select is(
  (select array_agg(id order by sort_order, id) from (select id, sort_order from public.articles order by sort_order, id limit 7) a),
  array['ice_fishing_basics', 'pike_tip_ups', 'zander_winter', 'perch_ice', 'burbot_winter', 'roach_bream_ice', 'ice_safety'],
  'плотва и лещ — шестая, перед «Безопасностью на льду»'
);
select ok(
  (select title_kk <> '' and title_en <> '' and body_kk <> '' and body_en <> ''
     from public.articles where id = 'roach_bream_ice'),
  'статья на трёх языках'
);
select ok(
  (select body_ru like '%26 см на Капшагае%' and body_ru like '%18 см в Атырауской%'
          and body_ru like '%19 см в Актюбинской области и в Шу-Таласском бассейне%'
          and body_en like '%26 cm on Kapshagay%'
     from public.articles where id = 'roach_bream_ice'),
  'мера леща, плотвы и воблы по бассейнам — в тексте'
);

select * from finish();
rollback;
