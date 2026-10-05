-- Совместные сборы (план: docs/02-plan/04-lifehacks.md, 4.3 — «поделиться чеклистом с участниками
-- поездки, каждый отмечает, кто что берёт»; спецификация — docs/04-beta/M23-shared-packing.md).
--
-- Свои чеклисты синхронизируются целиком («последняя правка побеждает») — для общей правки это не
-- годится: отметки людей затирали бы друг друга. Поэтому общие сборы — отдельная копия, и каждый
-- пункт — своя строка: «кто берёт» и «собрано» меняются по одному пункту.
--
-- Кто: автор и приглашённые им друзья (не больше 20). Видят и правят сборы только они. Пункты
-- добавляет любой участник; убрать пункт — автор или добавивший. Участник может выйти, автор —
-- удалить сборы целиком. Таблицы клиенту закрыты: всё через функции ниже.

create table public.shared_packings (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  title       text not null check (char_length(btrim(title)) between 1 and 100),
  trip_date   date,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.shared_packing_members (
  packing_id  uuid not null references public.shared_packings (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  primary key (packing_id, user_id)
);

create index shared_packing_members_user_idx on public.shared_packing_members (user_id);

create table public.shared_packing_items (
  id          uuid primary key default gen_random_uuid(),
  packing_id  uuid not null references public.shared_packings (id) on delete cascade,
  title       text not null check (char_length(btrim(title)) between 1 and 200),
  category    text check (char_length(category) <= 40),
  position    integer not null default 0,
  -- Кто берёт (null — пока никто) и собрано ли.
  assignee_id uuid references public.profiles (id) on delete set null,
  done        boolean not null default false,
  created_by  uuid references public.profiles (id) on delete set null,
  updated_at  timestamptz not null default now()
);

create index shared_packing_items_packing_idx on public.shared_packing_items (packing_id, position);

alter table public.shared_packings enable row level security;
alter table public.shared_packing_members enable row level security;
alter table public.shared_packing_items enable row level security;
revoke all on table public.shared_packings, public.shared_packing_members, public.shared_packing_items
  from anon, authenticated;

create function private.shared_packing_members_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 20 $$;

create function private.shared_packing_items_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 300 $$;

-- Участник сборов: автор или приглашённый (и не заблокирован автором и наоборот).
create function private.is_packing_member(p_packing uuid, p_user uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user is not null and exists (
    select 1 from public.shared_packings s
     where s.id = p_packing
       and (s.owner_id = p_user
            or (exists (select 1 from public.shared_packing_members m
                         where m.packing_id = s.id and m.user_id = p_user)
                and not private.is_blocked(p_user, s.owner_id)))
  );
$$;

create function private.require_packing_member(p_packing uuid) returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  if not private.is_packing_member(p_packing, auth.uid()) then
    raise exception 'packing not found' using errcode = 'P0002';
  end if;
end;
$$;

create function private.touch_packing(p_packing uuid) returns void
language sql
security definer
set search_path = ''
as $$
  update public.shared_packings set updated_at = now() where id = p_packing;
$$;

-- Поделиться сборами: копия пунктов (как в чеклисте: title, category) и друзья-участники (не друзья
-- отбрасываются; без друзей — 22023). Возвращает id общих сборов.
create function public.share_packing(
  p_title text,
  p_trip_date date,
  p_items jsonb,
  p_members uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  packing uuid;
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) > private.shared_packing_items_limit() then
    raise exception 'invalid items' using errcode = '22023';
  end if;
  if coalesce(cardinality(p_members), 0) > private.shared_packing_members_limit() then
    raise exception 'too many members' using errcode = '54000';
  end if;

  insert into public.shared_packings (owner_id, title, trip_date)
  values (me, btrim(p_title), p_trip_date)
  returning id into packing;

  insert into public.shared_packing_members (packing_id, user_id)
  select distinct packing, m
    from unnest(p_members) as m
   where m <> me and private.are_friends(me, m) and not private.is_blocked(me, m);
  if not found then
    raise exception 'no friends among members' using errcode = '22023';
  end if;

  insert into public.shared_packing_items (packing_id, title, category, position, created_by)
  select packing, left(btrim(e.value ->> 'title'), 200), nullif(left(e.value ->> 'category', 40), ''),
         e.ordinality::integer, me
    from jsonb_array_elements(p_items) with ordinality as e(value, ordinality)
   where jsonb_typeof(e.value) = 'object'
     and char_length(btrim(coalesce(e.value ->> 'title', ''))) between 1 and 200;
  return packing;
end;
$$;

-- Мои общие сборы: свои и куда пригласили; прогресс.
create function public.my_shared_packings()
returns table (
  id uuid,
  owner_id uuid,
  owner_username text,
  owner_display_name text,
  title text,
  trip_date date,
  members_count integer,
  items_count integer,
  done_count integer,
  is_own boolean,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, s.owner_id, p.username, p.display_name, s.title, s.trip_date,
         (select count(*)::integer from public.shared_packing_members m where m.packing_id = s.id),
         (select count(*)::integer from public.shared_packing_items i where i.packing_id = s.id),
         (select count(*)::integer from public.shared_packing_items i where i.packing_id = s.id and i.done),
         s.owner_id = auth.uid(),
         s.updated_at
    from public.shared_packings s
    join public.profiles p on p.id = s.owner_id
   where private.is_packing_member(s.id, auth.uid())
   order by s.trip_date nulls last, s.updated_at desc;
$$;

-- Участники сборов (автор первым).
create function public.shared_packing_members(p_packing uuid)
returns table (user_id uuid, username text, display_name text, avatar_path text, is_owner boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_packing_member(p_packing);
  return query
    select p.id, p.username, p.display_name, p.avatar_path, p.id = s.owner_id
      from public.shared_packings s
      join public.profiles p
        on p.id = s.owner_id
        or p.id in (select m.user_id from public.shared_packing_members m where m.packing_id = s.id)
     where s.id = p_packing
     order by p.id = s.owner_id desc, p.username;
end;
$$;

-- Пункты сборов.
create function public.shared_packing_items(p_packing uuid)
returns table (
  id uuid,
  title text,
  category text,
  item_position integer,
  assignee_id uuid,
  done boolean,
  created_by uuid,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_packing_member(p_packing);
  return query
    select i.id, i.title, i.category, i.position, i.assignee_id, i.done, i.created_by, i.updated_at
      from public.shared_packing_items i
     where i.packing_id = p_packing
     order by i.position, i.id;
end;
$$;

-- «Возьму я» (p_take = true) или «не беру» (false). Снять чужую отметку может только автор сборов.
create function public.take_packing_item(p_item uuid, p_take boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  it public.shared_packing_items;
  owner uuid;
begin
  select * into it from public.shared_packing_items where id = p_item;
  if not found then
    raise exception 'item not found' using errcode = 'P0002';
  end if;
  perform private.require_packing_member(it.packing_id);
  select s.owner_id into owner from public.shared_packings s where s.id = it.packing_id;
  if p_take then
    update public.shared_packing_items set assignee_id = auth.uid(), updated_at = now() where id = p_item;
  elsif it.assignee_id is not null and it.assignee_id <> auth.uid() and owner <> auth.uid() then
    raise exception 'not yours' using errcode = '42501';
  else
    update public.shared_packing_items set assignee_id = null, updated_at = now() where id = p_item;
  end if;
  perform private.touch_packing(it.packing_id);
end;
$$;

-- «Собрано» — любой участник.
create function public.set_packing_item_done(p_item uuid, p_done boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  it public.shared_packing_items;
begin
  select * into it from public.shared_packing_items where id = p_item;
  if not found then
    raise exception 'item not found' using errcode = 'P0002';
  end if;
  perform private.require_packing_member(it.packing_id);
  update public.shared_packing_items set done = coalesce(p_done, false), updated_at = now() where id = p_item;
  perform private.touch_packing(it.packing_id);
end;
$$;

-- Добавить пункт (любой участник). Возвращает id.
create function public.add_packing_item(p_packing uuid, p_title text, p_category text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  item uuid;
begin
  perform private.require_packing_member(p_packing);
  if char_length(btrim(coalesce(p_title, ''))) not between 1 and 200 then
    raise exception 'invalid title' using errcode = '22023';
  end if;
  if (select count(*) from public.shared_packing_items where packing_id = p_packing)
     >= private.shared_packing_items_limit() then
    raise exception 'too many items' using errcode = '54000';
  end if;
  insert into public.shared_packing_items (packing_id, title, category, position, created_by)
  values (
    p_packing, btrim(p_title), nullif(left(p_category, 40), ''),
    coalesce((select max(position) + 1 from public.shared_packing_items where packing_id = p_packing), 1),
    auth.uid()
  )
  returning id into item;
  perform private.touch_packing(p_packing);
  return item;
end;
$$;

-- Убрать пункт: автор сборов или кто его добавил.
create function public.delete_packing_item(p_item uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  it public.shared_packing_items;
begin
  select * into it from public.shared_packing_items where id = p_item;
  if not found then
    raise exception 'item not found' using errcode = 'P0002';
  end if;
  perform private.require_packing_member(it.packing_id);
  if it.created_by is distinct from auth.uid()
     and (select s.owner_id from public.shared_packings s where s.id = it.packing_id) <> auth.uid() then
    raise exception 'not yours' using errcode = '42501';
  end if;
  delete from public.shared_packing_items where id = p_item;
  perform private.touch_packing(it.packing_id);
end;
$$;

-- Выйти из сборов (участник) или удалить их целиком (автор). Взятые вышедшим пункты — снова ничьи.
create function public.leave_shared_packing(p_packing uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_packing_member(p_packing);
  if (select s.owner_id from public.shared_packings s where s.id = p_packing) = auth.uid() then
    delete from public.shared_packings where id = p_packing;
  else
    delete from public.shared_packing_members where packing_id = p_packing and user_id = auth.uid();
    update public.shared_packing_items set assignee_id = null
     where packing_id = p_packing and assignee_id = auth.uid();
    perform private.touch_packing(p_packing);
  end if;
end;
$$;

revoke execute on function
  private.shared_packing_members_limit(),
  private.shared_packing_items_limit(),
  private.is_packing_member(uuid, uuid),
  private.require_packing_member(uuid),
  private.touch_packing(uuid)
from public, anon, authenticated;

revoke execute on function
  public.share_packing(text, date, jsonb, uuid[]),
  public.my_shared_packings(),
  public.shared_packing_members(uuid),
  public.shared_packing_items(uuid),
  public.take_packing_item(uuid, boolean),
  public.set_packing_item_done(uuid, boolean),
  public.add_packing_item(uuid, text, text),
  public.delete_packing_item(uuid),
  public.leave_shared_packing(uuid)
from public, anon;

grant execute on function
  public.share_packing(text, date, jsonb, uuid[]),
  public.my_shared_packings(),
  public.shared_packing_members(uuid),
  public.shared_packing_items(uuid),
  public.take_packing_item(uuid, boolean),
  public.set_packing_item_done(uuid, boolean),
  public.add_packing_item(uuid, text, text),
  public.delete_packing_item(uuid),
  public.leave_shared_packing(uuid)
to authenticated;
