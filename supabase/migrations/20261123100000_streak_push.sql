-- «Серия под угрозой» (спецификация — docs/04-beta/M28-streaks.md, «Пуш „Серия под угрозой“»): в субботу утром тем, у
-- кого серия от двух недель, а на этой неделе ещё не было ни поездки, ни отчёта и неделя не
-- заморожена (зима, запрет в ваших местах). Одно в неделю. Настройка notify_streak.

alter table public.profiles add column notify_streak boolean not null default true;
grant update (notify_streak) on table public.profiles to authenticated;

create or replace function private.push_allowed(p_user uuid, p_kind public.push_kind) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case p_kind
      when 'thread_reply' then p.notify_replies
      when 'friend_request' then p.notify_friend_requests
      when 'friend_accept' then p.notify_friend_requests
      when 'comment' then p.notify_comments
      when 'friend_post' then p.notify_friend_posts
      when 'ban_start' then p.notify_bans
      when 'ban_end' then p.notify_bans
      when 'place_activity' then p.notify_place_activity
      when 'trip_tag' then p.notify_trip_tags
      when 'reaction' then p.notify_reactions
      when 'live_share' then p.notify_live_share
      when 'packing_invite' then p.notify_trip_tags
      when 'steward' then p.notify_steward
      when 'streak' then p.notify_streak
      else true
    end
      from public.profiles p
     where p.id = p_user
  ), false);
$$;

-- Серия человека (как my_streak, но для любого — для рассылки).
create function private.user_streak(p_user uuid)
returns table (current_weeks integer, best_weeks integer, this_week_done boolean, freeze_reason text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  this_week date := date_trunc('week', now() at time zone 'Asia/Almaty')::date;
  active date[];
  frozen date[];
begin
  select array_agg(distinct x.week) into active
    from (
      select date_trunc('week', t.started_at at time zone 'Asia/Almaty')::date as week
        from public.trips t
       where t.owner_id = p_user and t.deleted_at is null
      union all
      select date_trunc('week', c.at at time zone 'Asia/Almaty')::date
        from public.checkins c
       where c.owner_id = p_user and c.deleted_at is null
    ) x
   where x.week <= this_week;

  select array_agg(w::date) into frozen
    from generate_series((select min(a) from unnest(active) a), this_week - 7, interval '7 days') w
   where not (w::date = any (active))
     and private.streak_freeze(p_user, w::date) is not null;

  return query
    select s.current_weeks, s.best_weeks, coalesce(this_week = any (active), false),
           private.streak_freeze(p_user, this_week)
      from private.streak_count(active, frozen, this_week) s;
end;
$$;

create or replace function public.my_streak()
returns table (current_weeks integer, best_weeks integer, this_week_done boolean, freeze_reason text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  return query select * from private.user_streak(auth.uid());
end;
$$;

-- Рассылка: у кого есть телефон и выезд за последние 3 недели. Возвращает, скольким поставили.
create function private.streak_reminders() returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  u uuid;
  s record;
  sent integer := 0;
  week_start timestamptz := date_trunc('week', now() at time zone 'Asia/Almaty') at time zone 'Asia/Almaty';
begin
  for u in
    select distinct d.user_id
      from public.devices d
     where exists (
       select 1 from public.trips t
        where t.owner_id = d.user_id and t.deleted_at is null and t.started_at > now() - interval '21 days')
        or exists (
       select 1 from public.checkins c
        where c.owner_id = d.user_id and c.deleted_at is null and c.at > now() - interval '21 days')
  loop
    select * into s from private.user_streak(u);
    if s.current_weeks >= 2 and not s.this_week_done and s.freeze_reason is null
       and not exists (
         select 1 from private.push_outbox o
          where o.user_id = u and o.kind = 'streak' and o.created_at >= week_start)
    then
      perform private.push_enqueue(u, null, 'streak', jsonb_build_object('weeks', s.current_weeks));
      sent := sent + 1;
    end if;
  end loop;
  return sent;
end;
$$;

revoke execute on function private.user_streak(uuid), private.streak_reminders() from public, anon, authenticated;

-- Суббота, 10:00 по Алматы (05:00 UTC).
select cron.schedule('streak-reminders', '0 5 * * 6', 'select private.streak_reminders()');
