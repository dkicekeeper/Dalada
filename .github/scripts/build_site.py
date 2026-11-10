#!/usr/bin/env python3
"""Сборка сайта для GitHub Pages: docs/public и страницы «Поделиться» (docs/04-beta/M29-web-share.md).

- _site/s/index.html и _site/404.html — страница места, поездки, улова (данные грузит браузер);
- _site/p/<id>/index.html — статическая страница каждого публичного места с превью для Telegram
  (название, тип, описание, фото редакции);
- _site/s/config.js — адрес Supabase и публичный ключ гостя из секретов (в репозитории их нет);
- после выхода в App Store (APP_STORE_ID) — кнопка App Store вместо приглашения в бету и баннер
  Safari (Smart App Banner) на всех страницах;
- _site/a/ — статьи редакции, _site/rules/ — запреты на лов по бассейнам (site_content.py);
- _site/sitemap.xml — главная, пресс-страница, статьи, запреты и страницы мест для поисковиков
  (страницы поездок, уловов и приглашений закрыты от индексации: это записи людей);
- метки кампаний App Store Connect в ссылках на App Store (переменная репозитория APP_STORE_PT) и
  метатег Google Search Console (GOOGLE_SITE_VERIFICATION) — docs/05-release/promotion.md.

Без секретов или без сети сайт всё равно собирается — только без страниц мест, статей и запретов.
Ключ и адрес в журнал не печатаем: репозиторий публичный.
"""
import html
import json
import os
import re
import shutil
import sys
import urllib.request

import site_content

SOURCE = "docs/public"
OUTPUT = "_site"
BASE = os.environ.get("SITE_BASE", "/Dalada/")
ORIGIN = os.environ.get("SITE_ORIGIN", "https://dkicekeeper.github.io")
PHOTOS = "https://pub-06c03b3c9f2e4de7b1a196206e04c258.r2.dev"
TEMPLATE = os.path.join(SOURCE, "s", "page.template.html")
# Apple ID приложения в App Store (вышло 2026-11-01): кнопка App Store и баннер Safari вместо
# приглашения в бету (docs/05-release/README.md, R3). Пустой APP_STORE_ID в окружении — снова бета.
APP_STORE_ID = os.environ.get("APP_STORE_ID", "6817603558")
APP_STORE_URL = "https://apps.apple.com/kz/app/dalada/id" + APP_STORE_ID if APP_STORE_ID else ""
# Метки кампаний (docs/05-release/promotion.md, «Метки кампаний»): pt — токен поставщика, один на
# аккаунт разработчика (App Store Connect → Analytics → Acquisition → Campaigns → Generate Campaign
# Link), ct — вид ссылки. App Store Connect показывает по ним только суммы. Без pt — ссылки без меток.


def provider_token(raw):
    """Токен поставщика из переменной: само число, «pt=…», вся ссылка кампании из App Store Connect или
    кусок ссылки после «pt=» («128728453&ct=site»)."""
    raw = raw.strip().strip("\"'").strip()
    leading = re.fullmatch(r"([0-9]{1,20})(?:&.*)?", raw)
    if leading:
        return leading.group(1)
    found = re.search(r"(?:^|[?&\s])pt=([0-9]{1,20})(?:$|[&\s])", raw)
    return found.group(1) if found else ""


APP_STORE_PT_RAW = os.environ.get("APP_STORE_PT", "")
APP_STORE_PT = provider_token(APP_STORE_PT_RAW)
# Подтверждение сайта в Google Search Console метатегом на главной (код из Search Console).


def verification_code(raw):
    """Код Search Console: сам код или весь тег <meta name="google-site-verification" content="…">."""
    found = re.search(r"content\s*=\s*[\"']([^\"']+)[\"']", raw)
    code = (found.group(1) if found else raw.strip().strip("\"'")).strip()
    return code if re.fullmatch(r"[A-Za-z0-9_-]{10,100}", code) else ""


GOOGLE_SITE_VERIFICATION_RAW = os.environ.get("GOOGLE_SITE_VERIFICATION", "")
GOOGLE_SITE_VERIFICATION = verification_code(GOOGLE_SITE_VERIFICATION_RAW)
# Значения из переменных попадают в HTML — пропускаем только ожидаемый вид.
if APP_STORE_PT_RAW.strip() and not APP_STORE_PT:
    # Само значение не печатаем: мало ли что туда вставили.
    print("APP_STORE_PT: нужно число из pt=… ссылки кампании (например 123456789) или вся ссылка; сейчас "
          + str(len(APP_STORE_PT_RAW.strip())) + " символов без pt=<цифры> — ссылки без меток")
elif APP_STORE_PT:
    print("Метки кампаний: включены")
if GOOGLE_SITE_VERIFICATION_RAW.strip() and not GOOGLE_SITE_VERIFICATION:
    print("GOOGLE_SITE_VERIFICATION: нужен код из тега Search Console (content=\"…\") или весь тег — метатег не добавлен")
elif GOOGLE_SITE_VERIFICATION:
    print("Метатег Search Console: добавлен")

TYPES = {
    "base": "База отдыха", "campsite": "Стоянка", "fishing_spot": "Точка ловли",
    "landmark": "Достопримечательность", "paid_pond": "Платник", "parking": "Съезд, парковка",
    "spring": "Родник", "tackle_shop": "Снасти и наживка", "water_body": "Водоём",
}

# Заголовок страницы места для поиска и превью в Telegram: так люди ищут («рыбалка …»).
TITLES = {
    "water_body": "Рыбалка: {name} — отчёты, фото, запреты",
    "fishing_spot": "Рыбалка: {name} — точка ловли",
    "paid_pond": "Платная рыбалка: {name}",
    "base": "{name} — база отдыха",
    "campsite": "{name} — стоянка на природе",
    "spring": "Родник {name}",
    "landmark": "{name} — достопримечательность",
    "tackle_shop": "{name} — снасти и наживка",
    "parking": "{name} — съезд и парковка",
}

# Описание, если у места своего нет.
DESCRIPTIONS = {
    "water_body": "Водоём на карте Dalada: свежие отчёты рыбаков с уловом и фото, отзывы, запреты на лов и как доехать.",
    "fishing_spot": "Точка ловли на карте Dalada: свежие отчёты с уловом и фото, запреты на лов и как доехать.",
    "paid_pond": "Платный водоём на карте Dalada: отчёты рыбаков, фото, отзывы и как доехать.",
    "base": "База отдыха на карте Dalada: фото, отзывы, отчёты рыбаков рядом и как доехать.",
    "campsite": "Стоянка на карте Dalada: фото, отзывы, отчёты и как доехать.",
    "spring": "Родник на карте Dalada: фото, отзывы и как добраться.",
    "landmark": "Достопримечательность на карте Dalada: фото, отзывы и как добраться.",
    "tackle_shop": "Магазин снастей и наживки на карте Dalada: отзывы и как доехать.",
    "parking": "Съезд и парковка на карте Dalada: как доехать и где оставить машину.",
}

LOADING = '    <p class="muted" id="loading">…</p>'

# «Сведения» места — как в приложении (Localizable.xcstrings, place.info.*). Статическая страница —
# по-русски; на языке браузера их перерисовывает share.js.
INFO_LABELS = {
    "species": "Рыба", "methods": "Способы ловли", "access": "Подъезд", "fee": "Стоимость",
    "contact": "Контакты", "amenities": "Удобства", "signal": "Связь", "months": "Лучшие месяцы",
    "features": "Особенности",
}
INFO_VALUES = {
    "access": {"asphalt": "Асфальт", "dirt": "Грунтовка", "offroad": "Только на 4×4", "foot": "Пешком",
               "boat": "На лодке"},
    "fee": {"free": "Бесплатно", "paid": "Платно"},
    "price_unit": {"entry": "за вход", "day": "за сутки", "hour": "в час", "kg": "за кг улова"},
    "methods": {"shore": "С берега", "boat": "С лодки", "spinning": "Спиннинг", "feeder": "Фидер",
                "float": "Поплавок", "fly": "Нахлыст", "bottom": "Донка", "ice": "Со льда"},
    "amenities": {"parking": "Парковка", "toilet": "Туалет", "shade": "Тень", "tent": "Место под палатку",
                  "fireplace": "Костровище", "drinking_water": "Питьевая вода", "shop": "Магазин рядом",
                  "boat_rental": "Прокат лодок"},
    "signal": {"none": "Нет", "weak": "Слабая", "good": "Хорошая"},
}
MONTHS = ["январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь",
          "ноябрь", "декабрь"]
# У мест для рыбалки сначала рыба и способы ловли (PlaceType.isFishing в приложении).
FISHING_TYPES = {"fishing_spot", "water_body", "paid_pond"}


def app_store_url(campaign):
    """Ссылка на App Store с меткой кампании `campaign`, если задан токен поставщика."""
    if not APP_STORE_URL or not APP_STORE_PT:
        return APP_STORE_URL
    return APP_STORE_URL + "?pt=" + APP_STORE_PT + "&ct=" + campaign


def place_title(place):
    name = " ".join(str(place.get("name") or "").split())
    return TITLES.get(place.get("type"), "{name} — на карте Dalada").format(name=name)


def place_description(place):
    return short(place.get("description")) or DESCRIPTIONS.get(place.get("type"), "Место на карте Dalada.")


def month_spans(months):
    """Месяцы отрезками, как PlaceAttributes.monthSpans: [12, 1, 2] → [(12, 2)]."""
    ordered = sorted({m for m in months if isinstance(m, int) and 1 <= m <= 12})
    if not ordered:
        return []
    if len(ordered) == 12:
        return [(1, 12)]
    spans = [[ordered[0], ordered[0]]]
    for month in ordered[1:]:
        if month == spans[-1][1] + 1:
            spans[-1][1] = month
        else:
            spans.append([month, month])
    if len(spans) > 1 and spans[0][0] == 1 and spans[-1][1] == 12:
        head = spans.pop(0)
        spans[-1][1] = head[1]
    return [tuple(span) for span in spans]


def as_list(items):
    """Список в строку, как в предложении: «Сазан, карп, судак» — заглавная только первая буква."""
    items = [i for i in items if i]
    return ", ".join([items[0]] + [i[:1].lower() + i[1:] for i in items[1:]]) if items else ""


def place_info(place, species):
    """Строки «Сведений» места: [(подпись, значение)] в порядке приложения. `species` — id → (порядок, название)."""
    info = place.get("attributes") or {}
    if not isinstance(info, dict):
        return []

    def titles(key):
        values = info.get(key) or []
        return as_list(INFO_VALUES[key][v] for v in values if v in INFO_VALUES[key])

    fishing, other = [], []
    fish = [species[s] for s in (info.get("species") or []) if s in species]
    if fish:
        fishing.append(("species", as_list(name for _, name in sorted(fish))))
    if titles("methods"):
        fishing.append(("methods", titles("methods")))
    if titles("access"):
        other.append(("access", titles("access")))
    fee = INFO_VALUES["fee"].get(info.get("fee"))
    if fee:
        price = info.get("price_kzt")
        if isinstance(price, int) and price > 0:
            unit = INFO_VALUES["price_unit"].get(info.get("price_unit"))
            fee += " · " + f"{price:,}".replace(",", "\u00a0") + " ₸" + (" " + unit if unit else "")
        other.append(("fee", fee))
    if isinstance(info.get("contact"), str) and info["contact"].strip():
        other.append(("contact", info["contact"].strip()))
    if titles("amenities"):
        other.append(("amenities", titles("amenities")))
    signal = INFO_VALUES["signal"].get(info.get("signal"))
    if signal:
        other.append(("signal", signal))
    spans = month_spans(info.get("months") or [])
    if spans:
        text = ", ".join(MONTHS[a - 1] if a == b else MONTHS[a - 1] + "–" + MONTHS[b - 1] for a, b in spans)
        other.append(("months", text[:1].upper() + text[1:]))
    if isinstance(info.get("features"), str) and info["features"].strip():
        other.append(("features", " ".join(info["features"].split())))
    rows = fishing + other if place.get("type") in FISHING_TYPES else other + fishing
    return [(INFO_LABELS[key], value) for key, value in rows]


def info_html(rows):
    if not rows:
        return ""
    items = "".join(
        "\n      <dt>" + html.escape(label) + "</dt><dd>" + html.escape(value) + "</dd>" for label, value in rows
    )
    return '\n    <dl class="info">' + items + "\n    </dl>"


def fetch_species(url, key):
    """Справочник рыб: id → (порядок, название по-русски). Не загрузился — страницы без строки «Рыба»."""
    request = urllib.request.Request(
        url + "/rest/v1/fish_species?select=id,name_ru,sort_order",
        headers={"apikey": key, "Authorization": "Bearer " + key},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            rows = json.load(response)
    except Exception as error:  # noqa: BLE001 — без названий рыб страница всё равно полезна
        print("Справочник рыб не загрузился (" + type(error).__name__ + ")")
        return {}
    return {r["id"]: (r.get("sort_order") or 0, r["name_ru"]) for r in rows if r.get("id") and r.get("name_ru")}


def release(page):
    """После выхода: без блоков <!-- beta -->…<!-- /beta -->, с блоками <!-- appstore …appstore -->
    и баннером Safari. До выхода страница не меняется."""
    if not APP_STORE_ID:
        return page
    page = re.sub(r"<!-- beta -->.*?<!-- /beta -->\n?", "", page, flags=re.S)
    page = re.sub(r"<!-- appstore\n?(.*?)appstore -->\n?", r"\1", page, flags=re.S)
    # {{APP_STORE_URL}} — ссылка с меткой site, {{APP_STORE_URL:press}} — со своей меткой.
    page = re.sub(r"\{\{APP_STORE_URL(?::([a-z0-9-]{1,30}))?\}\}",
                  lambda m: html.escape(app_store_url(m.group(1) or "site"), quote=True), page)
    return page.replace("</head>", '  <meta name="apple-itunes-app" content="app-id=' + APP_STORE_ID + '">\n</head>', 1)


def render(template, title, description, image, url, large, indexed=False, content=LOADING):
    """Страница из шаблона. `indexed` — пустить поисковики (только места); `content` — то, что видно
    до скрипта (поисковикам и без JavaScript), уже экранированный HTML."""
    values = {
        "{{BASE}}": BASE,
        "{{OG_TITLE}}": html.escape(title, quote=True),
        "{{OG_DESCRIPTION}}": html.escape(description, quote=True),
        "{{OG_IMAGE}}": html.escape(image, quote=True),
        "{{OG_URL}}": html.escape(url, quote=True),
        "{{TWITTER_CARD}}": "summary_large_image" if large else "summary",
        "{{ROBOTS}}": "index, follow" if indexed else "noindex",
        # Последним: в нём текст из базы.
        "{{CONTENT}}": content,
    }
    page = template
    for key, value in values.items():
        page = page.replace(key, value)
    return page


# Сервер отдаёт не больше 1000 строк за запрос (max_rows), а мест больше: забираем страницами
# (web_places отдаёт их по id, порядок устойчивый).
PAGE = 1000


def fetch_places(url, key):
    places = []
    while True:
        request = urllib.request.Request(
            url + "/rest/v1/rpc/web_places?limit=" + str(PAGE) + "&offset=" + str(len(places)),
            data=b"{}",
            headers={"apikey": key, "Authorization": "Bearer " + key, "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            page = json.load(response)
        places += page
        if len(page) < PAGE:
            return places


def short(text, limit=200):
    text = " ".join((text or "").split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def main():
    shutil.rmtree(OUTPUT, ignore_errors=True)
    shutil.copytree(SOURCE, OUTPUT)
    os.remove(os.path.join(OUTPUT, "s", "page.template.html"))
    for folder, _, files in os.walk(OUTPUT):
        for name in files:
            if name.endswith(".html"):
                path = os.path.join(folder, name)
                with open(path, encoding="utf-8") as f:
                    page = f.read()
                with open(path, "w", encoding="utf-8") as f:
                    f.write(release(page))
    template = release(open(TEMPLATE, encoding="utf-8").read())
    if GOOGLE_SITE_VERIFICATION:
        landing = os.path.join(OUTPUT, "index.html")
        with open(landing, encoding="utf-8") as f:
            page = f.read()
        meta = '  <meta name="google-site-verification" content="' + GOOGLE_SITE_VERIFICATION + '">\n</head>'
        with open(landing, "w", encoding="utf-8") as f:
            f.write(page.replace("</head>", meta, 1))

    host = os.environ.get("SUPABASE_HOST", "").strip()
    key = os.environ.get("SUPABASE_KEY", "").strip()
    url = ("https://" + host) if host and not host.startswith("http") else host
    config = {"url": url, "key": key, "photos": PHOTOS} if url and key else {}
    browser = dict(config, appStore=APP_STORE_URL) if APP_STORE_URL else config
    if APP_STORE_URL and APP_STORE_PT:
        browser["appStorePt"] = APP_STORE_PT
    with open(os.path.join(OUTPUT, "s", "config.js"), "w", encoding="utf-8") as out:
        out.write("window.DALADA = " + json.dumps(browser) + ";\n")

    generic_image = ORIGIN + BASE + "s/og.png"
    generic = render(
        template,
        "Dalada — рыбалка и отдых на природе",
        "Место, поездка или улов в Dalada — карта рыбалки и отдыха по всему Казахстану.",
        generic_image,
        ORIGIN + BASE + "s/",
        False,
    )
    with open(os.path.join(OUTPUT, "s", "index.html"), "w", encoding="utf-8") as out:
        out.write(generic)
    with open(os.path.join(OUTPUT, "404.html"), "w", encoding="utf-8") as out:
        out.write(generic)

    if not config:
        print("Секретов Supabase нет — страницы мест, статей и запретов не собраны")
        write_sitemap([], [])
        return
    extra = content_pages(url, key)
    try:
        places = fetch_places(url, key)
    except Exception as error:  # noqa: BLE001 — сайт важнее страниц мест
        print("Места не загрузились (" + type(error).__name__ + ") — страницы мест не собраны")
        write_sitemap([], extra)
        return

    species = fetch_species(url, key)
    with_info = 0
    for place in places:
        place_id = str(place["id"])
        kind = TYPES.get(place.get("type"), "Место")
        description = place_description(place)
        # На странице — описание целиком, в мета-тегах — первые 200 знаков.
        full = " ".join(str(place.get("description") or "").split()) or description
        photo = place.get("photo_path")
        rows = place_info(place, species)
        with_info += bool(rows)
        content = "\n".join([
            "    <h1>" + html.escape(place["name"]) + "</h1>",
            '    <p class="sub">' + html.escape(kind) + "</p>",
            '    <p class="desc">' + html.escape(full) + "</p>",
        ]) + info_html(rows)
        page = render(
            template,
            place_title(place),
            description,
            PHOTOS + "/" + photo if photo else generic_image,
            ORIGIN + BASE + "p/" + place_id + "/",
            bool(photo),
            indexed=True,
            content=content,
        )
        folder = os.path.join(OUTPUT, "p", place_id)
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "index.html"), "w", encoding="utf-8") as out:
            out.write(page)
    print("Страниц мест: " + str(len(places)) + ", со сведениями: " + str(with_info))
    write_sitemap(places, extra)


def content_pages(url, key):
    """Статьи и запреты на лов (site_content.py). Каждая часть — отдельно: сбой одной не мешает другой.
    Возвращает адреса для sitemap."""
    sitemap = []
    app_id = APP_STORE_ID or ""
    parts = [
        ("статьи", lambda: site_content.article_pages(
            site_content.fetch_articles(url, key), ORIGIN, BASE, app_store_url, app_id)),
        ("запреты", lambda: site_content.rules_pages(
            *site_content.fetch_rules(url, key), ORIGIN, BASE, app_store_url, app_id, site_content.almaty_today())),
    ]
    for name, build in parts:
        try:
            files, entries = build()
        except Exception as error:  # noqa: BLE001 — сайт важнее этих страниц
            print("Страницы «" + name + "» не собраны (" + type(error).__name__ + ")")
            continue
        for path, text in files.items():
            target = os.path.join(OUTPUT, path)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "w", encoding="utf-8") as out:
                out.write(text)
        sitemap += entries
        print("Страниц «" + name + "»: " + str(len(files)))
    return sitemap


def write_sitemap(places, extra):
    """sitemap.xml: главная, пресс-страница, статьи, запреты и страницы мест (дата — последнее изменение).
    Поисковикам его отдаём сами (Search Console): robots.txt на GitHub Pages проекта не положить — он в
    корне домена."""
    entries = [(ORIGIN + BASE, None), (ORIGIN + BASE + "press.html", None)]
    entries += [(loc, lastmod if lastmod and re.fullmatch(r"\d{4}-\d{2}-\d{2}", lastmod) else None) for loc, lastmod in extra]
    for place in places:
        updated = str(place.get("updated_at") or "")[:10]
        entries.append((ORIGIN + BASE + "p/" + str(place["id"]) + "/", updated if re.fullmatch(r"\d{4}-\d{2}-\d{2}", updated) else None))
    lines = ['<?xml version="1.0" encoding="UTF-8"?>', '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    for loc, lastmod in entries:
        lines.append("  <url><loc>" + html.escape(loc) + "</loc>" + ("<lastmod>" + lastmod + "</lastmod>" if lastmod else "") + "</url>")
    lines.append("</urlset>")
    with open(os.path.join(OUTPUT, "sitemap.xml"), "w", encoding="utf-8") as out:
        out.write("\n".join(lines) + "\n")
    print("sitemap.xml: " + str(len(entries)) + " адресов")


if __name__ == "__main__":
    sys.exit(main())
