-- Смотритель и рекорды места (план: docs/02-plan/05-cross-cutting.md, «Геймификация» —
-- «Смотритель места» и «Рекорды места», релиз 1.1; спецификация — docs/04-beta/M22-place-stewards.md).
--
-- Смотритель — у кого больше всего подтверждённых отчётов в месте за 60 дней (аналог «мэра» из
-- Swarm), от трёх. При равенстве — кто начал раньше: смотрителя нужно обойти, а не догнать.
-- Рекорды — самый тяжёлый улов каждого вида в месте с фото из подтверждённого отчёта.
--
-- Приватность: считаются только публичные подтверждённые отчёты (и публичные уловы с открытым
-- размером) в публичном опубликованном месте — иначе статус выдал бы чужие визиты. Заблокированным
-- друг друга не показываем.

create index if not exists checkins_place_at_idx on public.checkins (place_id, at) where deleted_at is null;

create function private.steward_window() returns interval
language sql immutable
set search_path = ''
as $$ select interval '60 days' $$;

create function private.steward_min_checkins() returns integer
language sql immutable
set search_path = ''
as $$ select 3 $$;

-- Смотритель места (без учёта зрителя): кто и сколько отчётов за 60 дней.
create function private.place_steward_id(p_place uuid)
returns table (user_id uuid, checkins integer, since timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select c.owner_id, count(*)::integer, min(c.at)
    from public.checkins c
   where c.place_id = p_place
     and c.deleted_at is null
     and c.verified
     and c.visibility = 'public'
     and c.at > now() - private.steward_window()
   group by c.owner_id
  having count(*) >= private.steward_min_checkins()
   order by count(*) desc, min(c.at), c.owner_id
   limit 1;
$$;

-- Смотритель места для зрителя: пусто, если место закрыто, смотрителя нет или он заблокирован.
create function public.place_steward(p_place uuid)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_path text,
  checkins integer,
  since timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.user_id, p.username, p.display_name, p.avatar_path, s.checkins, s.since
    from private.place_steward_id(p_place) s
    join public.profiles p on p.id = s.user_id
   where private.is_open_place(p_place, auth.uid())
     and (auth.uid() is null or not private.is_blocked(auth.uid(), s.user_id));
$$;

-- Рекорды места: по каждому виду — самый тяжёлый улов с фото (при равном весе — кто раньше).
create function public.place_records(p_place uuid)
returns table (
  species_id text,
  weight_g integer,
  length_mm integer,
  caught_at timestamptz,
  catch_id uuid,
  author_id uuid,
  author_username text,
  author_display_name text,
  photo_path text,
  photo_thumb_path text
)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct on (k.species_id)
         k.species_id, k.weight_g, k.length_mm, c.at, k.id,
         k.owner_id, pr.username, pr.display_name,
         m.storage_path, m.owner_id::text || '/' || m.id::text || '_thumb.jpg'
    from public.catches k
    join public.checkins c on c.id = k.checkin_id
    join public.profiles pr on pr.id = k.owner_id
    cross join lateral (
      select m.id, m.owner_id, m.storage_path
        from public.media m
       where m.catch_id = k.id and m.deleted_at is null
       order by m.created_at, m.id
       limit 1
    ) m
   where c.place_id = p_place
     and private.is_open_place(p_place, auth.uid())
     and k.deleted_at is null
     and c.deleted_at is null
     and c.verified
     and c.visibility = 'public'
     and k.visibility = 'public'
     and not k.hide_size
     and k.weight_g is not null
     and (auth.uid() is null or not private.is_blocked(auth.uid(), k.owner_id))
   order by k.species_id, k.weight_g desc, c.at, k.id;
$$;

revoke execute on function
  private.steward_window(),
  private.steward_min_checkins(),
  private.place_steward_id(uuid)
from public, anon, authenticated;

revoke execute on function
  public.place_steward(uuid),
  public.place_records(uuid)
from public;

grant execute on function
  public.place_steward(uuid),
  public.place_records(uuid)
to anon, authenticated;
