-- Упоминания @username в обсуждениях: упомянутому — «Вас упомянули», даже без подписки; не себе,
-- не тем, кто обсуждение не видит или отписался; почта и середина слова — не упоминание.
-- A — автор обсуждения, B отвечает, C, D упоминают, E заблокирован автором.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(10);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.act_as_admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- Кому ушло уведомление с этим текстом: username, у упомянутых — «*».
create function pg_temp.notified(p_snippet text) returns text language sql as $$
  select coalesce(string_agg(p.username || case when o.payload ? 'mention' then '*' else '' end, ',' order by p.username), '')
    from private.push_outbox o join public.profiles p on p.id = o.user_id
   where o.payload ->> 'snippet' = p_snippet
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'd@test.local'),
  ('55555555-5555-5555-5555-555555555555', 'e@test.local');
update public.profiles p set username = u.name
  from (values ('11111111-1111-1111-1111-111111111111'::uuid, 'aaa'), ('22222222-2222-2222-2222-222222222222', 'bbb'),
               ('33333333-3333-3333-3333-333333333333', 'ccc'), ('44444444-4444-4444-4444-444444444444', 'ddd'),
               ('55555555-5555-5555-5555-555555555555', 'eee')) u(id, name)
 where p.id = u.id;
insert into public.devices (token, user_id, environment)
select repeat(lpad(to_hex(n), 2, '0'), 32), id, 'production'
  from (values (1, '11111111-1111-1111-1111-111111111111'::uuid), (2, '22222222-2222-2222-2222-222222222222'),
               (3, '33333333-3333-3333-3333-333333333333'), (4, '44444444-4444-4444-4444-444444444444'),
               (5, '55555555-5555-5555-5555-555555555555')) d(n, id);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Залив', 'SRID=4326;POINT(77.00 43.90)', 'public');
insert into public.blocks (blocked_id) values ('55555555-5555-5555-5555-555555555555');
select pg_temp.act_as_admin();
update public.places set status = 'published' where id = 'aaaaaaaa-0000-0000-0000-000000000001';

-- Упоминание в вопросе ---------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.threads (id, place_id, title, body)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Дорога',
        'Кто знает дорогу? @CCC.');
select pg_temp.act_as_admin();
select is(pg_temp.notified('Кто знает дорогу? @CCC.'), 'ccc*', 'упомянутому в вопросе — «Вас упомянули» (регистр и точка в конце не мешают)');

-- Упоминания в ответе ----------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.thread_posts (thread_id, body)
values ('dddddddd-0000-0000-0000-000000000001', 'Спроси @ddd и @eee, почта x@aaa.kz и @zzz не в счёт, себе @bbb — нет');
select pg_temp.act_as_admin();
select is(
  pg_temp.notified('Спроси @ddd и @eee, почта x@aaa.kz и @zzz не в счёт, себе @bbb — нет'),
  'aaa,ddd*',
  'автору — как подписанному, D — упоминание; заблокированному автором, себе, почте и несуществующему — нет'
);
select is(
  (select payload ->> 'mention' from private.push_outbox o
    where o.user_id = '11111111-1111-1111-1111-111111111111' and o.payload ->> 'snippet' like 'Спроси%'),
  null,
  'у подписанного без упоминания — обычный ответ'
);
select is(
  (select count(*)::integer from private.push_outbox o
    where o.user_id = '33333333-3333-3333-3333-333333333333' and o.payload ->> 'snippet' like 'Спроси%'),
  0,
  'упоминание в вопросе не подписывает'
);

-- Упомянутый и подписанный — одно уведомление, с упоминанием.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.thread_posts (thread_id, body)
values ('dddddddd-0000-0000-0000-000000000001', '@aaa, посмотрите');
select pg_temp.act_as_admin();
select is(pg_temp.notified('@aaa, посмотрите'), 'aaa*', 'автору одно уведомление — «Вас упомянули»');

-- D отписался от обсуждения — упоминания тоже не приходят.
select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select public.set_thread_subscription('dddddddd-0000-0000-0000-000000000001', false);
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.thread_posts (thread_id, body)
values ('dddddddd-0000-0000-0000-000000000001', 'Ещё раз, @ddd');
select pg_temp.act_as_admin();
select is(pg_temp.notified('Ещё раз, @ddd'), 'aaa', 'отписавшемуся — ни ответов, ни упоминаний');

-- Разбор упоминаний -------------------------------------------------------------------------------

select is(
  (select count(*)::integer from private.mentioned_users('@aaa @aaa @AAA')),
  1,
  'одно имя — одно упоминание'
);
select is(
  (select count(*)::integer from private.mentioned_users(
     (select string_agg('@' || username, ' ') from public.profiles) || ' ' || repeat('@aaa ', 20))),
  least((select count(*)::integer from public.profiles where username is not null), 10),
  'не больше 10 упоминаний'
);
select is(
  (select count(*)::integer from private.mentioned_users('mail@bbb.kz слово@ccc')),
  0,
  'почта и середина слова — не упоминание'
);
select is(
  has_function_privilege('authenticated', 'private.mentioned_users(text)', 'execute'),
  false,
  'разбор упоминаний клиенту не нужен'
);

select * from finish();
rollback;
