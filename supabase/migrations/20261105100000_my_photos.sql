-- Раздел «Фото» в профиле (план: docs/02-plan/01-profile.md, 1.1 — «Фото — сетка последних 6 и
-- «Все фото»): свои фото из отчётов, уловов и отзывов, новые сверху, с местом.
--
-- Только свои строки `media`. Название места — если место ещё видно владельцу фото (своё или
-- чужое публичное); иначе пусто. Страницы — после фото p_after: у фото одного отчёта одно время
-- загрузки, поэтому курсор — id, а время берётся из базы (с точностью до микросекунд).

create function public.my_photos(p_limit integer default 60, p_after uuid default null)
returns table (
  id uuid,
  path text,
  thumb_path text,
  width integer,
  height integer,
  created_at timestamptz,
  checkin_id uuid,
  catch_id uuid,
  review_id uuid,
  place_id uuid,
  place_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  with cursor as (
    select coalesce((select m.created_at from public.media m where m.id = p_after and m.owner_id = auth.uid()),
                    'infinity'::timestamptz) as at,
           case when p_after is null then 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid else p_after end as id
  )
  select m.id, m.storage_path,
         m.owner_id::text || '/' || m.id::text || '_thumb.jpg',
         m.width, m.height, m.created_at,
         m.checkin_id, m.catch_id, m.review_id,
         m.place_id,
         case when p.deleted_at is null
                   and (p.owner_id = auth.uid() or (p.status = 'published' and private.can_view(auth.uid(), p.owner_id, p.visibility)))
              then p.name end
    from public.media m
    cross join cursor c
    left join public.places p on p.id = m.place_id
   where m.owner_id = auth.uid()
     and m.deleted_at is null
     and (m.created_at, m.id) < (c.at, c.id)
   order by m.created_at desc, m.id desc
   limit least(greatest(coalesce(p_limit, 60), 1), 200);
$$;

revoke execute on function public.my_photos(integer, uuid) from public, anon;
grant execute on function public.my_photos(integer, uuid) to authenticated;
