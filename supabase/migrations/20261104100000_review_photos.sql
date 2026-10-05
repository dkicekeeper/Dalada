-- Фото к отзывам (план: docs/02-plan/03-places.md, 3.4 — «Оценка 1–5, текст, фото»).
--
-- Строка `media` теперь принадлежит либо чекину (как раньше), либо отзыву (`review_id`). Своей
-- видимости у фото нет и здесь: фото отзыва видят те, кто видит сам отзыв — публичное
-- опубликованное место, автор отзыва не заблокирован. До 5 фото на отзыв. Удалили отзыв — фото не
-- видно. Файлы — те же `<owner_id>/<media_id>.jpg` и `_thumb.jpg` в бакете `media`.
--
-- Запросы, которые собирают фото чекинов (отчёты, лента, галерея места), фильтруют по `checkin_id`
-- или `catch_id` — фото отзывов туда не попадают.

alter table public.media alter column checkin_id drop not null;
alter table public.media add column review_id uuid references public.reviews (id) on delete cascade;
alter table public.media add constraint media_one_owner_object
  check ((checkin_id is null) <> (review_id is null) and (review_id is null or catch_id is null));
create index media_review_idx on public.media (review_id, created_at) where review_id is not null;

grant insert (id, checkin_id, catch_id, review_id, width, height) on table public.media to authenticated;

create function private.media_per_review_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 5 $$;

create or replace function private.media_before_write() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  ch public.checkins;
  k public.catches;
  r public.reviews;
begin
  if tg_op = 'INSERT' then
    if private.is_client_request() then
      new.owner_id := auth.uid();
    end if;
    new.created_at := now();
  else
    new.owner_id := old.owner_id;
    new.checkin_id := old.checkin_id;
    new.catch_id := old.catch_id;
    new.review_id := old.review_id;
    new.created_at := old.created_at;
  end if;

  if new.owner_id is null then
    raise exception 'auth required' using errcode = '28000';
  end if;

  if new.review_id is not null then
    -- Фото только к своему отзыву; место берём из отзыва.
    select * into r from public.reviews where id = new.review_id;
    if not found or r.owner_id <> new.owner_id or r.deleted_at is not null then
      raise exception 'review not found' using errcode = 'P0002';
    end if;
    new.place_id := r.place_id;
    if tg_op = 'INSERT'
       and (select count(*) from public.media m
             where m.review_id = new.review_id and m.deleted_at is null)
           >= private.media_per_review_limit() then
      raise exception 'too many photos' using errcode = '54000';
    end if;
    new.updated_at := now();
    return new;
  end if;

  -- Фото только к своему чекину; место берём из чекина.
  select * into ch from public.checkins where id = new.checkin_id;
  if not found or ch.owner_id <> new.owner_id or ch.deleted_at is not null then
    raise exception 'checkin not found' using errcode = 'P0002';
  end if;
  new.place_id := ch.place_id;

  -- Фото улова: улов свой и из того же чекина.
  if new.catch_id is not null then
    select * into k from public.catches where id = new.catch_id;
    if not found
       or k.owner_id <> new.owner_id
       or k.checkin_id is distinct from new.checkin_id
       or k.deleted_at is not null then
      raise exception 'catch not found' using errcode = 'P0002';
    end if;
  end if;

  if tg_op = 'INSERT'
     and (select count(*) from public.media m
           where m.checkin_id = new.checkin_id and m.deleted_at is null)
         >= private.media_per_checkin_limit() then
    raise exception 'too many photos' using errcode = '54000';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

-- Видит ли зритель фото: своё — всегда; фото чекина — если видит место, чекин и улов; фото отзыва —
-- если видит отзыв (место открыто, автор отзыва не заблокирован).
create or replace function private.media_visible(viewer uuid, p_media uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.media m
      join public.checkins c on c.id = m.checkin_id
      join public.places p on p.id = c.place_id
      left join public.catches k on k.id = m.catch_id
     where m.id = p_media
       and m.deleted_at is null
       and (
         (viewer is not null and m.owner_id = viewer)
         or (
           c.deleted_at is null
           and p.deleted_at is null
           and (p.status = 'published' or p.owner_id = viewer)
           and private.can_view(viewer, p.owner_id, p.visibility)
           and private.can_view(viewer, c.owner_id, c.visibility)
           and (m.catch_id is null
                or (k.deleted_at is null and private.can_view(viewer, k.owner_id, k.visibility)))
         )
       )
  ) or exists (
    select 1
      from public.media m
      join public.reviews r on r.id = m.review_id
     where m.id = p_media
       and m.deleted_at is null
       and (
         (viewer is not null and m.owner_id = viewer)
         or (
           r.deleted_at is null
           and private.is_open_place(r.place_id, viewer)
           and (viewer is null or not private.is_blocked(viewer, r.owner_id))
         )
       )
  );
$$;

-- Отзывы места — как раньше, плюс фото отзыва (пути к файлу и превью).
drop function public.place_reviews(uuid, text, integer, integer);

create function public.place_reviews(
  p_place uuid,
  p_order text default 'new',
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  review_id uuid,
  author_id uuid,
  author_username text,
  author_display_name text,
  author_avatar_path text,
  rating smallint,
  body text,
  visited_on date,
  created_at timestamptz,
  edited_at timestamptz,
  is_own boolean,
  helpful_count integer,
  marked_helpful boolean,
  media jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.owner_id, pr.username, pr.display_name, pr.avatar_path,
         r.rating, r.body, r.visited_on, r.created_at, r.edited_at,
         r.owner_id is not distinct from auth.uid(),
         h.cnt, h.mine,
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'id', m.id,
                    'path', m.storage_path,
                    'thumb_path', m.owner_id::text || '/' || m.id::text || '_thumb.jpg',
                    'width', m.width,
                    'height', m.height
                  ) order by m.created_at, m.id)
             from public.media m
            where m.review_id = r.id
              and m.deleted_at is null
         ), '[]'::jsonb)
    from public.reviews r
    join public.profiles pr on pr.id = r.owner_id
    cross join lateral (
      select count(*)::integer as cnt,
             coalesce(bool_or(x.owner_id = auth.uid()), false) as mine
        from public.reactions x
       where x.target_kind = 'review' and x.target_id = r.id
    ) h
   where r.place_id = p_place
     and r.deleted_at is null
     and private.is_open_place(p_place, auth.uid())
     and (auth.uid() is null or not private.is_blocked(auth.uid(), r.owner_id))
   order by
     case when p_order = 'helpful' then h.cnt end desc nulls last,
     case when p_order = 'high' then r.rating end desc nulls last,
     case when p_order = 'low' then r.rating end asc nulls last,
     r.created_at desc, r.id desc
   limit least(greatest(p_limit, 1), 100)
   offset greatest(p_offset, 0);
$$;

revoke execute on function public.place_reviews(uuid, text, integer, integer) from public;
grant execute on function public.place_reviews(uuid, text, integer, integer) to anon, authenticated;
