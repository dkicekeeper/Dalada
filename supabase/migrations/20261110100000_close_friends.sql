-- Видимость «Близкие» (план: docs/02-plan/README.md, релиз 1.1 — «выбранные друзья»; спецификация —
-- docs/04-beta/M21-close-friends.md).
--
-- Один список на человека — «близкие друзья» (как в Instagram): места, отчёты, уловы и поездки с
-- видимостью `close_friends` видят только друзья из этого списка. Список видит только его владелец;
-- люди не узнают, что в нём. В список — только друзья (иначе 22023), не больше 200; разрыв дружбы
-- убирает из списка.
--
-- Решает по-прежнему одна функция — private.can_view: всё, что ей пользуется (отчёты, лента, трек,
-- фото, пуши друзьям), учитывает «Близких» само. Отчёт и улов не видимее места: в месте «Близкие»
-- «все» и «друзья» опускаются до «Близких» (триггеры *_visibility_close_friends, после основных).

create table public.close_friends (
  owner_id   uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  friend_id  uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  check (owner_id <> friend_id)
);

create index close_friends_friend_idx on public.close_friends (friend_id);

alter table public.close_friends enable row level security;
revoke all on table public.close_friends from anon, authenticated;
grant select, delete on table public.close_friends to authenticated;
grant insert (friend_id) on table public.close_friends to authenticated;

create policy "close_friends: свой список" on public.close_friends
  for select to authenticated using (owner_id = (select auth.uid()));

create policy "close_friends: добавлять в свой" on public.close_friends
  for insert to authenticated with check (owner_id = (select auth.uid()));

create policy "close_friends: убирать из своего" on public.close_friends
  for delete to authenticated using (owner_id = (select auth.uid()));

create function private.close_friends_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 200 $$;

create function private.close_friends_before_insert() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.is_client_request() then
    new.owner_id := auth.uid();
  end if;
  if new.owner_id is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  if not private.are_friends(new.owner_id, new.friend_id) then
    raise exception 'not a friend' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext('close_friends:' || new.owner_id::text));
  if (select count(*) from public.close_friends where owner_id = new.owner_id) >= private.close_friends_limit() then
    raise exception 'too many close friends' using errcode = '54000';
  end if;
  new.created_at := now();
  return new;
end;
$$;

create trigger close_friends_before_insert before insert on public.close_friends
  for each row execute function private.close_friends_before_insert();

-- Дружба разорвана (или блокировка) — из списка «Близкие» тоже.
create function private.friendships_after_delete() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.close_friends where owner_id = old.user_id and friend_id = old.friend_id;
  return null;
end;
$$;

create trigger friendships_after_delete after delete on public.friendships
  for each row execute function private.friendships_after_delete();

-- Единственная функция, которая решает «видит ли viewer объект owner с видимостью vis».
-- viewer = null — гость.
create or replace function private.can_view(viewer uuid, owner uuid, vis public.visibility) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when viewer is not null and viewer = owner then true
    when viewer is not null and private.is_blocked(viewer, owner) then false
    when vis = 'public' then true
    when vis = 'friends' then viewer is not null and private.are_friends(viewer, owner)
    when vis = 'close_friends' then viewer is not null and private.are_friends(viewer, owner)
      and exists (select 1 from public.close_friends c where c.owner_id = owner and c.friend_id = viewer)
    else false
  end;
$$;

-- Отчёт и улов не видимее места: в месте «Близкие» — не больше «Близких». Место «только я» и
-- «друзья» уже опускают видимость основные триггеры (checkins_before_write, catches_before_write).
create function private.visibility_close_friends_clamp() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.place_id is not null
     and new.visibility in ('public', 'friends')
     and exists (
       select 1 from public.places p
        where p.id = new.place_id and p.deleted_at is null and p.visibility = 'close_friends'
     ) then
    new.visibility := 'close_friends';
  end if;
  return new;
end;
$$;

create trigger checkins_visibility_close_friends before insert or update on public.checkins
  for each row execute function private.visibility_close_friends_clamp();

create trigger catches_visibility_close_friends before insert or update on public.catches
  for each row execute function private.visibility_close_friends_clamp();

revoke execute on function
  private.close_friends_limit(),
  private.close_friends_before_insert(),
  private.friendships_after_delete(),
  private.visibility_close_friends_clamp()
from public, anon, authenticated;
