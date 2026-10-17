-- Метки экипировки: свои слова вроде «зима», «лодка», «с детьми» — сверх категории. По меткам
-- список фильтруется, сводка показывает вес отобранного.
--
-- Старые сборки метки не знают и не присылают: upsert меняет только присланные колонки, поэтому
-- их правки метки не стирают, а новая строка получает пустой список.

alter table public.gear_items add column tags text[] not null default '{}';

-- До 10 меток по 1–30 знаков, без пустых и без повторов (без учёта регистра).
create function private.gear_tags_valid(p_tags text[]) returns boolean
language sql immutable
set search_path = ''
as $$
  select cardinality(p_tags) <= 10
     and array_position(p_tags, null) is null
     and not exists (
       select 1 from unnest(p_tags) t
        where char_length(btrim(t)) not between 1 and 30 or t <> btrim(t)
     )
     and (select count(distinct lower(t)) from unnest(p_tags) t) = cardinality(p_tags);
$$;

-- Проверка — в триггере: функции схемы private клиенту не видны.
create function private.gear_items_validate_tags() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.gear_tags_valid(new.tags) then
    raise exception 'invalid gear tags' using errcode = '23514';
  end if;
  return new;
end;
$$;

-- Выполняется после gear_items_before_write (триггеры идут по имени) и только если правка принята.
create trigger gear_items_validate_tags before insert or update on public.gear_items
  for each row execute function private.gear_items_validate_tags();

grant insert (tags), update (tags) on table public.gear_items to authenticated;
