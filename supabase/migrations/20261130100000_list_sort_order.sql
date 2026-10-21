-- Свой порядок экипировки (внутри категории) и чеклистов: перетаскиванием в списке (DesignKit 8.0.0,
-- один набор действий на всех списках).
--
-- Старые сборки порядок не знают и не присылают: upsert меняет только присланные колонки, поэтому
-- их правки порядок не стирают. Без порядка (null) — как раньше: экипировка по названию, чеклисты —
-- новые сверху.

alter table public.gear_items add column sort_order integer check (sort_order between 0 and 100000);
alter table public.checklists add column sort_order integer check (sort_order between 0 and 100000);

grant insert (sort_order), update (sort_order) on table public.gear_items, public.checklists to authenticated;
