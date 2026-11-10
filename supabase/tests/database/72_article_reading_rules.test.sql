-- Статья «Как читать запрет на рыбалку» (миграция …_article_reading_rules.sql): на трёх языках, в разделе
-- «Правила и этика» сразу после «Как отпустить рыбу»; сроки в примерах совпадают со слоем правил.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(3);

select ok(
  (select category = 'rules_ethics' and title_kk <> '' and title_en <> '' and body_kk <> '' and body_en <> ''
     from public.articles where id = 'reading_rules'),
  'статья на трёх языках в разделе «Правила и этика»'
);
select is(
  (select array_agg(id order by sort_order, id) from public.articles where category = 'rules_ethics'),
  array['fish_release', 'reading_rules', 'clean_shore', 'campfire'],
  'после «Как отпустить рыбу»'
);
select ok(
  (select start_month = 4 and start_day = 5 and end_month = 5 and end_day = 20 from public.regulations where id = 'kapshagay_spawning')
  and (select start_month = 4 and start_day = 10 and end_month = 6 and end_day = 15 and gear = 'amateur' from public.regulations where id = 'zhaiyk_wko_spawning')
  and (select body_ru like '%с 5 апреля по 20 мая%' and body_ru like '%с 10 апреля по 15 июня%' from public.articles where id = 'reading_rules'),
  'сроки Капшагая и Жайыка в статье — как в правилах'
);

select * from finish();
rollback;
