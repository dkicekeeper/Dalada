-- Значок «Три отчёта со льда» к событию App Store «Подлёдный сезон» (15 января — 15 февраля 2027,
-- docs/05-release/promotion.md, п. 9.4). В отчёте появляется вариант воды «Лёд»
-- (`checkins.conditions.water = 'ice'`, приложение 1.0.3); значок — за отчёты со льда в три разных дня
-- (по Алматы), чтобы три отчёта подряд с одной лунки его не давали. Удалённые отчёты не в счёт.
--
-- Старые версии приложения неизвестный значок не показывают, а неизвестное значение воды читают как
-- пустое (`CheckinConditions`), поэтому сервер можно обновить раньше приложения.

create or replace function private.achievement_progress(p_user uuid)
returns table (achievement text, sort integer, progress integer, target integer)
language sql
stable
security definer
set search_path = ''
as $$
  with trips as (
    select t.started_at, t.ended_at, t.distance_m
      from public.trips t
     where t.owner_id = p_user and t.deleted_at is null and t.ended_at is not null
  ),
  catches as (
    select k.species_id, k.weight_g, k.count
      from public.catches k
     where k.owner_id = p_user and k.deleted_at is null
  ),
  checkins as (
    select c.place_id, c.at, c.conditions
      from public.checkins c
     where c.owner_id = p_user and c.deleted_at is null
  )
  select v.achievement, v.sort, v.progress, v.target
    from (values
      ('first_trip', 1,
       (select count(*) from trips)::integer, 1),
      ('distance_100', 2,
       (select coalesce(sum(distance_m), 0) / 1000 from trips)::integer, 100),
      ('nights_5', 3,
       (select coalesce(sum(least(
                 (t.ended_at at time zone 'Asia/Almaty')::date
                 - (t.started_at at time zone 'Asia/Almaty')::date, 14)), 0)
          from trips t)::integer, 5),
      ('first_catch', 4,
       (select count(*) from catches)::integer, 1),
      ('species_5', 5,
       (select count(distinct species_id) from catches
         where species_id is not null and species_id <> 'other')::integer, 5),
      ('trophy_3kg', 6,
       (select coalesce(max(weight_g), 0) from catches where count = 1)::integer, 3000),
      ('places_5', 7,
       (select count(distinct place_id) from checkins where place_id is not null)::integer, 5),
      ('first_public_place', 8,
       (select count(*) from public.places p
         where p.owner_id = p_user and p.deleted_at is null
           and p.visibility = 'public' and p.status = 'published')::integer, 1),
      ('reviews_5', 9,
       (select count(*) from public.reviews r
         where r.owner_id = p_user and r.deleted_at is null)::integer, 5),
      ('accepted_edit', 10,
       (select count(*) from public.place_suggestions s
         where s.author_id = p_user and s.status = 'accepted')::integer, 1),
      ('ice_reports_3', 11,
       (select count(distinct (at at time zone 'Asia/Almaty')::date) from checkins
         where conditions ->> 'water' = 'ice')::integer, 3)
    ) as v(achievement, sort, progress, target);
$$;

revoke execute on function private.achievement_progress(uuid) from public;
