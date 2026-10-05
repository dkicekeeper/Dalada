-- Подписка на обсуждение: по умолчанию подписаны автор и отвечавшие, можно подписаться самому и
-- отписаться; ответ получают все подписанные, кроме отписавшихся, автора ответа и тех, кто обсуждение
-- не видит. A — автор обсуждения, B и D отвечают, C подписывается сам, E заблокирован автором.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(17);

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

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end $$;

-- Кому ушло уведомление об ответе с этим текстом.
create function pg_temp.notified(p_snippet text) returns text language sql as $$
  select coalesce(string_agg(p.username, ',' order by p.username), '')
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
-- У всех есть телефон — иначе уведомление не ставится в очередь.
insert into public.devices (token, user_id, environment)
select repeat(lpad(to_hex(n), 2, '0'), 32), id, 'production'
  from (values (1, '11111111-1111-1111-1111-111111111111'::uuid), (2, '22222222-2222-2222-2222-222222222222'),
               (3, '33333333-3333-3333-3333-333333333333'), (4, '44444444-4444-4444-4444-444444444444'),
               (5, '55555555-5555-5555-5555-555555555555')) d(n, id);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Залив', 'SRID=4326;POINT(77.00 43.90)', 'public');
select pg_temp.act_as_admin();
update public.places set status = 'published' where id = 'aaaaaaaa-0000-0000-0000-000000000001';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.threads (id, place_id, title, body)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Дорога', 'Как проехать?');

-- Подписка по умолчанию ----------------------------------------------------------------------------

select is(public.thread_subscription('dddddddd-0000-0000-0000-000000000001'), true, 'автор подписан');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(public.thread_subscription('dddddddd-0000-0000-0000-000000000001'), false, 'читатель не подписан');
insert into public.thread_posts (id, thread_id, body)
values ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001', 'Через мост');
select is(public.thread_subscription('dddddddd-0000-0000-0000-000000000001'), true, 'ответил — подписан');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(
  public.set_thread_subscription('dddddddd-0000-0000-0000-000000000001', true),
  true,
  'можно подписаться, не отвечая'
);
select is(public.thread_subscription('dddddddd-0000-0000-0000-000000000001'), true, 'подписка сохранилась');
select throws_ok(
  $$ select * from public.thread_subscriptions $$,
  '42501', null,
  'таблица подписок клиенту закрыта'
);

-- E заблокирован автором и подписался до блокировки: обсуждение ему больше не видно.
select pg_temp.act_as('55555555-5555-5555-5555-555555555555');
select public.set_thread_subscription('dddddddd-0000-0000-0000-000000000001', true);
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.blocks (blocked_id) values ('55555555-5555-5555-5555-555555555555');

select pg_temp.act_as('55555555-5555-5555-5555-555555555555');
select is(public.thread_subscription('dddddddd-0000-0000-0000-000000000001'), null, 'заблокированный обсуждение не видит');
select throws_ok(
  $$ select public.set_thread_subscription('dddddddd-0000-0000-0000-000000000001', true) $$,
  'P0002', null,
  'и подписаться на невидимое нельзя'
);

-- Кому уходит ответ --------------------------------------------------------------------------------

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
insert into public.thread_posts (id, thread_id, body)
values ('eeeeeeee-0000-0000-0000-000000000002', 'dddddddd-0000-0000-0000-000000000001', 'Мост размыло');
select pg_temp.act_as_admin();
select is(pg_temp.notified('Мост размыло'), 'aaa,bbb,ccc', 'автору, ответившему и подписавшемуся; не себе и не заблокированному');

-- Автор отписался: ни ответов, ни цитат его сообщений.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  public.set_thread_subscription('dddddddd-0000-0000-0000-000000000001', false),
  false,
  'автор может отписаться'
);
insert into public.thread_posts (id, thread_id, body)
values ('eeeeeeee-0000-0000-0000-000000000003', 'dddddddd-0000-0000-0000-000000000001', 'Есть брод');
select is(public.thread_subscription('dddddddd-0000-0000-0000-000000000001'), false, 'ответ после отписки подписку не возвращает');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.thread_posts (thread_id, body, quote_post_id)
values ('dddddddd-0000-0000-0000-000000000001', 'Где брод?', 'eeeeeeee-0000-0000-0000-000000000003');
select pg_temp.act_as_admin();
select is(pg_temp.notified('Где брод?'), 'ccc,ddd', 'отписавшемуся автору — ничего, даже на цитату');

-- C отписался, D удалил свой ответ — уведомлений им нет; цитата снова подписывает автора цитаты
-- только по умолчанию.
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select public.set_thread_subscription('dddddddd-0000-0000-0000-000000000001', false);
select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
update public.thread_posts set deleted_at = now() where id = 'eeeeeeee-0000-0000-0000-000000000002';
select is(public.thread_subscription('dddddddd-0000-0000-0000-000000000001'), false, 'удалил свой единственный ответ — не подписан');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select public.set_thread_subscription('dddddddd-0000-0000-0000-000000000001', true);
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.thread_posts (thread_id, body)
values ('dddddddd-0000-0000-0000-000000000001', 'Спасибо');
select pg_temp.act_as_admin();
select is(pg_temp.notified('Спасибо'), 'aaa', 'автор подписался снова; отписавшийся и удаливший ответ — нет');

-- Доступ -------------------------------------------------------------------------------------------

select pg_temp.act_as_anon();
select throws_ok(
  $$ select public.thread_subscription('dddddddd-0000-0000-0000-000000000001') $$,
  '42501', null,
  'гостю подписка недоступна'
);
select throws_ok(
  $$ select public.set_thread_subscription('dddddddd-0000-0000-0000-000000000001', true) $$,
  '42501', null,
  'и подписаться гость не может'
);

-- Удалённый аккаунт уносит свои подписки.
select pg_temp.act_as_admin();
delete from auth.users where id = '33333333-3333-3333-3333-333333333333';
select is(
  (select count(*)::integer from public.thread_subscriptions where user_id = '33333333-3333-3333-3333-333333333333'),
  0,
  'подписки удаляются вместе с аккаунтом'
);

select * from finish();
rollback;
