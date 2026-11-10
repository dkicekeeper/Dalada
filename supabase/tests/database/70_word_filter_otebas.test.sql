-- Фильтр слов (миграция …_word_filter_otebas.sql): название озера «Отебас» проходит, грубые формы
-- корня «еб» с приставкой «от» и без неё — нет.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(2);

select is_empty(
  $$ select w from unnest(array['Отебас', 'озеро Отебас', 'Отебасы', 'ОТЕБАС']) w where private.has_banned_words(w) $$,
  '«Отебас» и его формы проходят'
);
select is(
  (select count(*)::integer from unnest(array['отебал', 'отебись', 'отъебись', 'заебал', 'ебать', 'xуй']) w
    where private.has_banned_words(w)),
  6,
  'грубые формы с приставкой «от» и без неё по-прежнему находятся'
);

select * from finish();
rollback;
