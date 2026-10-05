-- Подписка на обсуждение (план: docs/02-plan/03-places.md, 3.6): об ответах узнают автор
-- обсуждения, все, кто в нём отвечал, и те, кто подписался сам; любой может отписаться.
--
-- По умолчанию подписаны автор и отвечавшие — строки для них не нужны. В thread_subscriptions
-- хранится только явный выбор: subscribed = true (подписался, не отвечая) или false (отписался —
-- уведомлений из обсуждения больше нет, даже на цитату своего ответа).

create table public.thread_subscriptions (
  thread_id  uuid not null references public.threads (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  subscribed boolean not null,
  updated_at timestamptz not null default now(),
  primary key (thread_id, user_id)
);

create index thread_subscriptions_user_idx on public.thread_subscriptions (user_id);

alter table public.thread_subscriptions enable row level security;
revoke all on public.thread_subscriptions from anon, authenticated;

-- Сколько уведомлений об одном ответе самое большее.
create function private.thread_push_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 200 $$;

-- Видит ли человек обсуждение: место открыто и он не заблокирован с автором обсуждения.
create function private.can_view_thread(p_user uuid, p_thread public.threads) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_thread.deleted_at is null
     and private.is_open_place(p_thread.place_id, p_user)
     and (p_user is null or not private.is_blocked(p_user, p_thread.owner_id));
$$;

-- Подписан ли: явный выбор, иначе — автор или отвечал (не удалённым ответом).
create function private.thread_subscribed(p_user uuid, p_thread public.threads) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select s.subscribed from public.thread_subscriptions s
      where s.thread_id = p_thread.id and s.user_id = p_user),
    p_thread.owner_id = p_user
      or exists (select 1 from public.thread_posts p
                  where p.thread_id = p_thread.id and p.owner_id = p_user and p.deleted_at is null)
  );
$$;

-- Подписка зрителя; null — гость или обсуждение не видно.
create function public.thread_subscription(p_thread uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.thread_subscribed(auth.uid(), t)
    from public.threads t
   where t.id = p_thread
     and auth.uid() is not null
     and private.can_view_thread(auth.uid(), t);
$$;

-- Подписаться или отписаться. Возвращает новое состояние.
create function public.set_thread_subscription(p_thread uuid, p_subscribed boolean) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  t public.threads;
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select * into t from public.threads where id = p_thread;
  if not found or not private.can_view_thread(me, t) then
    raise exception 'thread not found' using errcode = 'P0002';
  end if;
  insert into public.thread_subscriptions (thread_id, user_id, subscribed)
  values (p_thread, me, coalesce(p_subscribed, false))
  on conflict (thread_id, user_id)
  do update set subscribed = excluded.subscribed, updated_at = now();
  return coalesce(p_subscribed, false);
end;
$$;

revoke execute on function
  public.thread_subscription(uuid),
  public.set_thread_subscription(uuid, boolean),
  private.thread_push_limit(),
  private.can_view_thread(uuid, public.threads),
  private.thread_subscribed(uuid, public.threads)
from public, anon, authenticated;
grant execute on function
  public.thread_subscription(uuid),
  public.set_thread_subscription(uuid, boolean)
to authenticated;

-- Ответ в обсуждении: всем подписанным (автор, отвечавшие, подписавшиеся) и автору процитированного
-- ответа, кроме отписавшихся и тех, кто обсуждение больше не видит. Себе и между заблокированными —
-- нет (push_enqueue).
create or replace function private.thread_posts_push() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.threads;
  quoted_owner uuid;
  payload jsonb;
  recipient uuid;
begin
  select * into t from public.threads where id = new.thread_id;
  if not found or t.deleted_at is not null then
    return null;
  end if;
  payload := jsonb_build_object(
    'thread_id', t.id,
    'title', t.title,
    'snippet', left(regexp_replace(new.body, '\s+', ' ', 'g'), 120)
  );
  if new.quote_post_id is not null then
    select p.owner_id into quoted_owner
      from public.thread_posts p
     where p.id = new.quote_post_id and p.deleted_at is null;
  end if;

  for recipient in
    select u.user_id
      from (
        select t.owner_id as user_id
        union
        select p.owner_id from public.thread_posts p where p.thread_id = t.id and p.deleted_at is null
        union
        select s.user_id from public.thread_subscriptions s where s.thread_id = t.id and s.subscribed
        union
        select quoted_owner where quoted_owner is not null
      ) u
     where u.user_id <> new.owner_id
       and not exists (select 1 from public.thread_subscriptions s
                        where s.thread_id = t.id and s.user_id = u.user_id and not s.subscribed)
       and private.can_view_thread(u.user_id, t)
     order by u.user_id
     limit private.thread_push_limit()
  loop
    perform private.push_enqueue(recipient, new.owner_id, 'thread_reply', payload);
  end loop;
  return null;
end;
$$;
