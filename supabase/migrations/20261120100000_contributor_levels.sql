-- Уровни участника и проверка правок опытными (план: docs/02-plan/05-cross-cutting.md — «Очки вклада»,
-- «Уровни участника: Новичок → Знаток → Эксперт → Хранитель; высокие уровни проверяют правки», 1.1;
-- спецификация — docs/04-beta/M31-contributor-levels.md).
--
-- Очки — за то, что видят все: публичное опубликованное место — 20, фото к публичному отчёту или
-- отзыву — 5, публичный подтверждённый отчёт с условиями — 5, отзыв — 10, принятая правка — 10,
-- ответ в обсуждении с «респектом» — 5. Уровни: Знаток — от 50, Эксперт — от 200, Хранитель — от 500.
--
-- С уровня «Эксперт» можно разбирать чужие правки мест (только «правка полей»; «закрыто»,
-- «не существует», «дубль», «опасно», «не та точка» — по-прежнему редакция): принять или отклонить.
-- Свои правки и правки к своим местам — нельзя. Кто разобрал — в private.suggestion_reviews: видит
-- редакция, автор правки — нет.

create table private.suggestion_reviews (
  suggestion_id uuid primary key references public.place_suggestions (id) on delete cascade,
  reviewer_id   uuid references public.profiles (id) on delete set null,
  accepted      boolean not null,
  decided_at    timestamptz not null default now()
);

alter table private.suggestion_reviews enable row level security;

-- Очки по видам.
create function private.contribution(p_user uuid)
returns table (places integer, photos integer, reports integer, reviews integer, edits integer, helpful integer)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select count(*)::integer from public.places p
      where p.owner_id = p_user and p.deleted_at is null and p.status = 'published' and p.visibility = 'public'),
    (select count(*)::integer from public.media m
      where m.owner_id = p_user and m.deleted_at is null
        and (exists (select 1 from public.checkins c
                      where c.id = m.checkin_id and c.deleted_at is null and c.visibility = 'public')
             or exists (select 1 from public.reviews r where r.id = m.review_id and r.deleted_at is null))),
    (select count(*)::integer from public.checkins c
      where c.owner_id = p_user and c.deleted_at is null and c.verified and c.visibility = 'public'
        and c.conditions is not null and c.conditions <> '{}'::jsonb),
    (select count(*)::integer from public.reviews r where r.owner_id = p_user and r.deleted_at is null),
    (select count(*)::integer from public.place_suggestions s where s.author_id = p_user and s.status = 'accepted'),
    (select count(*)::integer from public.thread_posts tp
      where tp.owner_id = p_user and tp.deleted_at is null
        and exists (select 1 from public.reactions x
                     where x.target_kind = 'post' and x.target_id = tp.id and x.owner_id <> p_user));
$$;

create function private.contribution_points(p_user uuid) returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select c.places * 20 + c.photos * 5 + c.reports * 5 + c.reviews * 10 + c.edits * 10 + c.helpful * 5
    from private.contribution(p_user) c;
$$;

-- Уровень по очкам: novice, knower, expert, keeper.
create function private.contributor_level(p_points integer) returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_points >= 500 then 'keeper'
    when p_points >= 200 then 'expert'
    when p_points >= 50 then 'knower'
    else 'novice'
  end;
$$;

create function private.can_review_suggestions(p_user uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user is not null
     and private.contributor_level(private.contribution_points(p_user)) in ('expert', 'keeper');
$$;

revoke execute on function private.contribution(uuid), private.contribution_points(uuid),
  private.contributor_level(integer), private.can_review_suggestions(uuid)
  from public, anon, authenticated;

-- Свой вклад: очки по видам, уровень, сколько до следующего; может ли разбирать правки и сколько ждёт.
create function public.my_contribution()
returns table (
  points integer, level text, next_level_points integer,
  places integer, photos integer, reports integer, reviews integer, edits integer, helpful integer,
  can_review boolean, review_queue integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  total integer;
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  total := private.contribution_points(me);
  return query
    select total, private.contributor_level(total),
           case when total < 50 then 50 when total < 200 then 200 when total < 500 then 500 end,
           c.places, c.photos, c.reports, c.reviews, c.edits, c.helpful,
           private.can_review_suggestions(me),
           case when private.can_review_suggestions(me)
                then (select count(*)::integer from public.suggestion_review_queue()) else 0 end
      from private.contribution(me) c;
end;
$$;

-- Очередь правок для опытного: открытые «правки полей» к чужим публичным местам, не свои. Старые сверху.
create function public.suggestion_review_queue()
returns table (
  id uuid, place_id uuid, place_name text, place_type public.place_type, place_description text,
  changes jsonb, note text, author_username text, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.can_review_suggestions(auth.uid()) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
    select s.id, p.id, p.name, p.type, p.description, s.changes, s.note, a.username, s.created_at
      from public.place_suggestions s
      join public.places p on p.id = s.place_id
      join public.profiles a on a.id = s.author_id
     where s.status = 'open'
       and s.kind = 'edit'
       and s.author_id <> auth.uid()
       and p.owner_id <> auth.uid()
       and p.deleted_at is null and p.status = 'published' and p.visibility = 'public'
       and not private.is_blocked(auth.uid(), s.author_id)
     order by s.created_at
     limit 50;
end;
$$;

-- Разобрать правку: принять (меняет место) или отклонить. Только из своей очереди.
create function public.review_suggestion(p_id uuid, p_accept boolean, p_note text default null) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.can_review_suggestions(auth.uid()) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if not exists (select 1 from public.suggestion_review_queue() q where q.id = p_id) then
    raise exception 'suggestion not found' using errcode = 'P0002';
  end if;
  insert into private.suggestion_reviews (suggestion_id, reviewer_id, accepted)
  values (p_id, auth.uid(), p_accept);
  if p_accept then
    perform private.accept_place_suggestion(p_id, nullif(btrim(left(p_note, 500)), ''));
  else
    perform private.reject_place_suggestion(p_id, nullif(btrim(left(p_note, 500)), ''));
  end if;
end;
$$;

revoke execute on function public.my_contribution(), public.suggestion_review_queue(),
  public.review_suggestion(uuid, boolean, text) from public, anon;
grant execute on function public.my_contribution(), public.suggestion_review_queue(),
  public.review_suggestion(uuid, boolean, text) to authenticated;
