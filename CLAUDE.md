# Dalada — заметки для Claude

iOS-приложение для рыбалки и отдыха на природе в Казахстане; в App Store Казахстана с 2026-11-01
(какая версия сейчас — `docs/05-release/README.md`, «Выпуск обновлений»). Документы — в `docs/` (начать с `README.md` и `docs/05-release/README.md` — текущее
состояние, план после выхода и выпуск обновлений; вехи беты и их спецификации — `docs/04-beta/`).

## Язык и стиль

- Документы, комментарии в коде и тексты интерфейса — на русском. Сообщения коммитов — на английском.
- Интерфейс на трёх языках: строки только через `Localizable.xcstrings` (RU / KK / EN), без
  захардкоженного текста. Казахский — кириллица.
- `.xcstrings` пишем в формате Xcode (ключи по алфавиту, разделитель `" : "`, отступ 2, без перевода
  строки в конце) — иначе Xcode переписывает файл при сборке и появляются лишние изменения.

## Структура

- `supabase/` — миграции (`migrations/`), тесты pgTAP (`tests/database/`), `config.toml`.
- `ios/` — `project.yml` (XcodeGen; `.xcodeproj` не хранится в git), таргеты `Dalada/` и
  `DaladaWidgets/` (Live Activity), модули в `Packages/DaladaKit` (DaladaCore → DaladaUI / MapEngine /
  Backend / Persistence → Sync / TripLiveActivity → AppFeature).
- `docs/` — бриф, анализ рынка, план продукта, архитектура, путь к бете.

## База данных: правила

- **Приватность — главное.** Таблицы с координатами (`places`, `checkins`, дальше — поездки,
  уловы, медиа) напрямую отдают только свои строки. Чужие данные — только через RPC
  `SECURITY DEFINER` с `set search_path = ''`, которые вызывают `private.can_view` и огрубляют
  координаты. Фильтр по области карты для чужих приблизительных мест — по `approx_center`.
- Каждая новая таблица: `enable row level security`, `revoke all … from anon, authenticated`,
  затем явные права (для записи — только разрешённые колонки). Служебные поля выставляют триггеры.
- Внутри функций с пустым `search_path` — полные имена: `extensions.st_*`, `public.*`, `private.*`.
- Файлы (фото) — в закрытом бакете `media`, путь `<owner_id>/<media_id>.jpg`. Своей видимости у фото
  нет: оно видно тем, кто видит чекин, место и улов. Политики `storage.objects` вызывают функции из
  схемы `rls` (схема `private` для клиента закрыта, а политики выполняются от его имени).
- Любая новая таблица или RPC с чужими данными → тесты в `supabase/tests/database/` (матрица
  «зритель × объект × видимость»).
- Миграции только добавляются; уже применённые не редактировать.

## Проверки

```bash
# В облачном контейнере Docker может быть не запущен: nohup dockerd >/tmp/dockerd.log 2>&1 &
supabase db start
supabase db reset                                   # миграции с нуля
supabase db lint --level warning --fail-on warning -s public,private,rls
supabase test db                                    # pgTAP
```

iOS собирается только на Mac (Xcode 26, iOS 26): `cd ios && xcodegen generate`. Хуки в `.githooks/`
(включаются `git config core.hooksPath .githooks`) пересоздают проект после `git pull`, если изменился
`ios/project.yml` или состав файлов `ios/Dalada/` и `ios/DaladaWidgets/`. Новые файлы кладём в пакет `DaladaKit`, где
генерация не нужна. На Linux можно
проверить синтаксис (`swiftc -parse`) и модули без UI (`DaladaCore`, `Persistence`, `Sync`, `Backend`) отдельным
пакетом: у `DaladaKit` платформа только iOS, поэтому для Linux — свой `Package.swift` со ссылками на
папки исходников.

Настоящую сборку приложения и тесты пакета делает GitHub Actions на macOS (`.github/workflows/ios.yml`,
в том числе на ветках `claude/**`). Код iOS попадает в `main` только после зелёной сборки на рабочей
ветке. Сборка в TestFlight — `.github/workflows/testflight.yml` (вручную, см. `docs/04-beta/testflight.md`);
обновление в App Store — `docs/05-release/README.md`, «Выпуск обновлений» (сначала поднять
`MARKETING_VERSION`).

## Компоненты интерфейса: DesignKit или Dalada

Дизайн-система — пакет [DesignKit](https://github.com/dkicekeeper/DesignKit) (общий с Tenra). Перед
тем как писать новый компонент, ищи готовый в DesignKit: Gallery в TestFlight (у каждого компонента —
стили, состояния и скелетон) и `docs/design-system.md` в DesignKit (§0 — полный список). Что уже
есть для задач Dalada:

| Нужно | В DesignKit |
|---|---|
| Кнопки, карточки, строки | `DSButton` (иконка, загрузка, роль, размер), `cardStyle`, `UniversalRow` (деталь — `config: .info, accessory: .info(…)`), `DisclosureChevron` |
| Строка своего предмета | `ItemRow` (3.6.0): значок в кружке (`.symbol`) или сверху (`.glyph`), заголовок, описание, строки фактов `MetaLine` («12 окт. · 14,2 км · 3 ч», через «·»; ярлыки со значками — `separator: .space`), аксессуар справа; так нарисованы поездки, места, статьи, снаряжение. Факты под заголовком в других местах — тоже `MetaLine` |
| Очередь отправки | `PendingItemCard` (3.6.0): «ждёт отправки» / «не удалось отправить» с «Повторить» и «Удалить», содержимое — слотом; `discardConfirmation:` — свой вопрос перед удалением (поездки) |
| Бейджи, оценки, числа | `Badge`, `TrendBadge`, `StatTile`, `StatsStrip`, `StreakCard`, `Rating` / `RatingPicker`, сводка оценок `RatingSummary` (4.1.0: средняя, звёзды, полоски по звёздам) |
| Выбор | `ChipPicker` (`allTitle:` — чип «Все», `inset: AppSpacing.lg` — в карточке формы), `SegmentedPicker`, `SelectionIndicator` |
| Загрузка, пусто, ошибка | скелетоны (ниже), `EmptyState`, `RecommendationBox`, `LinearProgressBar(value:)`; низ списка, который грузится страницами, — `LoadMoreFooter(state:onLoad:)` (4.1.0: сам просит следующую страницу, скелетоны, «Повторить», конец), раньше конца — `.onReachEnd(of:in:threshold:)` |
| Формы | `EditSheetContainer(wrapInForm: false)` (✕ и ✓ в тулбаре, `isSaving:` — индикатор вместо ✓, `saveTitle:` — имя ✓ для VoiceOver) поверх `ScrollView` с карточками `FormSection` (с DesignKit 8.0.0 — стекло, разделители под текстом строк рисует сама секция, `Divider()` между строками не ставим; чипы с `inset:` и ленты фото с `.fullWidthRow()` идут под край карточки); строки `FormTextField(style: .row / .rowMultiline)` и `UniversalRow` с аксессуаром (7.0.0, одна строка вместо двенадцати): `.menu`, `.picker` (длинный список с поиском), `.stepper`, `.date`, `.slider`, `.toggle`, `.action`, `.checkmark`, `role: .destructive` для удаления; `config` по умолчанию `.standard` (карточка); подпись-строка для `PhotosPicker` — `UniversalRow` без аксессуара с `.contentShape(Rectangle())`; ошибки — `InlineStatusText`; у поля с лимитом в модели — `limit:` (4.1.0, `FormTextField` и `MessageComposer`: «980/1000» с 80% лимита). Системный `Form` в новых экранах не используем |
| Экраны и списки | с DesignKit 8.0.0 — один вид: белая страница, `ScrollView` из стеклянных `FormSection` и карточек (`List` не используем, кроме лент карточек: отзывы, обсуждения, комментарии). Свои вещи (экипировка, чеклисты, зоны) — `CardList(layout: .section)` с одним набором действий: тап открывает, долгое нажатие — «Изменить» и «Удалить» (`common.edit` / `common.delete`, удаление с подтверждением), в панели `.cardListToolbar` — выбор нескольких (`common.deleteSelectedConfirm`), свой порядок и «+». Смахиваний нет. Свой порядок — `sort_order` у `gear_items` и `checklists` (`ListsStore.moveGear` / `moveOwnLists`). Строка-кнопка или ссылка в секции ставит `.rowDividerInset(…)` на себя (метка не передаёт отступ наружу; `ItemRowMetrics.symbolInset` — после кружка `ItemRow` или аватара) |
| Поиск | системный `.searchable`; недавние запросы и подсказки под полем — `.dsSearchSuggestions` (3.5.0), недавние запросы экран хранит в `@AppStorage` под своим ключом (`places.recentSearches`, `friends.recentSearches`) |
| Заголовки разделов | `SectionHeader`; с 3.2.0 он рисует `systemImage` в любом стиле (раньше только в `.large`), поэтому заголовки Dalada — без значка, пока он не нужен на экране |
| Люди и сообщество | `Avatar`, `PersonRow` (`style: .card` — шапка профиля), `CommentRow`, `ThreadCard`, `ReviewCard`, `ReactionButton`, поле сообщения `MessageComposer` |
| Достижения и прогресс | `AchievementMedal`, `AchievementTile`, `AchievementProgressRow`, `ChecklistRow` / `ChecklistSummaryRow` |
| Фото | `PhotoTile`, `PhotoStrip`, `PhotoGrid`, `PhotoCarousel`, `PhotoViewer` (с масштабом); фото по ссылке — `RemotePhoto` (скелетон, пока грузится; грузит `PhotoCache` через `DesignKitPhotoLoader`, подключён в `AppBootstrap`) |
| Контент | `ThumbnailCard` / `ThumbnailRow`, `ArticleBody` (статьи), `ExpandableText`, `ActivityTimeline`, `MonthCalendar` |
| Остальное | картинки для Stories — `ShareCardSheet` / `ShareCardFrame` со стилем `ShareCard.Style.dalada`; мини-плеер записи — `LiveSessionBar`; офлайн-карты — `DownloadRow`; вопрос и праймер перед системным запросом разрешения — `PromptSheet`; онбординг — `OnboardingPager` / `OnboardingPage`; меню «+» на карте — `GlassActionMenu` |
| Цвета на карте | `AppColors.Palette` (3.7.0): глубокие оттенки с `UIColor`, одинаковые в обеих темах, белый символ на них читается; какой тип места или слой какого цвета — `MapEngine/MapColors.swift`. Зоны запретов — токены статусов (`AppColors.Status`). Системные цвета (`.systemTeal` и т. п.) на карте не используем |
| Эффекты | `docs/motion.md` DesignKit: `.celebration`, `.completionMoment`, `.holographic` + `.interactiveTilt`, `.dissolve`, `AuroraBackground`, `.spotlight` и другие |
| Время, пояснения, озвучивание (8.9.0) | когда было — `RelativeTime(date)` («5 мин назад» обновляется само, давнее — датой; текстом — `Formatting.relativeTime`), сколько идёт — `RelativeTime(start, style: .clock)`; ⓘ с пояснением к показателю — `.infoTip(текст, title:)`; выбор из длинного списка с поиском и «Создать» — `SearchablePicker`; итог действия для VoiceOver — `AccessibilityAnnouncer.announce(String(localized: "common.saved"))`; текст статуса на бледной подложке — `AppColors.Status.*Text` / `AppColors.readable(цвет)` |

Своё — только если в DesignKit нет подходящего (и тогда — сначала PR в DesignKit, см. ниже).

Значения дизайна — только токены DesignKit: `AppColors` (и `AppColors.Palette` для карты),
`AppTypography`, `AppSpacing`, `AppRadius`, `AppIconSize`, `AppAnimation`. Литералы (`Color(red:)`,
`.orange`, `.font(.title2)`, `.font(.system(size: 14))`, `.padding(12)`, `spacing: 6`,
`cornerRadius: 8`, `.easeInOut(duration:)`), а также `.swipeActions` и системный `Form` ловит
`scripts/designkit_lint.sh` (проверки DesignKit той версии, на которой собрано приложение; с
8.9.0 вместо своих `design_lint.py` и `section_rows_lint.py`), задача «Design lint» в CI
(`ios.yml`). Падает только на значениях сверх
`scripts/design-lint-baseline.json`; в базе намеренно два файла: картинка для Stories
(`ShareCardViews`, холст фиксированного размера) и Live Activity (`TripLiveActivity`, системные
стили текста по HIG). Оправданное исключение — `// design-lint:ignore <причина>` в той же
строке (символ размером с текст, прицел поверх карты). Стало меньше —
`scripts/designkit_lint.sh tokens --update-baseline`.

Строки стеклянной секции (`FormSection`, `CardList(layout: .section)`) стоят вплотную, поэтому
каждая отступает сама: строки DesignKit — да (`UniversalRow`; `ItemRow` 12 pt и `ChecklistRow`
8 pt с DesignKit 8.1.0, в стопке со своими промежутками — `verticalPadding: 0`), своя строка —
`.padding(.vertical, AppSpacing.md)`. Кнопка или ссылка вокруг строки со значком слева несёт
`.rowDividerInset(_:)` (метка не передаёт отступ наружу; для `ItemRow` с `.symbol` —
`ItemRowStyle.standard.symbolDividerInset`). Это проверяет тот же `scripts/designkit_lint.sh`
в задаче «Design lint»; исключение — `// section-rows-lint:ignore <причина>` на первой
строке ряда (сводка погоды «сейчас»).

Движение по правилам DesignKit (`docs/motion.md`): анимации — пружинами `AppAnimation.snappy`
(ответ на касание) и `.smooth` (меняется содержимое), без голого `withAnimation {}`; появление —
`.riseIn` (карточка, подсказка) и `.popIn` (чип, значок); данные сменяют скелетон через
`.transition(.skeletonReveal)` у содержимого, `.transition(.opacity)` у скелетона и
`.animation(AppAnimation.smooth, value: <идёт загрузка>)` на контейнере; то, что идёт сейчас, —
`.symbolPulse(.breathe)` (трансляция) и `.symbolPulse(.working)` (отправка, поиск); итог
сохранения — `HapticManager.play(.confirm)` / `.fail`. Меню «+» на карте — `GlassActionMenu`.

У каждого компонента DesignKit с данными есть скелетон `<Имя>Skeleton` той же формы: пока данные
грузятся, показывай его на месте компонента, а не `ProgressView()`. Строка без своего скелетона —
`SkeletonRow`; на скелетон целиком — `.skeletonLoadingLabel()` (VoiceOver читает его одним элементом, ключ `skeleton.loading`).

Компонент идёт в DesignKit, если выполнены оба условия (правило «двух потребителей» отменено
владельцем в октябре 2026: общим делается всё, что может быть общим, даже если нужно одному
приложению):
1. **Не знает данных приложения**: принимает текст, числа, даты, цвета, иконки, замыкания и
   `@ViewBuilder`-слоты — никаких `Place`, `Trip`, `Catch`, сторов и сервисов. Если зависимость от
   модели можно заменить параметром — тоже DesignKit, а переходник (`RuleStatus` → `Badge`)
   остаётся здесь маленькой обёрткой.
2. **Отвечает на «как выглядит», а не «что значит»**: карточка, строка, бейдж, выбор — да;
   «карточка улова», «форма чекина» — нет.

Перенос — PR в DesignKit по его чеклисту (CLAUDE.md DesignKit): нейтральное имя и API, скелетон,
экземпляр в Gallery, снапшот-тест. Здесь остаётся тонкий переходник со старым именем, который
отдаёт модели Dalada в параметры и слоты.

Признаки, что компонент остаётся в Dalada: в названии слово предметной области (Place, Trip,
Catch, Rule, Gear), или он сам загружает данные и управляет навигацией. Новая версия DesignKit
приходит сама (workflow **DesignKit update**). Что добавлено и изменилось в каждой версии и как на
неё перейти: [CHANGELOG.md](https://github.com/dkicekeeper/DesignKit/blob/main/CHANGELOG.md)
DesignKit (тот же текст: её release notes и экран Updates в Gallery). Визуальные изменения в
разделе **Changed**, замены старого на новое в **Migration**.

## Секреты

`ios/Config/Secrets.xcconfig` (хост и publishable key Supabase) — не в git, пример —
`Secrets.example.xcconfig`. Service role key — никогда в приложении и в репозитории.

<!-- designkit:agents:start -->
<!-- From DesignKit 8.11.0, docs/agents.md. Do not edit here: the DesignKit update workflow rewrites it. -->

## DesignKit for an app's agent

The short version of DesignKit's rules for a session working in Tenra or Dalada (8.9.0, benchmark
round 4: Astryx's `init`, which writes such a block into an app's AGENTS.md). Each app's
**DesignKit update** workflow puts this file into the app's CLAUDE.md between the
`designkit:agents` markers when it moves the pin (`scripts/sync_agents_block.py`), so it always
matches the version the app builds with. Do not edit the block in the app; change it here.

### Look a component up

- `docs/components.md` in the DesignKit checkout: one entry per component (`### Name`), what it is
  for, its initialisers, rules, do and don't, its skeleton. `docs/components.json` is the same as
  data. The full rules: `docs/design-system.md`.
- The Gallery app (TestFlight) shows every component with its parameters and states.
- A missing component goes to DesignKit by PR (CLAUDE.md, "Porting a component"); the app keeps a
  thin adapter over its model.

### The rules

1. Tokens, never raw values: `AppColors`, `AppTypography`, `AppSpacing`, `AppRadius`,
   `AppIconSize`, `AppAnimation` / `AppMotion`. Status text is `AppColors.Status.*Text` (4.5:1);
   a colour of your own as text is `AppColors.readable(color)` on `AppColors.pale(color)`.
2. Every symbol is an `Icon`: a glyph under 44 pt, a tile on its plate from 44 pt. iOS's own bars,
   menus, tabs and segments, and a symbol inside a line of text, stay `Image` / `Label`.
3. A form or settings list is `FormSection` glass cards of `UniversalRow(_:icon:accessory:)`; the
   section draws the dividers. No system `Form`.
4. A list of things a person keeps is a `CardList`: a tap opens, a long press shows Edit and
   Delete, the toolbar selects, reorders and adds. No swipe actions.
5. Every view that shows data has a skeleton (`<Name>Skeleton`); a list that loads pages ends in
   `LoadMoreFooter`.
6. An outcome that comes and goes is spoken: `MessageBanner` and the failure states of
   DesignKit's components do it; an app's own outcome calls `AccessibilityAnnouncer.announce(_:)`.
7. Motion through DesignKit (`AppMotion` springs, `.popIn`, `.riseIn`, effects); everything stops
   under Reduce Motion and `.designKitMotion(false)`.

### What a screen needs → the component

| Need | Component |
|---|---|
| A button | `DSButton` (`.dsButton` for a custom label) |
| A form, settings | `FormSection` + `UniversalRow(accessory: .toggle / .menu / .picker / .date / .stepper / .slider / .navigation / .action / .info)` |
| A list of the person's things | `CardList` (a card per item, or rows in one card), `ItemRow` + `MetaLine` |
| Pick from a long list, with search and "Create" | `SearchablePicker` |
| Pick from a few | `UniversalRow(accessory: .menu)`, `ChipPicker`, `SegmentedPicker` |
| A section title | `SectionHeader` |
| Money | `FormattedAmountText`, `AmountRow`, `AmountInput` / `CurrencyAmountInput`, `LiveAmountText` |
| When something happened, how long it runs | `RelativeTime` (`.relative`, `.elapsed`, `.clock`) |
| Explain a number | `InfoTip` / `.infoTip(_:title:)` |
| A value over what was tapped, a coachmark | `Tooltip`, `.spotlight` |
| A state that lasts | `StatusBanner` |
| An outcome that comes and goes | `MessageBanner` |
| Nothing here, or loading failed | `EmptyState` (`.error` with Retry) |
| Loading | the component's `<Name>Skeleton`, `.skeletonReveal` when it gives way |
| A chat | `MessageBubble` (`markdown:`, `time:`, `status:`), `ConversationDivider`, `MessageComposer`, `TypingIndicator`, `SuggestionChips` |
| Charts | `LineChart`, `BarChart`, `ChartSwitcher`, `Sparkline`, `OrbChart`, `CalendarHeatmap` (docs/charts.md) |
| Progress | `ProgressRing`, `LinearProgressBar`, `LimitProgressCard`, `StepTracker` |
| People | `Avatar`, `AvatarGroup`, `PersonRow`, `CommentRow` |
| Photos | `RemotePhoto`, `PhotoTile`, `PhotoGrid`, `PhotoCarousel`, `PhotoViewer` |
| Edit sheet | `EditSheetContainer`, `EditableHero`, `AmountEntrySheet` |
| A moment of success | `.celebration`, `.completionMoment` |

### Check before pushing

```bash
python3 <DesignKit>/scripts/designkit_lint.py all --source <the app's Swift folders>
```

`tokens` finds raw design values, swipe actions and the system `Form` (against the app's
`scripts/design-lint-baseline.json`); `section-rows` finds section rows without their own padding
or divider inset. A major DesignKit version: `scripts/migrate.py --from <old> --to <new> --source …`
rewrites what it can and leaves `TODO(DesignKit X.0)` where `docs/migration-X.0.md` needs a person.

<!-- designkit:agents:end -->
