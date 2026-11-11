-- «Как читать запрет на рыбалку»: ночной запрет любительских снастей (22:00–06:00) действует не только на
-- Жайыке в Западно-Казахстанской области, а во всём Жайык-Каспийском бассейне — на водоёмах ЗКО и Атырауской
-- области, на Кигаше и в Северном Каспии (приказ № 78, прил. 1, п. 21, пп. 5; зоны правила `zhaiyk_night`).
-- Исходники supabase/data/articles/reading_rules.*.md поправлены так же.

update public.articles
   set body_ru = replace(body_ru, $old$на Жайыке в Западно-Казахстанской области — с 10 апреля по 15 июня, а ночью, с 22:00 до 06:00, — круглый год.$old$, $new$на Жайыке в Западно-Казахстанской области — с 10 апреля по 15 июня, а ночью, с 22:00 до 06:00, — круглый год во всём Жайык-Каспийском бассейне: в Западно-Казахстанской и Атырауской областях, на Кигаше и в Северном Каспии.$new$)
 where id = 'reading_rules';

update public.articles
   set body_kk = replace(body_kk, $old$Батыс Қазақстан облысындағы Жайықта — 10 сәуірден 15 маусымға дейін, ал түнде, 22:00-ден 06:00-ге дейін, — жыл бойы.$old$, $new$Батыс Қазақстан облысындағы Жайықта — 10 сәуірден 15 маусымға дейін, ал түнде, 22:00-ден 06:00-ге дейін, — жыл бойы бүкіл Жайық-Каспий бассейнінде: Батыс Қазақстан және Атырау облыстарында, Кигашта және Солтүстік Каспийде.$new$)
 where id = 'reading_rules';

update public.articles
   set body_en = replace(body_en, $old$on the Zhaiyk in West Kazakhstan Region from 10 April to 15 June, and at night, from 22:00 to 06:00, all year.$old$, $new$on the Zhaiyk in West Kazakhstan Region from 10 April to 15 June, and at night, from 22:00 to 06:00, all year across the Zhaiyk-Caspian basin: in West Kazakhstan and Atyrau regions, on the Kigash and in the North Caspian.$new$)
 where id = 'reading_rules';
