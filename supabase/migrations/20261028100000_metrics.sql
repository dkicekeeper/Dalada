-- Метрики продукта (план: docs/02-plan/README.md, «Метрики») — из данных, которые уже есть в базе.
--
-- Без аналитики поведения: приложение ничего дополнительно не отправляет, событий и экранов не
-- считаем (так обещает политика конфиденциальности). Только суммы по неделям и когортам из чекинов,
-- уловов, поездок, отзывов, друзей и мест; ни координат, ни имён, ни идентификаторов в ответе.
--
-- Читает владелец базы в Supabase Studio → SQL Editor:
--   select * from private.metrics_weekly();          -- North Star и активность по неделям
--   select * from private.metrics_cohorts();         -- воронка и удержание W1 / W4
--   select * from private.metrics_content_health();  -- доля публичных мест со свежим отчётом
--   select * from private.metrics_monthly_trips();   -- доля активных с 2+ поездками за месяц
-- Клиенту функции недоступны (схема private закрыта, права на выполнение отозваны).
--
-- Неделя — с понедельника по времени Алматы. Служебные аккаунты (редакция и аккаунт для проверки
-- Apple) не считаются. Удалённое — тоже.

-- Кого не считаем ---------------------------------------------------------------------------------

create function private.metrics_excluded_users() returns setof uuid
language sql stable
set search_path = ''
as $$
  select private.editorial_id()
  union
  select u.id from auth.users u where coalesce(u.raw_app_meta_data ->> 'provider', '') = 'email'
$$;

-- Активность: чекин (он же отчёт о месте), улов, поездка, отзыв ------------------------------------

create function private.metrics_activity() returns table (user_id uuid, at timestamptz, kind text)
language sql stable
set search_path = ''
as $$
  select a.user_id, a.at, a.kind
    from (
      select c.owner_id as user_id, c.created_at as at, 'checkin' as kind
        from public.checkins c where c.deleted_at is null
      union all
      select k.owner_id, k.created_at, 'catch' from public.catches k where k.deleted_at is null
      union all
      select t.owner_id, t.created_at, 'trip' from public.trips t where t.deleted_at is null
      union all
      select r.owner_id, r.created_at, 'review' from public.reviews r where r.deleted_at is null
    ) a
   where a.user_id not in (select private.metrics_excluded_users())
$$;

-- Понедельник недели по времени Алматы.
create function private.metrics_week(p_at timestamptz) returns date
language sql stable
set search_path = ''
as $$ select date_trunc('week', p_at at time zone 'Asia/Almaty')::date $$;

-- North Star и активность по неделям ---------------------------------------------------------------

-- Последние p_weeks недель, текущая (неполная) — первой строкой с complete = false.
-- active_users — North Star: сделали за неделю хотя бы один чекин, улов, поездку или отзыв.
create function private.metrics_weekly(p_weeks integer default 12)
returns table (
  week_start   date,
  complete     boolean,
  active_users integer,
  new_users    integer,
  checkins     integer,
  catches      integer,
  trips        integer,
  reviews      integer,
  new_friends  integer
)
language sql stable
set search_path = ''
as $$
  with weeks as (
    select (private.metrics_week(now()) - 7 * g)::date as week_start
      from generate_series(0, greatest(p_weeks, 1) - 1) g
  ),
  activity as (
    select private.metrics_week(a.at) as week_start, a.user_id, a.kind from private.metrics_activity() a
  )
  select w.week_start,
         w.week_start + 7 <= (now() at time zone 'Asia/Almaty')::date,
         (select count(distinct a.user_id) from activity a where a.week_start = w.week_start)::integer,
         (select count(*) from public.profiles p
           where private.metrics_week(p.created_at) = w.week_start
             and p.id not in (select private.metrics_excluded_users()))::integer,
         (select count(*) from activity a where a.week_start = w.week_start and a.kind = 'checkin')::integer,
         (select count(*) from activity a where a.week_start = w.week_start and a.kind = 'catch')::integer,
         (select count(*) from activity a where a.week_start = w.week_start and a.kind = 'trip')::integer,
         (select count(*) from activity a where a.week_start = w.week_start and a.kind = 'review')::integer,
         -- Дружба хранится в обе стороны — пара считается один раз.
         (select count(*) from public.friendships f
           where f.user_id < f.friend_id and private.metrics_week(f.created_at) = w.week_start)::integer
    from weeks w
   order by w.week_start desc
$$;

-- Воронка и удержание по когортам ------------------------------------------------------------------

-- Когорта — неделя регистрации. activated — первый чекин, улов, поездка или отзыв в первые 7 дней;
-- with_friend — первый друг в первые 7 дней; w1 / w4 — активны на 1-й / 4-й неделе после недели
-- регистрации (null, пока та неделя не закончилась). Доли — от размера когорты.
create function private.metrics_cohorts(p_weeks integer default 12)
returns table (
  cohort_week date,
  users       integer,
  activated   integer,
  with_friend integer,
  w1          integer,
  w4          integer,
  w1_share    numeric,
  w4_share    numeric
)
language sql stable
set search_path = ''
as $$
  with users as (
    select p.id, p.created_at, private.metrics_week(p.created_at) as cohort_week
      from public.profiles p
     where p.id not in (select private.metrics_excluded_users())
       and private.metrics_week(p.created_at) > private.metrics_week(now()) - 7 * greatest(p_weeks, 1)
  ),
  activity as (
    select a.user_id, a.at, private.metrics_week(a.at) as week_start from private.metrics_activity() a
  ),
  per_user as (
    select u.cohort_week,
           exists (select 1 from activity a
                    where a.user_id = u.id and a.at < u.created_at + interval '7 days') as activated,
           exists (select 1 from public.friendships f
                    where f.user_id = u.id and f.created_at < u.created_at + interval '7 days') as with_friend,
           exists (select 1 from activity a
                    where a.user_id = u.id and a.week_start = u.cohort_week + 7) as w1,
           exists (select 1 from activity a
                    where a.user_id = u.id and a.week_start = u.cohort_week + 28) as w4
      from users u
  ),
  today as (select (now() at time zone 'Asia/Almaty')::date as d)
  select c.cohort_week,
         c.users,
         c.activated,
         c.with_friend,
         case when c.cohort_week + 14 <= t.d then c.w1 end,
         case when c.cohort_week + 35 <= t.d then c.w4 end,
         case when c.cohort_week + 14 <= t.d then round(c.w1::numeric / c.users, 3) end,
         case when c.cohort_week + 35 <= t.d then round(c.w4::numeric / c.users, 3) end
    from (
      select pu.cohort_week,
             count(*)::integer as users,
             count(*) filter (where pu.activated)::integer as activated,
             count(*) filter (where pu.with_friend)::integer as with_friend,
             count(*) filter (where pu.w1)::integer as w1,
             count(*) filter (where pu.w4)::integer as w4
        from per_user pu
       group by pu.cohort_week
    ) c
    cross join today t
   order by c.cohort_week desc
$$;

-- Здоровье контента --------------------------------------------------------------------------------

-- Доля публичных мест, где за 7 дней до p_at был чекин (отчёт): fresh_public — публичный, его видит
-- любой; fresh_any — любой видимости (и для друзей, и личный): место живое, даже если отчёт не открыт.
create function private.metrics_content_health(p_at timestamptz default now())
returns table (
  public_places      integer,
  fresh_public       integer,
  fresh_public_share numeric,
  fresh_any          integer,
  fresh_any_share    numeric
)
language sql stable
set search_path = ''
as $$
  with places as (
    select p.id from public.places p
     where p.visibility = 'public' and p.status = 'published' and p.deleted_at is null
  ),
  recent as (
    select c.place_id, c.visibility from public.checkins c
     where c.deleted_at is null
       and c.at > p_at - interval '7 days' and c.at <= p_at
       and c.owner_id not in (select private.metrics_excluded_users())
  ),
  counts as (
    select count(*)::integer as total,
           count(*) filter (where exists (select 1 from recent r where r.place_id = p.id and r.visibility = 'public'))::integer as fresh_public,
           count(*) filter (where exists (select 1 from recent r where r.place_id = p.id))::integer as fresh_any
      from places p
  )
  select c.total,
         c.fresh_public,
         round(c.fresh_public::numeric / nullif(c.total, 0), 3),
         c.fresh_any,
         round(c.fresh_any::numeric / nullif(c.total, 0), 3)
    from counts c
$$;

-- Поездки за месяц ---------------------------------------------------------------------------------

-- Месяцы по времени Алматы, текущий — первой строкой. active_users — хоть одна активность за месяц;
-- with_two_trips — две поездки и больше (поездка — по началу записи); share — от активных.
create function private.metrics_monthly_trips(p_months integer default 6)
returns table (
  month_start    date,
  active_users   integer,
  with_trip      integer,
  with_two_trips integer,
  share          numeric
)
language sql stable
set search_path = ''
as $$
  with months as (
    select (date_trunc('month', now() at time zone 'Asia/Almaty') - make_interval(months => g))::date as month_start
      from generate_series(0, greatest(p_months, 1) - 1) g
  ),
  trips as (
    select t.owner_id, date_trunc('month', t.started_at at time zone 'Asia/Almaty')::date as month_start
      from public.trips t
     where t.deleted_at is null and t.owner_id not in (select private.metrics_excluded_users())
  ),
  per_user as (
    select tr.month_start, tr.owner_id, count(*) as trips from trips tr group by tr.month_start, tr.owner_id
  ),
  active as (
    select date_trunc('month', a.at at time zone 'Asia/Almaty')::date as month_start,
           count(distinct a.user_id)::integer as users
      from private.metrics_activity() a
     group by 1
  )
  select m.month_start,
         coalesce(a.users, 0),
         (select count(*) from per_user pu where pu.month_start = m.month_start)::integer,
         (select count(*) from per_user pu where pu.month_start = m.month_start and pu.trips >= 2)::integer,
         round((select count(*) from per_user pu where pu.month_start = m.month_start and pu.trips >= 2)::numeric
               / nullif(a.users, 0), 3)
    from months m
    left join active a on a.month_start = m.month_start
   order by m.month_start desc
$$;

revoke execute on function
  private.metrics_excluded_users(),
  private.metrics_activity(),
  private.metrics_week(timestamptz),
  private.metrics_weekly(integer),
  private.metrics_cohorts(integer),
  private.metrics_content_health(timestamptz),
  private.metrics_monthly_trips(integer)
from public, anon, authenticated;
