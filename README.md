# Dalada

**Dalada** (каз. «далада» — «на природе») — iOS-приложение для поездок на природу: рыбалка,
кэмпинг, походы в горы, дикая природа. Старт — **рыбалка по всему Казахстану** (бета начиналась
с Алматы, Алматинской области и Жетісу), дальше другие активности. Языки: русский, казахский,
английский.

**В [App Store Казахстана](https://apps.apple.com/kz/app/dalada/id6817603558)** с 2026-11-01,
бесплатно, для iPhone. Какая версия сейчас и что на проверке — [`docs/release.md`](docs/release.md). Сайт — [dkicekeeper.github.io/Dalada](https://dkicekeeper.github.io/Dalada/).

Формула продукта: **Strava** (профиль, поездки, статистика, друзья) + **Foursquare/Swarm**
(места, чекины, краудсорсинг) + локальная специфика Казахстана (водоёмы, запреты, нацпарки,
погранзона).

## Разделы приложения

| # | Вкладка | Суть |
|---|---------|------|
| 1 | **Главная** | Лента: поездки, отчёты и места друзей и свои, отзывы, обсуждения; «Сейчас на выезде» |
| 2 | **Карта** | Весь Казахстан: места, отчёты, слои (запреты на лов, нацпарки, погранзона, свои треки и фото), карты без сети, маршрут до места, запись поездки |
| 3 | **Места** | Поиск, подборки (рядом, популярные, где были друзья, редакции), сохранённые; карточка места: отчёты, отзывы (1–5), обсуждения, погода, фото |
| 4 | **Лайфхаки** | Статьи, моя экипировка, чеклисты и общие сборы |
| 5 | **Профиль** | Поездки, уловы, места, фото, статистика, рекорды, значки и серии, друзья, настройки |

## Этапы работы

| Этап | Результат | Статус |
|------|-----------|--------|
| 1. Анализ рынка и конкурентов | [`docs/market-analysis.md`](docs/market-analysis.md) | ✅ готово |
| 2. План по каждому разделу | [`docs/product-plan.md`](docs/product-plan.md) | ✅ готово, решения приняты |
| 3. Архитектура и стек | [`docs/architecture.md`](docs/architecture.md) | ✅ готово, решения приняты (Supabase, TypeScript, MapLibre) |
| 4–5. Спецификации и реализация по вехам | [`docs/archive/plans/beta-milestones.md`](docs/archive/plans/beta-milestones.md) | ✅ бета завершена: вехи M0–M34 вошли в 1.0 |
| 6. Релиз 1.0 в App Store | [`docs/release.md`](docs/release.md) | ✅ 2026-11-01 версия 1.0.0 в App Store Казахстана; дальше — R4 «После выхода» |

## Документы

- [`docs/product-brief.md`](docs/product-brief.md) — бриф продукта, принятые решения, дизайн-система
- [`docs/market-analysis.md`](docs/market-analysis.md) — рынок, конкуренты, сегменты, риски, монетизация
- [`docs/product-plan.md`](docs/product-plan.md) — план продукта: принципы, навигация, модель данных, релизы,
  планы по вкладкам и сквозным темам
- [`docs/architecture.md`](docs/architecture.md) — архитектура и стек: iOS, бэкенд на Supabase, карты, инфраструктура и переезд в РК
- [`docs/archive/plans/beta-milestones.md`](docs/archive/plans/beta-milestones.md) — бета: вехи M0–M34 и их спецификации, настройка окружения, TestFlight
- [`docs/release.md`](docs/release.md) — релиз 1.0 и **текущее состояние**: что после выхода, выпуск обновлений, решения, страница App Store и скриншоты
- [`docs/promotion.md`](docs/promotion.md) — продвижение на год: воронка, каналы, календарь по сезонам, бюджет, метрики без слежки, первые 30 дней; готовые тексты — [`promotion-texts.md`](docs/promotion-texts.md)
- [`docs/content.md`](docs/content.md) — наполнение мест: аудит, процесс, очередь и журнал волн, метрики
- [`docs/kk-proofreading.md`](docs/kk-proofreading.md) — что на казахском ещё ждёт вычитки носителем
- [`docs/naming.md`](docs/naming.md) — название: выбор Dalada и оставшиеся проверки

## Код

- [`supabase/`](supabase) — миграции базы, тесты приватности (pgTAP), Edge Function `push`, данные редакции
- [`ios/`](ios) — iOS-приложение: `project.yml` (XcodeGen) и модули `Packages/DaladaKit`
- [`map/`](map) — своя карта: стили, сборка тайлов и рельефа для Cloudflare R2
- [`appstore/`](appstore) — тексты App Store и TestFlight, скрипты App Store Connect API, рамки скриншотов
- [`docs/public/`](docs/public) — сайт на GitHub Pages: главная, политика, условия, поддержка, страницы «Поделиться»
- [`.github/workflows/`](.github/workflows) — CI, сборки, выпуск, карта, сайт, бэкапы ([список](docs/architecture-infra.md#cicd))
- Как собрать и проверить — в [`docs/archive/plans/beta-milestones.md`](docs/archive/plans/beta-milestones.md#настройка-окружения-сделано) и [`CLAUDE.md`](CLAUDE.md)

## Дизайн-система

UI строится на [DesignKit](https://github.com/dkicekeeper/DesignKit) — SwiftUI-дизайн-системе,
вынесенной из приложения Tenra (iOS 26+, Liquid Glass, шрифт Inter). Заметки о том, что из неё
переиспользуем и что придётся добавить, — в [брифе](docs/product-brief.md#дизайн-система-designkit).
