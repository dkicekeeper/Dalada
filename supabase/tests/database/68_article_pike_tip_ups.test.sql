-- Статья «Жерлицы: как ловить щуку со льда» (миграция …_article_pike_tip_ups.sql): опубликована на
-- трёх языках сразу после «Подлёдной рыбалки», а та больше не отсылает за числом жерлиц к правилам.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(3);

set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select is(
  (select array_agg(id order by sort_order, id) from (select id, sort_order from public.articles order by sort_order, id limit 2) a),
  array['ice_fishing_basics', 'pike_tip_ups'],
  'статья о жерлицах — вторая, после «Подлёдной рыбалки»'
);
select ok(
  (select title_kk <> '' and title_en <> '' and body_kk <> '' and body_en <> ''
          and body_ru like '%Перечень разрешённых орудий лова (п. 26)%'
     from public.articles where id = 'pike_tip_ups'),
  'статья на трёх языках и ссылается на пункты первоисточников'
);
select ok(
  (select body_ru like '%Правила рыболовства не ограничивают%'
          and body_kk like '%шектемейді%'
          and body_en like '%do not limit how many%'
          and body_ru not like '%указано в правилах рыболовства%'
     from public.articles where id = 'ice_fishing_basics'),
  '«Подлёдная рыбалка» на всех языках говорит, что число жерлиц не ограничено'
);

select * from finish();
rollback;
