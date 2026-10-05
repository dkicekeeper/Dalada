-- Упоминания @username в обсуждениях (план: docs/02-plan/03-places.md, 3.6; уведомления —
-- «Ответ в треде, где я автор или подписан; @упоминание»).
--
-- Упомянутый в вопросе или ответе получает уведомление «Вас упомянули», даже если не подписан на
-- обсуждение. Не получает: автор сообщения, кто обсуждение не видит, кто от него отписался (колокольчик),
-- и при выключенных «Ответах в обсуждениях». Не больше 10 упоминаний в одном сообщении.

-- Кого упомянули: @username в начале или после пробела и знаков — не внутри почты или слова
-- (буквы любого алфавита — [[:alnum:]]).
create function private.mentioned_users(p_text text) returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select distinct p.id
    from regexp_matches(coalesce(p_text, ''), '(?:^|[^[:alnum:]_.@])@([a-z0-9_.]{3,30})', 'gi') as m(parts)
    join public.profiles p on p.username = rtrim(lower(m.parts[1]), '.')
   limit 10;
$$;

-- Ответ: подписанным (автор, отвечавшие, подписавшиеся), автору цитаты и упомянутым — кроме
-- отписавшихся и тех, кто обсуждение не видит. У упомянутых в уведомлении — «Вас упомянули».
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
  is_mention boolean;
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

  for recipient, is_mention in
    select u.user_id, bool_or(u.mention)
      from (
        select t.owner_id as user_id, false as mention
        union all
        select p.owner_id, false from public.thread_posts p where p.thread_id = t.id and p.deleted_at is null
        union all
        select s.user_id, false from public.thread_subscriptions s where s.thread_id = t.id and s.subscribed
        union all
        select quoted_owner, false where quoted_owner is not null
        union all
        select m.id, true from private.mentioned_users(new.body) as m(id)
      ) u
     where u.user_id <> new.owner_id
       and not exists (select 1 from public.thread_subscriptions s
                        where s.thread_id = t.id and s.user_id = u.user_id and not s.subscribed)
       and private.can_view_thread(u.user_id, t)
     group by u.user_id
     order by bool_or(u.mention) desc, u.user_id
     limit private.thread_push_limit()
  loop
    perform private.push_enqueue(recipient, new.owner_id, 'thread_reply',
      case when is_mention then payload || '{"mention": true}'::jsonb else payload end);
  end loop;
  return null;
end;
$$;

-- Вопрос: упомянутым в нём (остальные ещё не подписаны — кроме автора).
create function private.threads_mention_push() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient uuid;
  payload jsonb := jsonb_build_object(
    'thread_id', new.id,
    'title', new.title,
    'snippet', left(regexp_replace(new.body, '\s+', ' ', 'g'), 120),
    'mention', true
  );
begin
  for recipient in
    select m.id from private.mentioned_users(new.title || ' ' || new.body) as m(id)
     where m.id <> new.owner_id
       and private.can_view_thread(m.id, new)
  loop
    perform private.push_enqueue(recipient, new.owner_id, 'thread_reply', payload);
  end loop;
  return null;
end;
$$;

revoke execute on function
  private.mentioned_users(text),
  private.threads_mention_push()
from public, anon, authenticated;

create trigger threads_mention_push after insert on public.threads
  for each row execute function private.threads_mention_push();
