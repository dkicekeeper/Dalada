-- Справочник рыб и меры (миграция …_fish_species_min_sizes.sql): 36 видов, меры шемаи, белоглазки,
-- воблы, густеры, берша, пеляди и ельца — в таблице правил, в текстах правил их больше нет.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(4);

set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select is((select count(*)::integer from public.fish_species), 36, 'в справочнике 36 видов');
select is(
  (select min_sizes ->> 'volga_zander' from public.regulations where id = 'min_size_atyrau'),
  '26',
  'берш в Атырауской области — 26 см'
);
select ok(
  (select (min_sizes ->> 'peled')::int = 26 from public.regulations where id = 'min_size_kostanay_reservoirs')
  and (select (min_sizes ->> 'dace')::int = 19 from public.regulations where id = 'min_size_shu_talas')
  and (select (min_sizes ->> 'shemaya')::int = 17 from public.regulations where id = 'min_size_shardara'),
  'пелядь, елец и шемая — в таблице мер'
);
select is_empty(
  $$ select id from public.regulations
      where kind = 'min_size' and (body_ru ~ '(шемая|белоглазка|вобла|густера|берш|пелядь|елец) —' or body_kk ~ '(ақкөз|қаракөз)') $$,
  'в текстах правил этих видов больше нет, как и непроверенных казахских названий'
);

select * from finish();
rollback;
