---
status: ready
type: chore
priority: 3
size: s
created: 2026-11-26
updated: 2026-11-26
---
# Старые пути документов в трёх файлах и в миграциях

Зачем: при переезде документов на стандарт (2026-11-26) три файла не тронуты, потому что их
изменение в `main` само запускает отправку текстов в App Store Connect или деплой функций:
`appstore/listing.py`, `.github/workflows/appstore-listing.yml`, `.github/workflows/functions.yml`.
В их комментариях остались пути вида `docs/05-release/…` и `docs/04-beta/…`.

Готово, когда:
- при следующей содержательной правке каждого из трёх файлов пути в комментариях заменены на
  новые (`docs/release.md`, `docs/promotion.md`, `docs/testflight.md`, `docs/archive/plans/M6-beta-readiness.md`).

Заметки: применённые миграции SQL (`supabase/migrations/`) не правятся по правилу репозитория; их
комментарии со старыми путями остаются как есть. Соответствие старых путей новым — в описании PR #85.
