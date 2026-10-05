-- Ещё три статьи (до 18): безопасность в лодке, как не заблудиться без связи, костёр без пожара.
--
-- Исходники — supabase/data/articles; SQL собран `build_sql.py boat_safety offline_navigation campfire`.
-- Казахский и английский — черновик на вычитку носителем.

insert into public.articles
  (id, category, sort_order, published_on,
   title_ru, title_kk, title_en, summary_ru, summary_kk, summary_en, body_ru, body_kk, body_en)
values
  ('boat_safety',
   'safety',
   160,
   date '2026-10-05',
   $md$Безопасность в лодке$md$,
   $md$Қайықтағы қауіпсіздік$md$,
   $md$Safety in a boat$md$,
   $md$Капшагай, Балхаш и Алаколь — большие и ветреные. Что взять, когда не выходить и что делать, если лодка перевернулась.$md$,
   $md$Қапшағай, Балқаш және Алакөл — үлкен әрі желді. Не алу керек, қашан шықпау керек және қайық аударылса не істеу керек.$md$,
   $md$Kapshagay, Balkhash and Alakol are big and windy. What to bring, when not to go out and what to do if the boat capsizes.$md$,
   $md$На больших водоёмах Алматинской области ветер поднимается быстро, а волна на мелкой воде короткая и крутая. Большинство несчастных случаев с лодками — без спасательного жилета.

## Перед выходом

- **Спасательный жилет на каждом** — надетый, а не лежащий в лодке. Упавшему в холодную воду некогда его искать.
- Посмотрите прогноз ветра. Больше 8–10 м/с — на надувной и маленькой лодке не выходите.
- Скажите на берегу, куда идёте и когда вернётесь. Телефон — в непромокаемом чехле.
- Возьмите вёсла, черпак, фонарь, нож и свисток — даже если есть мотор.
- Не перегружайте лодку: число людей и груз — не больше, чем написано на табличке.

## На воде

- Держитесь ближе к берегу. Ветер, дующий с берега, незаметно уносит на середину, а назад придётся грести против волны.
- Встали в лодке, чтобы вытащить рыбу, — лодка качнулась. Вываживайте сидя.
- Алкоголь и лодка несовместимы.
- Увидели, что ветер крепчает и поднимается волна, — сразу к берегу, не дожидаясь шторма.

## Если лодка перевернулась

1. Держитесь за лодку: она не тонет и её видно издалека.
2. Не плывите к далёкому берегу — сил не хватит, особенно в холодной воде.
3. Свистите и машите, чтобы вас заметили.
4. Если вода холодная, прижмите колени к груди — так меньше тепла уходит.

> Весной и осенью вода холодная даже в жаркий день. Экстренная помощь — **112**.$md$,
   $md$Алматы облысының үлкен су айдындарында жел тез көтеріледі, ал таяз судағы толқын қысқа әрі тік болады. Қайықпен болатын жазатайым оқиғалардың көбі — құтқару кеудешесінсіз.

## Шығар алдында

- **Әркімде құтқару кеудешесі** — қайықта жатқан емес, киілген. Суық суға құлаған адамның оны іздеуге уақыты болмайды.
- Жел болжамын қараңыз. Секундына 8–10 метрден көп болса — үрлемелі және кішкентай қайықпен шықпаңыз.
- Жағадағыларға қайда баратыныңызды және қашан оралатыныңызды айтыңыз. Телефон — су өткізбейтін қапта.
- Мотор болса да ескек, шөміш, шам, пышақ және ысқырық алыңыз.
- Қайыққа артық жүк салмаңыз: адам саны мен жүк — тақтайшада жазылғаннан аспасын.

## Суда

- Жағаға жақын жүріңіз. Жағадан соққан жел байқатпай ортаға алып кетеді, ал кері толқынға қарсы ескек есуге тура келеді.
- Балықты шығару үшін қайықта тұрсаңыз — қайық шайқалады. Балықты отырып шығарыңыз.
- Ішімдік пен қайық сыйыспайды.
- Жел күшейіп, толқын көтеріле бастаса — дауылды күтпей, бірден жағаға.

## Қайық аударылса

1. Қайықты ұстаңыз: ол батпайды және алыстан көрінеді.
2. Алыс жағаға қарай жүзбеңіз — күшіңіз жетпейді, әсіресе суық суда.
3. Сізді байқауы үшін ысқырып, қол бұлғаңыз.
4. Су суық болса, тізеңізді кеудеңізге қысыңыз — жылу азырақ кетеді.

> Көктем мен күзде ыстық күні де су суық болады. Шұғыл көмек — **112**.$md$,
   $md$On the big waters of the Almaty region the wind rises fast, and waves on shallow water are short and steep. Most boating accidents happen without a life jacket.

## Before you go out

- **A life jacket on everyone** — worn, not lying in the boat. Someone who falls into cold water has no time to look for it.
- Check the wind forecast. Over 8–10 m/s, do not go out in an inflatable or small boat.
- Tell someone on shore where you are going and when you will be back. Keep your phone in a waterproof case.
- Bring oars, a bailer, a torch, a knife and a whistle — even with an engine.
- Do not overload the boat: people and cargo no more than the plate says.

## On the water

- Stay close to the shore. An offshore wind quietly carries you to the middle, and you will have to row back against the waves.
- Standing up to land a fish rocks the boat. Play fish sitting down.
- Alcohol and boats do not mix.
- When the wind picks up and waves build, head for the shore at once — do not wait for the storm.

## If the boat capsizes

1. Hold on to the boat: it stays afloat and can be seen from afar.
2. Do not swim for a distant shore — you will not have the strength, especially in cold water.
3. Whistle and wave so you are noticed.
4. In cold water, pull your knees to your chest — you lose less heat.

> In spring and autumn the water is cold even on a hot day. Emergency — **112**.$md$),
  ('offline_navigation',
   'safety',
   170,
   date '2026-10-05',
   $md$Как не заблудиться без связи$md$,
   $md$Байланыссыз қалай адаспау керек$md$,
   $md$How not to get lost without a signal$md$,
   $md$В горах и степи связи часто нет. Как подготовить телефон, что взять и что делать, если потерялись.$md$,
   $md$Тауда және далада байланыс жиі болмайды. Телефонды қалай дайындау керек, не алу керек және адасып қалсаңыз не істеу керек.$md$,
   $md$In the mountains and the steppe there is often no signal. How to prepare your phone, what to bring and what to do if you get lost.$md$,
   $md$За городом сотовая связь пропадает уже в ущельях и на дальних берегах. Карта в телефоне работает и без интернета — если подготовить её заранее.

## Дома

1. Скачайте карту района: «Лайфхаки» → «Карты без сети». Dalada показывает места, запреты и слои без сети.
2. Зарядите телефон и возьмите внешний аккумулятор. Холод и поиск сети быстро сажают батарею.
3. Скажите близким маршрут и время возвращения. Договоритесь: если не вышли на связь до вечера — звонят 112.

## В пути

- Включите запись поездки — трек пишется и без связи, по нему можно вернуться: страница поездки → «Пройти по маршруту» → «В обратную сторону».
- Держите телефон в авиарежиме, когда связи всё равно нет: батарея проживёт в разы дольше, а GPS работает.
- Запоминайте ориентиры: развилки, мосты, приметные скалы.
- В горах темнеет быстро. Поворачивайте назад так, чтобы вернуться засветло.

## Если потерялись

1. Остановитесь и успокойтесь. Не идите наугад — так уходят ещё дальше.
2. Посмотрите свой трек и вернитесь по нему к последнему знакомому месту.
3. Поднимитесь повыше — там часто появляется связь. Звонок на **112** проходит и через сеть другого оператора.
4. Если наступает темнота — оставайтесь на месте, оденьтесь теплее, разведите огонь, если это безопасно. Ждать на месте легче, чем искать в темноте.

> В горах не ходят по руслам рек вниз «к людям»: русла обрываются водопадами и сбросами.$md$,
   $md$Қаладан тыс жерде ұялы байланыс шатқалдар мен алыс жағаларда-ақ жоғалады. Телефондағы карта интернетсіз де жұмыс істейді — егер оны алдын ала дайындасаңыз.

## Үйде

1. Аудан картасын жүктеп алыңыз: «Лайфхактар» → «Желісіз карталар». Dalada орындарды, тыйымдарды және қабаттарды желісіз көрсетеді.
2. Телефонды зарядтап, сыртқы аккумулятор алыңыз. Суық пен желі іздеу батареяны тез отырғызады.
3. Жақындарыңызға бағытыңызды және оралу уақытын айтыңыз. Келісіп алыңыз: кешке дейін хабарласпасаңыз — 112-ге қоңырау шалады.

## Жолда

- Сапар жазбасын қосыңыз — трек байланыссыз да жазылады, сол арқылы қайтуға болады: сапар беті → «Бағытпен жүру» → «Кері бағытта».
- Байланыс бәрібір жоқ болса, телефонды ұшақ режимінде ұстаңыз: батарея бірнеше есе ұзақ шыдайды, ал GPS жұмыс істейді.
- Белгілерді есте сақтаңыз: айрықтар, көпірлер, көзге түсетін жартастар.
- Тауда тез қараңғы түседі. Жарықта оралатындай кері бұрылыңыз.

## Адасып қалсаңыз

1. Тоқтап, сабыр сақтаңыз. Кез келген бағытпен жүрмеңіз — солай одан әрі алыстайды.
2. Трегіңізді қарап, соңғы таныс жерге сол бойымен оралыңыз.
3. Биігірек көтеріліңіз — онда байланыс жиі пайда болады. **112**-ге қоңырау басқа оператордың желісі арқылы да өтеді.
4. Қараңғы түссе — орныңызда қалыңыз, жылырақ киініңіз, қауіпсіз болса от жағыңыз. Қараңғыда іздегеннен орында күткен жеңіл.

> Тауда «адамдарға» жетемін деп өзен арнасымен төмен жүрмейді: арналар сарқырамалар мен құламалармен үзіледі.$md$,
   $md$Outside the city the mobile signal disappears already in the gorges and on distant shores. The map in your phone works without internet — if you prepare it in advance.

## At home

1. Download the map of the area: Tips → Offline maps. Dalada shows places, bans and layers offline.
2. Charge your phone and bring a power bank. Cold and searching for a network drain the battery fast.
3. Tell someone your route and when you will be back. Agree that if you have not called by evening, they call 112.

## On the way

- Start recording a trip — the track records without a signal, and you can follow it back: the trip page → Follow this route → Reverse direction.
- Keep the phone in airplane mode when there is no signal anyway: the battery lasts several times longer and GPS still works.
- Remember landmarks: forks, bridges, notable rocks.
- It gets dark fast in the mountains. Turn back in time to return in daylight.

## If you are lost

1. Stop and calm down. Do not walk at random — that takes you further away.
2. Look at your track and follow it back to the last familiar place.
3. Climb higher — the signal often comes back there. A call to **112** also goes through another operator's network.
4. If darkness falls, stay where you are, put on warm clothes, make a fire if it is safe. Waiting is easier than searching in the dark.

> In the mountains, do not follow a riverbed downhill "towards people": riverbeds break off at waterfalls and drops.$md$),
  ('campfire',
   'rules_ethics',
   180,
   date '2026-10-05',
   $md$Костёр без пожара$md$,
   $md$Өртсіз от$md$,
   $md$A campfire without a wildfire$md$,
   $md$Степь, тростник и сухая хвоя загораются от одной искры. Где можно разводить костёр, как его сложить и как потушить.$md$,
   $md$Дала, қамыс және құрғақ қылқан бір ұшқыннан тұтанады. От қайда жағуға болады, оны қалай жинау және қалай сөндіру керек.$md$,
   $md$Steppe, reeds and dry needles catch fire from a single spark. Where you may light a fire, how to build it and how to put it out.$md$,
   $md$Летом и осенью в Алматинской области сухо, а ветер разносит искры на десятки метров. Большинство степных и лесных пожаров начинается с непотушенного костра.

## Можно ли здесь разводить огонь

- В нацпарках и заповедниках огонь — только в оборудованных местах. Границы — на карте Dalada, слой «Нацпарки и заповедники».
- В сильный ветер, в жару и при объявленной пожарной опасности костёр не разводят вовсе — готовьте на газовой горелке.
- Не разводите огонь под деревьями, на торфе, в сухой траве и тростнике, ближе 10 метров от палатки.

## Как сложить

1. Используйте старое кострище. Если его нет — снимите дёрн, уберите вокруг траву и листья на метр.
2. Обложите место камнями (не речными: мокрые камни от жара трескаются).
3. Держите рядом воду — котелок или канистру — до того, как зажгли.
4. Костёр — маленький: для ухи и чая хватит огня размером с котелок.

## Как потушить

1. Залейте костёр водой, не жалейте.
2. Перемешайте угли и золу палкой и залейте ещё раз.
3. Проверьте рукой над золой: тепла быть не должно. Уходите, только когда всё холодное.
4. Нет воды — засыпьте землёй или песком и тоже перемешайте.

> Увидели пожар — звоните **112** и уходите против ветра, поперёк направления огня.$md$,
   $md$Жазда және күзде Алматы облысында құрғақ, ал жел ұшқынды ондаған метрге таратады. Дала мен орман өрттерінің көбі сөндірілмеген оттан басталады.

## Мұнда от жағуға бола ма

- Ұлттық парктер мен қорықтарда от — тек жабдықталған жерлерде. Шекаралар — Dalada картасында, «Ұлттық парктер мен қорықтар» қабатында.
- Қатты желде, ыстықта және өрт қаупі жарияланғанда от мүлде жақпайды — газ оттығында пісіріңіз.
- Отты ағаштардың астына, шымтезекке, құрғақ шөп пен қамысқа, шатырдан 10 метрден жақын жақпаңыз.

## Қалай жинау керек

1. Бұрынғы ошақты пайдаланыңыз. Болмаса — шымды алып, айналадағы шөп пен жапырақты бір метрге тазалаңыз.
2. Орынды таспен қоршаңыз (өзен тасымен емес: ылғал тас ыстықтан жарылады).
3. Отты жақпай тұрып жаныңызға су қойыңыз — қазан немесе канистр.
4. От шағын болсын: уха мен шайға қазандай от жеткілікті.

## Қалай сөндіру керек

1. Отқа су құйыңыз, аямаңыз.
2. Шоқ пен күлді таяқпен араластырып, тағы су құйыңыз.
3. Күлдің үстінен қолмен тексеріңіз: жылу болмауы керек. Бәрі суығанда ғана кетіңіз.
4. Су болмаса — топырақпен немесе құммен көміп, оны да араластырыңыз.

> Өрт көрсеңіз — **112**-ге қоңырау шалып, желге қарсы, оттың бағытына көлденең кетіңіз.$md$,
   $md$In summer and autumn the Almaty region is dry, and the wind carries sparks tens of metres. Most steppe and forest fires start from a campfire that was not put out.

## Can you light a fire here

- In national parks and reserves, fires only in designated places. Boundaries are on the Dalada map, layer National parks and reserves.
- In strong wind, in the heat and when fire danger is announced, no campfire at all — cook on a gas stove.
- Do not light a fire under trees, on peat, in dry grass and reeds, or closer than 10 metres to a tent.

## How to build it

1. Use an existing fire ring. If there is none, lift the turf and clear grass and leaves for a metre around.
2. Ring the spot with stones (not from the river: wet stones crack in the heat).
3. Keep water nearby — a pot or a canister — before you light it.
4. Keep the fire small: a fire the size of the pot is enough for ukha and tea.

## How to put it out

1. Pour water on the fire, plenty of it.
2. Stir the embers and ash with a stick and pour water again.
3. Check with your hand above the ash: there should be no warmth. Leave only when everything is cold.
4. No water — cover it with soil or sand and stir that too.

> If you see a wildfire, call **112** and move into the wind, across the fire's direction.$md$);
