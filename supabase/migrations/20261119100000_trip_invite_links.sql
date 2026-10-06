-- Приглашение в поездку по ссылке (план: docs/02-plan/05-cross-cutting.md — «Отметка друзей: отмеченный
-- в поездке получает приглашение, даже если его нет в приложении», 1.1; спецификация —
-- docs/04-beta/M30-trip-invite-links.md).
--
-- Автор своей поездки берёт ссылку и отправляет кому угодно (в мессенджер). Кто откроет её в
-- приложении после входа, становится участником (принял) — и автору уходит запрос в друзья. Ссылка
-- живёт 30 дней; одна на поездку, пока не истекла. По ссылке видно только название поездки и имя
-- автора (страница в браузере); трек и остальное — уже в приложении, как участнику.

create table public.trip_invite_links (
  token      text primary key,
  trip_id    uuid not null references public.trips (id) on delete cascade,
  owner_id   uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 days'
);

create index trip_invite_links_trip_idx on public.trip_invite_links (trip_id);

alter table public.trip_invite_links enable row level security;
revoke all on table public.trip_invite_links from anon, authenticated;

-- Ссылка-приглашение в свою поездку: действующая или новая.
create function public.trip_invite_link(p_trip uuid) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  existing text;
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  if not exists (select 1 from public.trips where id = p_trip and owner_id = me and deleted_at is null) then
    raise exception 'trip not found' using errcode = 'P0002';
  end if;
  select l.token into existing
    from public.trip_invite_links l
   where l.trip_id = p_trip and l.expires_at > now() + interval '1 day'
   order by l.expires_at desc
   limit 1;
  if existing is not null then
    return existing;
  end if;
  existing := replace(gen_random_uuid()::text, '-', '');
  insert into public.trip_invite_links (token, trip_id, owner_id) values (existing, p_trip, me);
  return existing;
end;
$$;

-- Что показать по ссылке (и гостю в браузере): поездка и автор. Истёкшая — пусто.
create function public.web_trip_invite(p_token text)
returns table (trip_id uuid, title text, activity public.trip_activity, started_at timestamptz,
               owner_username text, owner_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.title, t.activity, t.started_at, p.username, p.display_name
    from public.trip_invite_links l
    join public.trips t on t.id = l.trip_id and t.deleted_at is null
    join public.profiles p on p.id = l.owner_id
   where l.token = p_token
     and l.expires_at > now()
     and (auth.uid() is null or not private.is_blocked(auth.uid(), l.owner_id));
$$;

-- Принять приглашение по ссылке: участник (принял) и запрос в друзья автору. Возвращает поездку.
create function public.accept_trip_invite_link(p_token text) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  link public.trip_invite_links;
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  select l.* into link
    from public.trip_invite_links l
    join public.trips t on t.id = l.trip_id and t.deleted_at is null
   where l.token = p_token and l.expires_at > now();
  if link.token is null then
    raise exception 'invitation not found' using errcode = 'P0002';
  end if;
  if link.owner_id = me then
    return link.trip_id;
  end if;
  if private.is_blocked(me, link.owner_id) then
    raise exception 'invitation not found' using errcode = 'P0002';
  end if;
  if not exists (
    select 1 from public.trip_participants tp
     where tp.trip_id = link.trip_id and tp.user_id = me and tp.status in ('pending', 'accepted')
  ) and (
    select count(*) from public.trip_participants tp
     where tp.trip_id = link.trip_id and tp.status in ('pending', 'accepted')
  ) >= private.trip_participants_limit() then
    raise exception 'too many participants' using errcode = '54000';
  end if;

  insert into public.trip_participants (trip_id, user_id, status, responded_at)
  values (link.trip_id, me, 'accepted', now())
  on conflict (trip_id, user_id) do update set status = 'accepted', responded_at = now();

  perform public.send_friend_request(link.owner_id);
  return link.trip_id;
end;
$$;

revoke execute on function public.trip_invite_link(uuid), public.web_trip_invite(text),
  public.accept_trip_invite_link(text) from public;
grant execute on function public.trip_invite_link(uuid), public.accept_trip_invite_link(text) to authenticated;
grant execute on function public.web_trip_invite(text) to anon, authenticated;
