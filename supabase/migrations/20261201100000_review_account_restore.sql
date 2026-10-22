-- Аккаунт для проверки Apple: удалённое демо-содержимое возвращается.
--
-- Проверяющие Apple проверяют удаление своего (Guideline 5.1.1(v), 1.2) и удаляют места, отчёты и
-- поездки демо-аккаунта — так у него пропали оба своих места, и скриншоты для App Store показали
-- пустые «Мои места». create_review_account добавляет содержимое, только если мест нет вовсе, а
-- удалённые (deleted_at) тоже считались. Теперь функция сначала возвращает удалённое демо-содержимое
-- (по названиям и заметкам, которые она сама создаёт; то, что проверяющие завели и удалили сами, не
-- трогает), а для уже созданного аккаунта (@appreview) миграция делает это сразу.

create function private.restore_review_content(p_owner uuid) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.places set deleted_at = null
   where owner_id = p_owner and deleted_at is not null
     and name in ('Секретная коса', 'Стоянка на Или');
  update public.checkins set deleted_at = null
   where owner_id = p_owner and deleted_at is not null
     and note in ('Утром хорошо брал сазан на кукурузу.', 'Ветрено, клевало ближе к вечеру.');
  update public.catches k set deleted_at = null
   where k.owner_id = p_owner and k.deleted_at is not null
     and exists (select 1 from public.checkins c
                  where c.id = k.checkin_id and c.deleted_at is null
                    and c.note in ('Утром хорошо брал сазан на кукурузу.', 'Ветрено, клевало ближе к вечеру.'));
  update public.trips set deleted_at = null
   where owner_id = p_owner and deleted_at is not null
     and title = 'Вечерняя рыбалка на косе';
end;
$$;

revoke execute on function private.restore_review_content(uuid) from public;

create or replace function private.create_review_account(p_email text, p_password text) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_id uuid;
  v_own_spot uuid;
  v_water uuid;
  v_checkin uuid;
  v_almaty extensions.geometry := extensions.st_setsrid(extensions.st_makepoint(76.95, 43.24), 4326);
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'invalid email' using errcode = '22023';
  end if;
  if char_length(coalesce(p_password, '')) < 8 then
    raise exception 'password must be at least 8 characters' using errcode = '22023';
  end if;

  select u.id into v_id from auth.users u where lower(u.email) = v_email;
  if v_id is not null then
    if coalesce((select u.raw_app_meta_data ->> 'provider' from auth.users u where u.id = v_id), '') <> 'email' then
      raise exception 'this email belongs to an Apple or Google account' using errcode = '22023';
    end if;
    update auth.users
       set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           banned_until = null,
           updated_at = now()
     where id = v_id;
  else
    v_id := gen_random_uuid();
    -- Пустые строки вместо NULL в служебных полях: иначе Supabase Auth не прочитает пользователя.
    insert into auth.users (
      id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    )
    values (
      v_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', v_email,
      extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
      '', '', '', '',
      '{"provider": "email", "providers": ["email"]}'::jsonb,
      '{"full_name": "App Review"}'::jsonb, now(), now()
    );
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (
      v_id::text, v_id,
      jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
      'email', now(), now(), now()
    );
  end if;

  -- Профиль (его создаёт триггер регистрации): username и согласие с условиями — чтобы проверяющий
  -- сразу попал в приложение.
  update public.profiles
     set username = coalesce(username, 'appreview'),
         display_name = coalesce(display_name, 'App Review'),
         terms_version = greatest(coalesce(terms_version, 0), 1),
         terms_accepted_at = coalesce(terms_accepted_at, now())
   where id = v_id;

  -- Удалённое проверяющими — вернуть, чтобы аккаунт снова был заполнен.
  perform private.restore_review_content(v_id);

  -- Содержимое — один раз.
  if exists (select 1 from public.places where owner_id = v_id) then
    return v_id;
  end if;

  -- Всё содержимое — «только я»: в подборках, на карте и в отчётах чужих мест его никто не увидит.
  -- Свои места: точка ловли и стоянка с «Информацией».
  insert into public.places (owner_id, type, name, description, geom, attributes, visibility, approximate, status)
  values (
    v_id, 'fishing_spot', 'Секретная коса', 'Заход с южной стороны, глубина у бровки 3–4 м.',
    extensions.st_setsrid(extensions.st_makepoint(77.0512, 43.8861), 4326),
    '{"species": ["common_carp", "zander", "asp"], "access": ["dirt"], "fee": "free",
      "methods": ["shore", "feeder", "spinning"], "amenities": ["tent", "fireplace"],
      "signal": "weak", "months": [4, 5, 6, 9, 10], "features": "Коряги у берега, течение слабое"}'::jsonb,
    'private', false, 'published'
  )
  returning id into v_own_spot;

  insert into public.places (owner_id, type, name, description, geom, attributes, visibility, approximate, status)
  values (
    v_id, 'campsite', 'Стоянка на Или', 'Ровная площадка в тени, до воды 50 м.',
    extensions.st_setsrid(extensions.st_makepoint(77.4215, 43.9127), 4326),
    '{"access": ["dirt", "offroad"], "fee": "free", "amenities": ["shade", "tent", "fireplace", "parking"],
      "signal": "none", "months": [5, 6, 7, 8, 9]}'::jsonb,
    'private', false, 'published'
  );

  -- Ближайший к Алматы водоём редакции: свой отчёт с уловом (после него можно оставить отзыв).
  select p.id into v_water
    from public.places p
   where p.owner_id = private.editorial_id()
     and p.type = 'water_body'
     and p.deleted_at is null
     and p.status = 'published'
   order by p.geom operator(extensions.<->) v_almaty
   limit 1;

  insert into public.checkins (owner_id, place_id, at, conditions, note, visibility)
  values (
    v_id, v_own_spot, now() - interval '3 days',
    '{"bite": "good", "crowd": "empty", "water": "clear", "road": "fine"}'::jsonb,
    'Утром хорошо брал сазан на кукурузу.', 'private'
  )
  returning id into v_checkin;

  insert into public.catches (owner_id, checkin_id, place_id, species_id, weight_g, length_mm, method, bait, released, at, visibility)
  values (v_id, v_checkin, v_own_spot, 'common_carp', 3200, 560, 'feeder', 'кукуруза', true,
          now() - interval '3 days', 'private');

  if v_water is not null then
    insert into public.checkins (owner_id, place_id, at, conditions, note, visibility)
    values (
      v_id, v_water, now() - interval '1 day',
      '{"bite": "moderate", "crowd": "few", "water": "clear", "road": "fine"}'::jsonb,
      'Ветрено, клевало ближе к вечеру.', 'private'
    )
    returning id into v_checkin;

    insert into public.catches (owner_id, checkin_id, place_id, species_id, weight_g, method, released, at, visibility)
    values (v_id, v_checkin, v_water, 'perch', 350, 'spinning', false, now() - interval '1 day', 'private');
  end if;

  -- Сохранённые места: три водоёма редакции поблизости.
  insert into public.saved_places (owner_id, place_id)
  select v_id, p.id
    from public.places p
   where p.owner_id = private.editorial_id()
     and p.deleted_at is null
     and p.status = 'published'
   order by p.geom operator(extensions.<->) v_almaty
   limit 3
  on conflict do nothing;

  -- Поездка с треком (высота и время в каждой точке).
  insert into public.trips (owner_id, activity, title, note, started_at, ended_at, moving_seconds, distance_m,
                            elevation_gain_m, max_speed_mps, track, visibility)
  values (
    v_id, 'fishing', 'Вечерняя рыбалка на косе', 'Прошли вдоль берега до мыса.',
    now() - interval '3 days' - interval '2 hours', now() - interval '3 days', 3600, 2400, 12, 1.8,
    extensions.st_geomfromewkt(
      'SRID=4326;LINESTRING ZM (77.0450 43.8830 480 ' || extract(epoch from now() - interval '3 days 2 hours')::bigint
      || ', 77.0478 43.8842 482 ' || extract(epoch from now() - interval '3 days 90 minutes')::bigint
      || ', 77.0496 43.8851 486 ' || extract(epoch from now() - interval '3 days 60 minutes')::bigint
      || ', 77.0512 43.8861 492 ' || extract(epoch from now() - interval '3 days')::bigint || ')'
    ),
    'private'
  );

  return v_id;
end;
$$;

revoke execute on function private.create_review_account(text, text) from public;

-- Уже созданный аккаунт для проверки.
select private.restore_review_content(p.id) from public.profiles p where p.username = 'appreview';
