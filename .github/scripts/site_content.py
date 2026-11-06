"""Страницы сайта из данных Dalada для поиска и ссылок из постов (docs/05-release/promotion.md,
«Сайт и поиск»):

- a/ — статьи редакции (public.articles): a/<id>/ по-русски, a/<id>/kk.html и en.html; список — a/,
  a/kk.html, a/en.html;
- rules/ — запреты на лов по бассейнам (public.regulations и public.rule_zones) с тем, что действует
  сегодня по времени Алматы; rules/kk.html и rules/en.html.

Данные — по ключу гостя, как у страниц мест: только опубликованное и публичное. Текст из базы
вставляем только экранированным; разметка статей — то же подмножество Markdown, что в приложении
(supabase/data/articles/README.md). Сборка раз в день (pages.yml), поэтому «сейчас действуют» свежее.
"""
import datetime
import html
import math
import json
import re
import urllib.request

LANGS = ("ru", "kk", "en")
HTML_LANG = {"ru": "ru", "kk": "kk", "en": "en"}
LANG_NAMES = {"ru": "Русский", "kk": "Қазақша", "en": "English"}

CATEGORIES = {
    "safety": {"ru": "Безопасность", "kk": "Қауіпсіздік", "en": "Safety"},
    "rules_ethics": {"ru": "Правила и этика", "kk": "Ережелер мен әдеп", "en": "Rules and ethics"},
    "tackle": {"ru": "Снасти и приманки", "kk": "Құралдар мен жемдер", "en": "Tackle and lures"},
    "knots": {"ru": "Узлы", "kk": "Түйіндер", "en": "Knots"},
    "cooking": {"ru": "Приготовление улова", "kk": "Олжаны пісіру", "en": "Cooking your catch"},
    "places_seasons": {"ru": "Места и сезоны", "kk": "Орындар мен маусымдар", "en": "Places and seasons"},
    "technique": {"ru": "Техника ловли", "kk": "Аулау тәсілдері", "en": "Fishing techniques"},
    "other": {"ru": "Разное", "kk": "Әртүрлі", "en": "Other"},
}

# Порядок бассейнов на странице: сначала общие правила, потом с юго-востока по кругу.
BASINS = [
    ("kazakhstan", {"ru": "Вся страна", "kk": "Бүкіл ел", "en": "Whole country"}),
    ("balkhash_alakol", {"ru": "Балхаш-Алакольский бассейн", "kk": "Балқаш-Алакөл бассейні", "en": "Balkhash-Alakol basin"}),
    ("zaysan_ertis", {"ru": "Зайсан-Ертисский бассейн", "kk": "Зайсан-Ертіс бассейні", "en": "Zaysan-Ertis basin"}),
    ("esil", {"ru": "Есильский бассейн", "kk": "Есіл бассейні", "en": "Esil basin"}),
    ("nura_sarysu", {"ru": "Нура-Сарысуский бассейн", "kk": "Нұра-Сарысу бассейні", "en": "Nura-Sarysu basin"}),
    ("tobyl_torgay", {"ru": "Тобыл-Торгайский бассейн", "kk": "Тобыл-Торғай бассейні", "en": "Tobyl-Torgay basin"}),
    ("zhaiyk_caspian", {"ru": "Жайык-Каспийский бассейн", "kk": "Жайық-Каспий бассейні", "en": "Zhaiyk-Caspian basin"}),
    ("aral_syrdarya", {"ru": "Арало-Сырдарьинский бассейн", "kk": "Арал-Сырдария бассейні", "en": "Aral-Syr Darya basin"}),
    ("shu_talas", {"ru": "Шу-Таласский бассейн", "kk": "Шу-Талас бассейні", "en": "Shu-Talas basin"}),
]

MONTHS = {
    "ru": ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября",
           "ноября", "декабря"],
    "kk": ["қаңтар", "ақпан", "наурыз", "сәуір", "мамыр", "маусым", "шілде", "тамыз", "қыркүйек", "қазан",
           "қараша", "желтоқсан"],
    "en": ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
           "November", "December"],
}

T = {
    "ru": {
        "about": "Dalada — карта рыбалки и отдыха на природе по всему Казахстану: запреты на лов на карте, места, "
                 "свежие отчёты и карта без сети. Бесплатно, для iPhone.",
        "store": "Скачать в App Store", "home": "Dalada", "articles": "Статьи и советы", "rules": "Запреты на рыбалку",
        "articles_lead": "Советы редакции Dalada: безопасность, снасти, узлы, уха и как вести себя на природе.",
        "minutes": "мин чтения", "back": "Все статьи",
        "rules_title": "Запреты на рыбалку в Казахстане {year}: сроки по бассейнам",
        "rules_h1": "Запреты на рыбалку в Казахстане — {year}",
        "rules_lead": "Сроки нерестовых запретов, зоны покоя и запрещённые способы лова по всем бассейнам — по приказу "
                      "Минсельхоза РК. Проверено {verified}. Границы зон и что действует у конкретного места — на "
                      "карте в приложении Dalada.",
        "rules_desc": "Нерестовые запреты {year} по всем бассейнам Казахстана: сроки, водоёмы, зоны покоя и источники.",
        "now": "Что действует сегодня, {day}", "now_none": "Сезонных запретов сегодня нет — круглогодичные "
               "правила ниже действуют всегда.",
        "all_year": "круглый год", "amateur": "касается удочек, спиннингов и других любительских орудий",
        "source": "Источник", "verified": "проверено",
        "disclaimer": "Сведения справочные: перед поездкой сверяйтесь с первоисточником. Границы зон в приложении "
                      "приблизительные — текст правила важнее линии на карте.",
    },
    "kk": {
        "about": "Dalada — бүкіл Қазақстан бойынша балық аулау мен табиғаттағы демалыс картасы: картадағы аулауға "
                 "тыйымдар, орындар, жаңа есептер және байланыссыз карта. Тегін, iPhone үшін.",
        "store": "App Store-дан жүктеу", "home": "Dalada", "articles": "Мақалалар мен кеңестер",
        "rules": "Балық аулауға тыйымдар",
        "articles_lead": "Dalada редакциясының кеңестері: қауіпсіздік, құралдар, түйіндер, сорпа және табиғаттағы әдеп.",
        "minutes": "мин оқу", "back": "Барлық мақалалар",
        "rules_title": "Қазақстандағы балық аулауға тыйымдар {year}: бассейндер бойынша мерзімдер",
        "rules_h1": "Қазақстандағы балық аулауға тыйымдар — {year}",
        "rules_lead": "Барлық бассейндер бойынша уылдырық шашу кезеңіндегі тыйымдар, тыныштық аймақтары және тыйым "
                      "салынған аулау тәсілдері — ҚР Ауыл шаруашылығы министрлігінің бұйрығы бойынша. Тексерілді: "
                      "{verified}. Аймақ шекаралары мен нақты орында не әрекет ететіні — Dalada қосымшасының картасында.",
        "rules_desc": "Қазақстанның барлық бассейндеріндегі {year} жылғы тыйымдар: мерзімдер, су айдындары, дереккөздер.",
        "now": "Бүгін не әрекет етеді, {day}", "now_none": "Бүгін маусымдық тыйымдар жоқ — төмендегі жыл бойғы "
               "ережелер әрқашан әрекет етеді.",
        "all_year": "жыл бойы", "amateur": "қармақтарға, спиннингтерге және басқа әуесқойлық құралдарға қатысты",
        "source": "Дереккөз", "verified": "тексерілді",
        "disclaimer": "Мәліметтер анықтамалық: сапар алдында дереккөзбен салыстырыңыз. Қосымшадағы аймақ шекаралары "
                      "шамамен — ереже мәтіні картадағы сызықтан маңыздырақ.",
    },
    "en": {
        "about": "Dalada is a map for fishing and the outdoors across Kazakhstan: fishing bans on the map, places, "
                 "fresh reports and an offline map. Free, for iPhone.",
        "store": "Download on the App Store", "home": "Dalada", "articles": "Articles and tips",
        "rules": "Fishing bans",
        "articles_lead": "Tips from the Dalada editors: safety, tackle, knots, fish soup and outdoor manners.",
        "minutes": "min read", "back": "All articles",
        "rules_title": "Fishing bans in Kazakhstan {year}: dates by basin",
        "rules_h1": "Fishing bans in Kazakhstan — {year}",
        "rules_lead": "Spawning bans, rest zones and banned methods in every basin, from the order of the Ministry of "
                      "Agriculture of Kazakhstan. Checked on {verified}. Zone borders and what applies at a given place "
                      "are on the map in the Dalada app.",
        "rules_desc": "Spawning bans {year} in every basin of Kazakhstan: dates, waters, rest zones and sources.",
        "now": "In force today, {day}", "now_none": "No seasonal bans today — the year-round rules below always "
               "apply.",
        "all_year": "all year", "amateur": "applies to rods, spinning and other amateur gear",
        "source": "Source", "verified": "checked on",
        "disclaimer": "For reference only: check the original source before a trip. Zone borders in the app are "
                      "approximate — the text of a rule matters more than a line on the map.",
    },
}

STYLE = """    :root { --text: #1d1d1f; --muted: #6e6e73; --body: #333; --bg: #ffffff; --link: #0066cc; --line: #e5e5e7; --box: #f5f5f7; --accent: #2E8B57; }
    @media (prefers-color-scheme: dark) {
      :root { --text: #f5f5f7; --muted: #a1a1a6; --body: #d2d2d7; --bg: #000000; --link: #2997ff; --line: #333336; --box: #1c1c1e; --accent: #3CB371; }
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.7;
           color: var(--text); background: var(--bg); padding: 24px 16px; max-width: 720px; margin: 0 auto; }
    nav.top { font-size: 14px; margin-bottom: 24px; display: flex; flex-wrap: wrap; gap: 4px 12px; }
    h1 { font-size: 30px; font-weight: 800; margin-bottom: 8px; line-height: 1.2; }
    h2 { font-size: 21px; font-weight: 700; margin-top: 32px; margin-bottom: 10px; line-height: 1.3; }
    h3 { font-size: 17px; font-weight: 600; margin-top: 20px; margin-bottom: 6px; }
    p, li { font-size: 16px; color: var(--body); margin-bottom: 10px; }
    ul, ol { padding-left: 22px; margin-bottom: 10px; }
    .lead { font-size: 17px; color: var(--muted); margin-bottom: 20px; }
    .meta { font-size: 14px; color: var(--muted); margin-bottom: 6px; }
    .note { border-left: 3px solid var(--accent); padding: 4px 0 4px 14px; margin: 14px 0; }
    .box { background: var(--box); border-radius: 12px; padding: 16px 20px; margin: 28px 0; }
    .rule { border-top: 1px solid var(--line); padding-top: 4px; }
    a { color: var(--link); }
    .footer-links { margin-top: 24px; font-size: 14px; }"""


# --- Данные ---------------------------------------------------------------------------------------

def get(url, key, path):
    request = urllib.request.Request(url + "/rest/v1/" + path, headers={"apikey": key, "Authorization": "Bearer " + key})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def fetch_articles(url, key):
    columns = ",".join(["id", "category", "published_on", "sort_order", "updated_at"]
                       + [f + "_" + lang for f in ("title", "summary", "body") for lang in LANGS])
    return get(url, key, "articles?select=" + columns + "&order=sort_order,id")


def fetch_rules(url, key):
    regulations = get(url, key, "regulations?select=*&order=sort_order,id")
    zones = get(url, key, "rule_zones?select=id,name_ru,name_kk,name_en")
    return regulations, {zone["id"]: zone for zone in zones}


# --- Разметка статей (как в приложении) ----------------------------------------------------------

def inline(text):
    """Строка Markdown → HTML: **жирный**, *курсив*, [ссылка](https://…). Сначала экранируем."""
    links = []

    def keep(match):
        links.append('<a href="' + html.escape(match.group(2), quote=True) + '">' + html.escape(match.group(1)) + "</a>")
        return "\u0000" + str(len(links) - 1) + "\u0000"

    text = re.sub(r"\[([^\]]+)\]\((https://[^)\s]+)\)", keep, text)
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![*\w])\*(?!\s)(.+?)(?<!\s)\*(?![*\w])", r"<em>\1</em>", text)
    return re.sub("\u0000(\\d+)\u0000", lambda m: links[int(m.group(1))], text)


def markdown(source):
    """Подмножество Markdown статей: ## и ###, абзацы, «- » и «1. », выноски «> »."""
    out, paragraph, items, kind, note = [], [], [], None, []

    def flush():
        nonlocal paragraph, items, kind, note
        if paragraph:
            out.append("<p>" + inline(" ".join(paragraph)) + "</p>")
        if items:
            out.append("<" + kind + ">" + "".join("<li>" + inline(i) + "</li>" for i in items) + "</" + kind + ">")
        if note:
            out.append('<div class="note"><p>' + inline(" ".join(note)) + "</p></div>")
        paragraph, items, kind, note = [], [], None, []

    for raw in source.splitlines():
        line = raw.strip()
        if not line:
            flush()
        elif line.startswith("### "):
            flush()
            out.append("<h3>" + inline(line[4:]) + "</h3>")
        elif line.startswith("## "):
            flush()
            out.append("<h2>" + inline(line[3:]) + "</h2>")
        elif line.startswith("> "):
            if paragraph or items:
                flush()
            note.append(line[2:])
        elif re.match(r"^[-*] ", line):
            if kind != "ul":
                flush()
                kind = "ul"
            items.append(line[2:])
        elif re.match(r"^\d+\. ", line):
            if kind != "ol":
                flush()
                kind = "ol"
            items.append(re.sub(r"^\d+\. ", "", line))
        else:
            if items or note:
                flush()
            paragraph.append(line)
    flush()
    return "\n".join(out)


# --- Страница ------------------------------------------------------------------------------------

def page(lang, title, description, canonical, alternates, body, app_store_url, app_store_id, nav):
    """Страница сайта: шапка с языками, текст, блок App Store, подвал."""
    links = "".join('\n  <link rel="alternate" hreflang="' + code + '" href="' + html.escape(url, quote=True) + '">'
                    for code, url in alternates.items())
    banner = ('\n  <meta name="apple-itunes-app" content="app-id=' + app_store_id + '">') if app_store_id else ""
    langs = " ".join('<a href="' + html.escape(url, quote=True) + '" lang="' + code + '">' + LANG_NAMES[code] + "</a>"
                     for code, url in alternates.items() if code != lang)
    store = ('<p><a href="' + html.escape(app_store_url, quote=True) + '"><strong>' + T[lang]["store"]
             + "</strong></a></p>") if app_store_url else ""
    return f"""<!DOCTYPE html>
<html lang="{HTML_LANG[lang]}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{html.escape(title)}</title>
  <meta name="description" content="{html.escape(description, quote=True)}">
  <link rel="canonical" href="{html.escape(canonical, quote=True)}">{links}
  <meta property="og:type" content="article">
  <meta property="og:site_name" content="Dalada">
  <meta property="og:title" content="{html.escape(title, quote=True)}">
  <meta property="og:description" content="{html.escape(description, quote=True)}">
  <meta property="og:url" content="{html.escape(canonical, quote=True)}">{banner}
  <style>
{STYLE}
  </style>
</head>
<body>
  <nav class="top">{nav} {langs}</nav>
{body}
<div class="box">
  <p>{html.escape(T[lang]["about"])}</p>
  {store}
</div>
</body>
</html>
"""


def nav_links(root, lang):
    suffix = "" if lang == "ru" else lang + ".html"
    return ('<a href="' + root + ("" if lang == "ru" else "#" + lang) + '">' + T[lang]["home"] + "</a> · "
            + '<a href="' + root + "rules/" + suffix + '">' + T[lang]["rules"] + "</a> · "
            + '<a href="' + root + "a/" + suffix + '">' + T[lang]["articles"] + "</a> ·")


def localized(row, field, lang):
    return (row.get(field + "_" + lang) or "").strip()


def page_name(lang):
    return "index.html" if lang == "ru" else lang + ".html"


def page_url(base_url, lang):
    return base_url if lang == "ru" else base_url + lang + ".html"


# --- Статьи --------------------------------------------------------------------------------------

def article_pages(articles, origin, base, app_store_url_for, app_store_id):
    """{относительный путь: html} статей и списков статей; плюс адреса для sitemap."""
    files, sitemap = {}, []
    root = origin + base
    for article in articles:
        langs = [lang for lang in LANGS if localized(article, "title", lang) and localized(article, "body", lang)]
        folder = root + "a/" + article["id"] + "/"
        alternates = {lang: page_url(folder, lang) for lang in langs}
        for lang in langs:
            body_md = localized(article, "body", lang)
            # Как в приложении (Article.readingMinutes): ≈180 слов в минуту, вверх, не меньше одной.
            minutes = max(1, math.ceil(len(body_md.split()) / 180))
            category = CATEGORIES.get(article["category"], CATEGORIES["other"])[lang]
            body = "\n".join([
                '<p class="meta">' + html.escape(category) + " · " + str(minutes) + " " + T[lang]["minutes"] + "</p>",
                "<h1>" + html.escape(localized(article, "title", lang)) + "</h1>",
                '<p class="lead">' + html.escape(localized(article, "summary", lang)) + "</p>",
                markdown(body_md),
                '<p class="footer-links"><a href="' + page_url(root + "a/", lang) + '">' + T[lang]["back"] + "</a></p>",
            ])
            files["a/" + article["id"] + "/" + page_name(lang)] = page(
                lang, localized(article, "title", lang) + " — Dalada", localized(article, "summary", lang),
                alternates[lang], alternates, body, app_store_url_for("site-article"), app_store_id, nav_links(base, lang))
            sitemap.append((alternates[lang], str(article.get("updated_at") or article.get("published_on") or "")[:10]))
    index_alternates = {lang: page_url(root + "a/", lang) for lang in LANGS}
    for lang in LANGS:
        parts = ["<h1>" + T[lang]["articles"] + "</h1>", '<p class="lead">' + T[lang]["articles_lead"] + "</p>"]
        for key, names in CATEGORIES.items():
            rows = [a for a in articles if a["category"] == key and localized(a, "title", lang)]
            if not rows:
                continue
            parts.append("<h2>" + html.escape(names[lang]) + "</h2><ul>")
            for row in rows:
                href = page_url(root + "a/" + row["id"] + "/", lang)
                parts.append('<li><a href="' + href + '">' + html.escape(localized(row, "title", lang)) + "</a> — "
                             + html.escape(localized(row, "summary", lang)) + "</li>")
            parts.append("</ul>")
        files["a/" + page_name(lang)] = page(
            lang, T[lang]["articles"] + " — Dalada", T[lang]["articles_lead"], index_alternates[lang],
            index_alternates, "\n".join(parts), app_store_url_for("site-article"), app_store_id, nav_links(base, lang))
        sitemap.append((index_alternates[lang], None))
    return files, sitemap


# --- Запреты -------------------------------------------------------------------------------------

def in_period(day, rule):
    """Действует ли сезонное правило в день `day` (сроки могут переходить через Новый год)."""
    if rule.get("start_month") is None:
        return False
    start = (rule["start_month"], rule["start_day"])
    end = (rule["end_month"], rule["end_day"])
    today = (day.month, day.day)
    return start <= today <= end if start <= end else (today >= start or today <= end)


def day_text(lang, month, day):
    name = MONTHS[lang][month - 1]
    return f"{name} {day}" if lang == "en" else f"{day} {name}"


def period_text(lang, rule):
    if rule.get("start_month") is None:
        return T[lang]["all_year"]
    return day_text(lang, rule["start_month"], rule["start_day"]) + " — " + day_text(lang, rule["end_month"], rule["end_day"])


def date_text(lang, value):
    try:
        parsed = datetime.date.fromisoformat(str(value)[:10])
    except ValueError:
        return str(value)
    return day_text(lang, parsed.month, parsed.day) + " " + str(parsed.year)


def zone_names(lang, rule, zones):
    return [localized(zones[z], "name", lang) or zones[z].get("name_ru", "") for z in rule.get("zone_ids") or [] if z in zones]


def basin_name(lang, code):
    return next((names[lang] for key, names in BASINS if key == code), code)


def where(lang, rule, zones):
    """Где действует правило: зоны, а если их нет — бассейн."""
    return ", ".join(zone_names(lang, rule, zones)) or basin_name(lang, rule["basin"])


def rule_block(lang, rule, zones):
    names = zone_names(lang, rule, zones)
    meta = [period_text(lang, rule)] if rule["kind"] == "fishing_ban" or rule.get("start_month") is not None else []
    if names:
        meta.insert(0, ", ".join(names))
    if rule.get("gear") == "amateur":
        meta.append(T[lang]["amateur"])
    title = localized(rule, "title", lang) or rule["title_ru"]
    body = localized(rule, "body", lang) or rule["body_ru"]
    paragraphs = "".join("<p>" + html.escape(p.strip()) + "</p>" for p in body.split("\n") if p.strip())
    source = ('<p class="meta">' + T[lang]["source"] + ': <a href="' + html.escape(rule["source_url"], quote=True) + '">'
              + html.escape(rule["source_title"]) + "</a>, " + html.escape(rule["source_clause"]) + "; "
              + T[lang]["verified"] + " " + date_text(lang, rule["verified_on"]) + "</p>")
    return ('<div class="rule"><h3>' + html.escape(title) + "</h3>"
            + ('<p class="meta">' + html.escape(" · ".join(meta)) + "</p>" if meta else "")
            + paragraphs + source + "</div>")


def rules_pages(regulations, zones, origin, base, app_store_url_for, app_store_id, today):
    files, sitemap = {}, []
    if not regulations:
        return files, sitemap
    verified = max(str(r["verified_on"])[:10] for r in regulations)
    year = verified[:4]
    folder = origin + base + "rules/"
    alternates = {lang: page_url(folder, lang) for lang in LANGS}
    known = {code for code, _ in BASINS}
    for lang in LANGS:
        active = [r for r in regulations if in_period(today, r)]
        parts = [
            "<h1>" + html.escape(T[lang]["rules_h1"].format(year=year)) + "</h1>",
            '<p class="lead">' + html.escape(T[lang]["rules_lead"].format(verified=date_text(lang, verified))) + "</p>",
            "<h2>" + html.escape(T[lang]["now"].format(day=day_text(lang, today.month, today.day))) + "</h2>",
        ]
        if active:
            parts.append("<ul>" + "".join(
                "<li>" + html.escape(localized(r, "title", lang) or r["title_ru"]) + " — " + html.escape(where(lang, r, zones))
                + " (" + html.escape(period_text(lang, r)) + ")</li>" for r in active) + "</ul>")
        else:
            parts.append("<p>" + html.escape(T[lang]["now_none"]) + "</p>")
        for code, names in BASINS + [(b, {"ru": b, "kk": b, "en": b}) for b in sorted({r["basin"] for r in regulations} - known)]:
            rows = [r for r in regulations if r["basin"] == code]
            if not rows:
                continue
            parts.append('<h2 id="' + html.escape(code) + '">' + html.escape(names[lang]) + "</h2>")
            parts.extend(rule_block(lang, r, zones) for r in rows)
        parts.append('<p class="note">' + html.escape(T[lang]["disclaimer"]) + "</p>")
        files["rules/" + page_name(lang)] = page(
            lang, T[lang]["rules_title"].format(year=year), T[lang]["rules_desc"].format(year=year), alternates[lang],
            alternates, "\n".join(parts), app_store_url_for("site-rules"), app_store_id, nav_links(base, lang))
        sitemap.append((alternates[lang], today.isoformat()))
    return files, sitemap


def almaty_today():
    return (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=5)).date()


