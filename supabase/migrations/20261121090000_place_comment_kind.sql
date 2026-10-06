-- Комментарии к местам «друзья», «близкие» и «только я» — отдельной миграцией: новое значение enum
-- можно использовать только после коммита.
alter type public.reaction_target add value if not exists 'place';
