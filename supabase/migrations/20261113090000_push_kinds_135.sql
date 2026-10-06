-- Уведомления к функциям сборки 135 — отдельной миграцией: новые значения enum нельзя использовать
-- в той же транзакции, где их добавили.
alter type public.push_kind add value if not exists 'live_share';
alter type public.push_kind add value if not exists 'packing_invite';
alter type public.push_kind add value if not exists 'steward';
