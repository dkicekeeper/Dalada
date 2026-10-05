-- Удаление и правка своих записей (после беты 130: «не могу удалить и отредактировать место и улов»).
--
-- База и раньше разрешала владельцу менять и удалять (deleted_at) свои места, чекины и уловы, но
-- триггеры проверяли место и чекин и при правке: улов или отчёт в удалённом (или скрытом
-- модератором) месте нельзя было ни удалить, ни поправить. Теперь:
-- - удалить своё (deleted_at) можно всегда — проверки места и чекина только при создании и правке;
-- - править улов и отчёт можно и после удаления места: тогда видимость не сверяется с местом
--   (запись и так никому, кроме автора, не видна);
-- - delete_checkin удаляет отчёт целиком: фото, уловы и сам чекин.

create or replace function private.catches_before_write() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  ch public.checkins;
  pl public.places;
begin
  if tg_op = 'INSERT' then
    if private.is_client_request() then
      new.owner_id := auth.uid();
    end if;
    new.created_at := now();
  else
    new.owner_id := old.owner_id;
    new.created_at := old.created_at;
    new.checkin_id := old.checkin_id;
  end if;

  if new.owner_id is null then
    raise exception 'auth required' using errcode = '28000';
  end if;

  -- Удалить свой улов можно всегда.
  if tg_op = 'UPDATE' and new.deleted_at is not null then
    new.updated_at := now();
    return new;
  end if;

  -- Улов в чекине: чекин должен быть своим, место берём из чекина. Новый улов — только в живой
  -- чекин; правка улова удалённого чекина не мешает.
  if new.checkin_id is not null then
    select * into ch from public.checkins where id = new.checkin_id;
    if not found or ch.owner_id <> new.owner_id
       or (tg_op = 'INSERT' and ch.deleted_at is not null) then
      raise exception 'checkin not found' using errcode = 'P0002';
    end if;
    new.place_id := ch.place_id;
  end if;

  -- Улов в месте: при создании место должно быть видно автору; улов не видимее места.
  if new.place_id is not null then
    select * into pl from public.places where id = new.place_id;
    if not found
       or pl.deleted_at is not null
       or (pl.status <> 'published' and pl.owner_id <> new.owner_id)
       or not private.can_view(new.owner_id, pl.owner_id, pl.visibility) then
      if tg_op = 'INSERT' then
        raise exception 'place not found' using errcode = 'P0002';
      end if;
    else
      if pl.visibility = 'private' then
        new.visibility := 'private';
      elsif pl.visibility = 'friends' and new.visibility = 'public' then
        new.visibility := 'friends';
      end if;
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create or replace function private.checkins_before_write() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  pl public.places;
  place_ok boolean;
begin
  if tg_op = 'INSERT' then
    if private.is_client_request() then
      new.owner_id := auth.uid();
    end if;
    new.created_at := now();
  else
    new.owner_id := old.owner_id;
    new.created_at := old.created_at;
    new.place_id := old.place_id;
  end if;

  if new.owner_id is null then
    raise exception 'auth required' using errcode = '28000';
  end if;

  -- Удалить свой отчёт можно всегда — даже если место уже удалено или скрыто.
  if tg_op = 'UPDATE' and new.deleted_at is not null then
    new.verified := old.verified;
    new.updated_at := now();
    return new;
  end if;

  select * into pl from public.places where id = new.place_id;
  place_ok := found
     and pl.deleted_at is null
     and (pl.status = 'published' or pl.owner_id = new.owner_id)
     and private.can_view(new.owner_id, pl.owner_id, pl.visibility);
  if not place_ok and tg_op = 'INSERT' then
    raise exception 'place not found' using errcode = 'P0002';
  end if;

  -- Чекин не может быть видимее места.
  if place_ok then
    if pl.visibility = 'private' then
      new.visibility := 'private';
    elsif pl.visibility = 'friends' and new.visibility = 'public' then
      new.visibility := 'friends';
    end if;
  end if;

  -- Время из будущего — это спешащие часы телефона.
  if new.at > now() + interval '5 minutes' then
    new.at := now();
  end if;

  -- Точки сравниваем как байты: операторы PostGIS при пустом search_path не находятся.
  if tg_op = 'UPDATE'
     and new.at = old.at
     and extensions.st_asewkb(new.geom) is not distinct from extensions.st_asewkb(old.geom) then
    new.verified := old.verified;
  elsif tg_op = 'UPDATE' then
    -- Точку или время поменяли задним числом — подтверждения больше нет.
    new.verified := false;
  else
    -- Подтверждён, если телефон был рядом с местом и чекин получен не позже 72 часов.
    new.verified := new.geom is not null
      and new.at > now() - private.checkin_verify_window()
      and extensions.st_dwithin(
            new.geom::extensions.geography,
            pl.geom::extensions.geography,
            private.checkin_radius_m());
  end if;

  new.updated_at := now();
  return new;
end;
$$;

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

  -- Удалить своё фото можно всегда — даже если чекин, улов или отзыв уже удалены.
  if tg_op = 'UPDATE' and new.deleted_at is not null then
    new.updated_at := now();
    return new;
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

-- Удалить свой отчёт целиком: фото, уловы отчёта и сам чекин. Повторное удаление — P0002.
create function public.delete_checkin(p_checkin uuid) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not exists (select 1 from public.checkins c
                  where c.id = p_checkin and c.owner_id = me and c.deleted_at is null) then
    raise exception 'checkin not found' using errcode = 'P0002';
  end if;
  update public.media set deleted_at = now()
   where checkin_id = p_checkin and owner_id = me and deleted_at is null;
  update public.catches set deleted_at = now()
   where checkin_id = p_checkin and owner_id = me and deleted_at is null;
  update public.checkins set deleted_at = now()
   where id = p_checkin and owner_id = me;
end;
$$;

revoke execute on function public.delete_checkin(uuid) from public, anon;
grant execute on function public.delete_checkin(uuid) to authenticated;
