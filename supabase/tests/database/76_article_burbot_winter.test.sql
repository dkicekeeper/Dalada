-- Статья «Налим зимой» (миграция …_article_burbot_winter.sql): пятая в списке, после «Окуня со льда», на трёх языках, с ночным запретом в Жайык-Каспийском бассейне и мерой налима. И правка «Как читать
-- запрет» (…_article_reading_rules_night_ban.sql): ночной запрет — во всём бассейне, на трёх языках.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(4);

set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select is(
  (select array_agg(id order by sort_order, id) from (select id, sort_order from public.articles order by sort_order, id limit 5) a),
  array['ice_fishing_basics', 'pike_tip_ups', 'zander_winter', 'perch_ice', 'burbot_winter'],
  'налим — пятый, после «Окуня со льда»'
);
select ok(
  (select title_kk <> '' and title_en <> '' and body_kk <> '' and body_en <> ''
     from public.articles where id = 'burbot_winter'),
  'статья на трёх языках'
);
select ok(
  (select body_ru like '%с 22:00 до 06:00%' and body_ru like '%Ночная рыбалка на налима на Урале запрещена%'
          and body_ru like '%45 см на водоёмах Костанайской и Актюбинской областей%'
          and body_en like '%Zhaiyk-Caspian basin%'
     from public.articles where id = 'burbot_winter'),
  'ночной запрет и мера налима — в тексте'
);
select ok(
  (select body_ru like '%круглый год во всём Жайык-Каспийском бассейне%'
          and body_kk like '%бүкіл Жайық-Каспий бассейнінде%'
          and body_en like '%all year across the Zhaiyk-Caspian basin%'
     from public.articles where id = 'reading_rules'),
  '«Как читать запрет»: ночной запрет — во всём бассейне, на трёх языках'
);

select * from finish();
rollback;
