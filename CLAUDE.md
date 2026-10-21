# Dalada — заметки для Claude

iOS-приложение для рыбалки и отдыха на природе в Казахстане. Документы — в `docs/`
(начать с `README.md` и `docs/04-beta/README.md` — текущий план по вехам).

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
ветке. Сборка в TestFlight — `.github/workflows/testflight.yml` (вручную, см. `docs/04-beta/testflight.md`).

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

Своё — только если в DesignKit нет подходящего (и тогда — сначала PR в DesignKit, см. ниже).

Значения дизайна — только токены DesignKit: `AppColors` (и `AppColors.Palette` для карты),
`AppTypography`, `AppSpacing`, `AppRadius`, `AppIconSize`, `AppAnimation`. Литералы (`Color(red:)`,
`.orange`, `.font(.title2)`, `.font(.system(size: 14))`, `.padding(12)`, `spacing: 6`,
`cornerRadius: 8`, `.easeInOut(duration:)`) ловит `python3 scripts/design_lint.py`, задача
«Design lint» в CI (`ios.yml`). Падает только на значениях сверх
`scripts/design-lint-baseline.json`; в базе намеренно два файла: картинка для Stories
(`ShareCardViews`, холст фиксированного размера) и Live Activity (`TripLiveActivity`, системные
стили текста по HIG). Оправданное исключение — `// design-lint:ignore <причина>` в той же
строке (символ размером с текст, прицел поверх карты). Стало меньше — `--update-baseline`.

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
