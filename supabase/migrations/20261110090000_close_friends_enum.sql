-- Видимость «Близкие» (план: docs/02-plan/README.md, релиз 1.1 — «выбранные друзья»; спецификация —
-- docs/04-beta/M21-close-friends.md). Новое значение — отдельной миграцией: в той же транзакции им
-- пользоваться нельзя.

alter type public.visibility add value if not exists 'close_friends' before 'private';
