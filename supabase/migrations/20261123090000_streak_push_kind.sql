-- Уведомление «Серия под угрозой» — отдельной миграцией: новое значение enum можно использовать только
-- после коммита.
alter type public.push_kind add value if not exists 'streak';
