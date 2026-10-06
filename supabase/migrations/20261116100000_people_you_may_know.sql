-- «Возможно, вы знакомы» (план: docs/02-plan/01-profile.md — «Возможно, вы знакомы: общие друзья, общие
-- места», 1.1; спецификация — docs/04-beta/M27-people-you-may-know.md).
--
-- Кандидаты: друзья моих друзей (сколько общих друзей — без имён) и те, кто за полгода оставлял
-- публичные подтверждённые отчёты в местах, где отмечался я (сколько таких мест). С моей стороны
-- считаются любые мои отчёты — это мои данные; с его стороны — только публичные: иначе подсказка
-- выдала бы чужие визиты. Не показываем: себя, друзей, заблокированных (в любую сторону), тех, с кем
-- уже есть запрос, людей без username и тех, кого я скрыл.

create table public.friend_suggestion_dismissals (
  owner_id   uuid not null references public.profiles (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, user_id)
);

alter table public.friend_suggestion_dismissals enable row level security;
revoke all on table public.friend_suggestion_dismissals from anon, authenticated;

create function private.suggestion_window() returns interval
language sql immutable
set search_path = ''
as $$ select interval '180 days' $$;

create function public.people_you_may_know(p_limit integer default 10)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_path text,
  mutual_friends integer,
  shared_places integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with mutual as (
    select f2.friend_id as user_id, count(*)::integer as n
      from public.friendships f1
      join public.friendships f2 on f2.user_id = f1.friend_id
     where f1.user_id = auth.uid()
     group by f2.friend_id
  ),
  my_places as (
    select distinct c.place_id
      from public.checkins c
     where c.owner_id = auth.uid()
       and c.deleted_at is null
       and c.at > now() - private.suggestion_window()
  ),
  shared as (
    select c.owner_id as user_id, count(distinct c.place_id)::integer as n
      from public.checkins c
      join my_places m on m.place_id = c.place_id
     where c.deleted_at is null
       and c.verified
       and c.visibility = 'public'
       and c.at > now() - private.suggestion_window()
       and private.is_open_place(c.place_id, null)
     group by c.owner_id
  ),
  candidates as (
    select coalesce(m.user_id, s.user_id) as user_id,
           coalesce(m.n, 0) as mutual,
           coalesce(s.n, 0) as places
      from mutual m
      full join shared s on s.user_id = m.user_id
  )
  select p.id, p.username, p.display_name, p.avatar_path, c.mutual, c.places
    from candidates c
    join public.profiles p on p.id = c.user_id
   where auth.uid() is not null
     and c.user_id <> auth.uid()
     and p.username is not null
     and not private.are_friends(auth.uid(), c.user_id)
     and not private.is_blocked(auth.uid(), c.user_id)
     and not exists (
       select 1 from public.friend_requests r
        where r.status = 'pending'
          and ((r.from_user = auth.uid() and r.to_user = c.user_id)
            or (r.from_user = c.user_id and r.to_user = auth.uid())))
     and not exists (
       select 1 from public.friend_suggestion_dismissals d
        where d.owner_id = auth.uid() and d.user_id = c.user_id)
   order by c.mutual * 3 + c.places desc, c.mutual desc, p.username
   limit least(greatest(coalesce(p_limit, 10), 1), 30);
$$;

-- Скрыть человека из подсказок (навсегда; дружбе не мешает).
create function public.dismiss_friend_suggestion(p_user uuid) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  insert into public.friend_suggestion_dismissals (owner_id, user_id)
  select auth.uid(), p_user
   where exists (select 1 from public.profiles where id = p_user) and p_user <> auth.uid()
  on conflict do nothing;
end;
$$;

revoke execute on function public.people_you_may_know(integer), public.dismiss_friend_suggestion(uuid)
  from public, anon;
grant execute on function public.people_you_may_know(integer), public.dismiss_friend_suggestion(uuid)
  to authenticated;
