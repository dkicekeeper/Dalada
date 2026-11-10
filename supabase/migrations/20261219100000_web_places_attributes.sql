-- Страницы мест на сайте: «Сведения» — рыба, способы ловли, подъезд, плата, удобства, связь, лучшие
-- месяцы, особенности (docs/05-release/content.md, волна 8б). Гость и так получает их из place_card;
-- здесь — для статических страниц /p/<id>/, которые читают поисковики. Служебные ключи редакции
-- (osm, source) не отдаём; пустые сведения — null.
--
-- Тип результата меняется, поэтому функция пересоздаётся; права — как в 20261118100000_web_share.sql.

drop function public.web_places();

create function public.web_places()
returns table (
  id uuid,
  type public.place_type,
  name text,
  description text,
  lon double precision,
  lat double precision,
  approximate boolean,
  photo_path text,
  attributes jsonb,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.type, p.name, p.description,
         extensions.st_x(case when p.approximate then p.approx_center else p.geom end),
         extensions.st_y(case when p.approximate then p.approx_center else p.geom end),
         p.approximate,
         (select 'photos/places/' || e.id::text || '.jpg'
            from public.place_editorial_photos e
           where e.place_id = p.id
           order by e.position, e.id
           limit 1),
         nullif(coalesce(p.attributes, '{}'::jsonb) - 'osm' - 'source', '{}'::jsonb),
         p.updated_at
    from public.places p
   where p.deleted_at is null
     and p.status = 'published'
     and p.visibility = 'public'
   order by p.id;
$$;

revoke execute on function public.web_places() from public;
grant execute on function public.web_places() to anon, authenticated;
