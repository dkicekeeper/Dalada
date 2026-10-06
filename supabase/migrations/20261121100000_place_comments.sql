-- Комментарии в непубличных местах (план: docs/02-plan/03-places.md — «Дневник приватного места… в 1.1 —
-- комментарии для тех, кто видит место»; спецификация — docs/04-beta/M32-place-comments.md).
--
-- У места «только я» это дневник (заметки себе), у места «друзья» и «близкие» — разговор с теми, кто
-- видит место. Публичным местам комментарии не нужны: у них отзывы и обсуждения. Видят комментарии
-- те, кто видит место (блокировки учтены); удалить — автор комментария и владелец места. Владельцу —
-- уведомление «Новый комментарий», как к посту. Реакции («респекты») к местам — нет.

-- Реакции — только к прежним видам (место теперь тоже reaction_target, но только для комментариев).
alter table public.reactions
  add constraint reactions_target_kind_check check (target_kind in ('trip', 'checkin', 'review', 'post'));

alter table public.comments drop constraint if exists comments_target_kind_check;
alter table public.comments
  add constraint comments_target_kind_check check (target_kind in ('trip', 'checkin', 'review', 'place'));

create or replace function private.reaction_target_visible(
  p_viewer uuid,
  p_kind public.reaction_target,
  p_target uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_kind
    when 'trip' then exists (
      select 1 from public.trips t
       where t.id = p_target
         and private.can_view_trip(p_viewer, t))
    when 'checkin' then exists (
      select 1 from public.checkins c
        join public.places p on p.id = c.place_id
       where c.id = p_target
         and c.deleted_at is null
         and p.deleted_at is null
         and (p.status = 'published' or p.owner_id = p_viewer)
         and private.can_view(p_viewer, p.owner_id, p.visibility)
         and private.can_view(p_viewer, c.owner_id, c.visibility))
    when 'review' then exists (
      select 1 from public.reviews r
       where r.id = p_target
         and r.deleted_at is null
         and private.is_open_place(r.place_id, p_viewer)
         and (p_viewer is null or not private.is_blocked(p_viewer, r.owner_id)))
    when 'post' then exists (
      select 1 from public.thread_posts x
        join public.threads t on t.id = x.thread_id
       where x.id = p_target
         and x.deleted_at is null
         and t.deleted_at is null
         and private.is_open_place(t.place_id, p_viewer)
         and (p_viewer is null
              or (not private.is_blocked(p_viewer, x.owner_id)
                  and not private.is_blocked(p_viewer, t.owner_id))))
    -- Место — только непубличное: у публичных отзывы и обсуждения.
    when 'place' then exists (
      select 1 from public.places p
       where p.id = p_target
         and p.deleted_at is null
         and p.visibility <> 'public'
         and (p.status = 'published' or p.owner_id = p_viewer)
         and private.can_view(p_viewer, p.owner_id, p.visibility))
    else false
  end;
$$;

create or replace function private.reaction_target_owner(p_kind public.reaction_target, p_target uuid) returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case p_kind
    when 'trip' then (select owner_id from public.trips where id = p_target)
    when 'checkin' then (select owner_id from public.checkins where id = p_target)
    when 'review' then (select owner_id from public.reviews where id = p_target)
    when 'post' then (select owner_id from public.thread_posts where id = p_target)
    when 'place' then (select owner_id from public.places where id = p_target)
  end;
$$;

create or replace function private.comments_before_write() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  client boolean := private.is_client_request();
begin
  new.body := btrim(new.body);

  if tg_op = 'INSERT' then
    if client then
      new.owner_id := auth.uid();
    end if;
    if new.owner_id is null then
      raise exception 'auth required' using errcode = '28000';
    end if;
    new.created_at := now();
    new.edited_at := null;
    new.deleted_at := null;
    if new.target_kind not in ('trip', 'checkin', 'review', 'place') then
      raise exception 'comments are for trips, reports, reviews and places' using errcode = '22023';
    end if;
    -- Комментировать можно то, что видишь (блокировки учтены в видимости).
    if not private.reaction_target_visible(new.owner_id, new.target_kind, new.target_id) then
      raise exception 'post not found' using errcode = 'P0002';
    end if;
    if client then
      perform pg_advisory_xact_lock(hashtext('comments:' || new.owner_id::text));
      if (select count(*) from public.comments
           where owner_id = new.owner_id and created_at > now() - interval '1 hour')
         >= private.comments_per_hour_limit() then
        raise exception 'too many comments' using errcode = 'DL003';
      end if;
    end if;
  else
    new.owner_id := old.owner_id;
    new.target_kind := old.target_kind;
    new.target_id := old.target_id;
    new.created_at := old.created_at;
    if new.body is distinct from old.body then
      new.edited_at := now();
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;
