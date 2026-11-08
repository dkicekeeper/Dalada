-- Статья к событию «Первый лёд» (1–31 декабря): подлёдная рыбалка для начинающих — снасти, где искать
-- рыбу по сезону, проводка. Первая в списке статей (sort_order 5), рядом с «Безопасностью на льду».
--
-- Исходники — supabase/data/articles; SQL собран `build_sql.py ice_fishing_basics`.
-- Казахский и английский — черновик на вычитку носителем.

insert into public.articles
  (id, category, sort_order, published_on,
   title_ru, title_kk, title_en, summary_ru, summary_kk, summary_en, body_ru, body_kk, body_en)
values
  ('ice_fishing_basics',
   'technique',
   5,
   date '2026-11-09',
   $md$Подлёдная рыбалка: с чего начать$md$,
   $md$Мұз астынан балық аулау: неден бастау керек$md$,
   $md$Ice fishing: getting started$md$,
   $md$Что взять на первый лёд, где зимой искать рыбу и какими снастями ловить окуня, плотву, судака и щуку.$md$,
   $md$Алғашқы мұзға не алу керек, қыста балықты қайдан іздеу керек және алабұға, торта, көксерке мен шортанды қандай құралмен аулау керек.$md$,
   $md$What to bring on first ice, where to look for fish in winter and which tackle to use for perch, roach, zander and pike.$md$,
   $md$Зимой рыба держится стаями и мало двигается, поэтому главное — найти её. Сверлите несколько лунок на разной глубине и не сидите над пустой дольше 10–15 минут.

Сначала — лёд: какой лёд держит и что делать, если провалились, — в статье «Безопасность на льду».

## Что взять

- **Ледобур.** Для окуня и плотвы хватит 100–110 мм, для судака и щуки удобнее 130–150 мм.
- **Зимние удочки** — короткие, с кивком; к ним мормышки, блёсны или балансиры.
- **Черпак** — чистить лунку от ледяной крошки.
- **Ящик или стульчик** и коврик под ноги.
- **Пешню, спасалки и верёвку** — обязательно.
- Тёплые сменные носки и варежки, термос, заряженный телефон.

## Где искать рыбу

- **Первый лёд** (обычно декабрь): рыба ещё активна и стоит там же, где осенью, — на свалах глубин, у бровок, на краю камыша.
- **Глухозимье** (январь–февраль): лёд и снег толще, кислорода в воде меньше. Рыба уходит глубже и держится ближе к течению — у русла и впадений рек.
- **Последний лёд** (март): рыба снова оживает и подходит к берегам. Лёд в это время самый коварный — проверяйте каждый шаг.

## Снасти и проводка

- **Мормышка** — главная зимняя приманка для окуня, плотвы и леща. Опустите её до дна и поднимайте мелкими частыми покачиваниями кивка, иногда с паузами. Насадка — мотыль или опарыш.
- **Блесна и балансир** — для окуня, судака и щуки. Резкий подброс на 20–40 см, свободное падение, пауза; поклёвка чаще всего — на паузе.
- **Жерлица** — для щуки и судака: живец на крючке и флажок, который поднимается при поклёвке. Ставьте жерлицы на перепадах глубин. Сколько снастей можно ставить, указано в правилах рыболовства.

## Как не замёрзнуть

Одевайтесь слоями: термобельё, флис, непродуваемые куртка и штаны, тёплая обувь с толстой подошвой. На открытом льду ветер сильнее, чем на берегу, — укройтесь за палаткой или щитом от ветра. Промокшие варежки меняйте сразу.

> Зимой на части водоёмов действуют запреты и ограничения на лов. Проверьте их для своего водоёма перед выездом — они есть на карте Dalada.$md$,
   $md$Қыста балық топтанып жүреді және аз қозғалады, сондықтан ең бастысы — оны табу. Әртүрлі тереңдікте бірнеше ойық бұрғылаңыз және бос ойықтың басында 10–15 минуттан артық отырмаңыз.

Алдымен — мұз: қандай мұз көтереді және мұз ойылып кетсе не істеу керек — «Мұздағы қауіпсіздік» мақаласында.

## Не алу керек

- **Мұз бұрғысы.** Алабұға мен торта үшін 100–110 мм жеткілікті, көксерке мен шортан үшін 130–150 мм ыңғайлы.
- **Қысқы қармақтар** — қысқа, кивогы бар; оларға мормышка, блесна немесе балансир.
- **Шөміш** — ойықты мұз үгіндісінен тазалау үшін.
- **Жәшік немесе орындық** және аяқ астына төсеніш.
- **Сүймен, құтқарғыштар және арқан** — міндетті түрде.
- Ауыстыратын жылы шұлық пен қолғап, термос, зарядталған телефон.

## Балықты қайдан іздеу керек

- **Алғашқы мұз** (әдетте желтоқсан): балық әлі белсенді және күздегі орнында тұрады — тереңдік еңістерінде, жиектерде, қамыстың шетінде.
- **Қыстың ортасы** (қаңтар–ақпан): мұз бен қар қалыңдайды, судағы оттегі азаяды. Балық тереңге кетеді және ағысқа жақын — арна мен өзен сағаларының маңында болады.
- **Соңғы мұз** (наурыз): балық қайта жанданып, жағаға жақындайды. Бұл кезде мұз ең алдамшы — әр қадамды тексеріңіз.

## Құралдар және ойнату

- **Мормышка** — алабұға, торта және тыран үшін басты қысқы жем. Оны түбіне дейін түсіріп, кивокты ұсақ әрі жиі тербетіп, кейде кідіріспен көтеріңіз. Жем — мотыль немесе опарыш.
- **Блесна және балансир** — алабұға, көксерке және шортан үшін. 20–40 см-ге күрт көтеріп, еркін түсіріңіз, кідіріс жасаңыз; балық көбіне кідіріс кезінде қабады.
- **Жерлица** — шортан мен көксерке үшін: ілгектегі тірі балық және қапқанда көтерілетін жалауша. Жерлицаларды тереңдік ауысатын жерлерге қойыңыз. Қанша құрал қоюға болатыны балық аулау қағидаларында көрсетілген.

## Қалай тоңбау керек

Қабаттап киініңіз: термоіш киім, флис, жел өтпейтін күрте мен шалбар, қалың табанды жылы аяқ киім. Ашық мұзда жел жағадағыдан күшті — шатырдың немесе желден қорғайтын қалқанның тасасына отырыңыз. Су болған қолғапты бірден ауыстырыңыз.

> Қыста кейбір су айдындарында балық аулауға тыйым мен шектеулер болады. Шығар алдында өз су айдыныңыз үшін оларды тексеріңіз — олар Dalada картасында бар.$md$,
   $md$In winter fish gather in schools and move little, so the main task is to find them. Drill several holes at different depths and don't sit over an empty one for more than 10–15 minutes.

Ice comes first: which ice holds and what to do if you fall through — see "Ice safety".

## What to bring

- **An ice auger.** 100–110 mm is enough for perch and roach; for zander and pike 130–150 mm is handier.
- **Ice rods** — short, with a spring tip; jigs, spoons or balance lures for them.
- **A skimmer** to clear ice chips from the hole.
- **A box or stool** and a mat for your feet.
- **An ice chisel, ice picks and a rope** — always.
- Spare warm socks and mittens, a thermos, a charged phone.

## Where to look for fish

- **First ice** (usually December): fish are still active and hold where they were in autumn — on drop-offs, ledges and the edge of the reeds.
- **Midwinter** (January–February): ice and snow get thicker and the water holds less oxygen. Fish move deeper and stay closer to current — near the channel and river mouths.
- **Last ice** (March): fish wake up again and come closer to the shore. The ice is at its most treacherous — test every step.

## Tackle and retrieve

- **The jig (mormyshka)** is the main winter lure for perch, roach and bream. Lower it to the bottom and lift it with small, quick twitches of the spring tip, sometimes with pauses. Bait — bloodworms or maggots.
- **Spoons and balance lures** — for perch, zander and pike. A sharp lift of 20–40 cm, a free fall, a pause; most bites come on the pause.
- **A tip-up (zherlitsa)** — for pike and zander: live bait on a hook and a flag that pops up on a bite. Set tip-ups where the depth changes. How many you may set is stated in the fishing rules.

## How to stay warm

Dress in layers: thermal underwear, fleece, windproof jacket and trousers, warm boots with thick soles. Wind on open ice is stronger than on the shore — shelter behind a tent or a windbreak. Change wet mittens straight away.

> In winter some waters have fishing bans and restrictions. Check them for your water before you go — they are on the Dalada map.$md$);
