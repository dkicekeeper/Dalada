#!/usr/bin/env python3
"""Сборка сайта для GitHub Pages: docs/public и страницы «Поделиться» (docs/04-beta/M29-web-share.md).

- _site/s/index.html и _site/404.html — страница места, поездки, улова (данные грузит браузер);
- _site/p/<id>/index.html — статическая страница каждого публичного места с превью для Telegram
  (название, тип, описание, фото редакции);
- _site/s/config.js — адрес Supabase и публичный ключ гостя из секретов (в репозитории их нет);
- после выхода в App Store (APP_STORE_ID) — кнопка App Store вместо приглашения в бету и баннер
  Safari (Smart App Banner) на всех страницах;
- _site/sitemap.xml — главная, пресс-страница и страницы мест для поисковиков (страницы поездок, уловов и
  приглашений закрыты от индексации: это записи людей);
- метки кампаний App Store Connect в ссылках на App Store (переменная репозитория APP_STORE_PT) и
  метатег Google Search Console (GOOGLE_SITE_VERIFICATION) — docs/05-release/promotion.md.

Без секретов или без сети сайт всё равно собирается — только без страниц мест.
Ключ и адрес в журнал не печатаем: репозиторий публичный.
"""
import html
import json
import os
import re
import shutil
import sys
import urllib.request

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
APP_STORE_PT = os.environ.get("APP_STORE_PT", "").strip()
# Подтверждение сайта в Google Search Console метатегом на главной (код из Search Console).
GOOGLE_SITE_VERIFICATION = os.environ.get("GOOGLE_SITE_VERIFICATION", "").strip()
# Значения из переменных попадают в HTML — пропускаем только ожидаемый вид.
if APP_STORE_PT and not re.fullmatch(r"[0-9]{1,20}", APP_STORE_PT):
    print("APP_STORE_PT не похож на токен поставщика (только цифры) — ссылки без меток")
    APP_STORE_PT = ""
if GOOGLE_SITE_VERIFICATION and not re.fullmatch(r"[A-Za-z0-9_-]{10,100}", GOOGLE_SITE_VERIFICATION):
    print("GOOGLE_SITE_VERIFICATION не похож на код Search Console — метатег не добавлен")
    GOOGLE_SITE_VERIFICATION = ""

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
        print("Секретов Supabase нет — страницы мест не собраны")
        write_sitemap([])
        return
    try:
        places = fetch_places(url, key)
    except Exception as error:  # noqa: BLE001 — сайт важнее страниц мест
        print("Места не загрузились (" + type(error).__name__ + ") — страницы мест не собраны")
        write_sitemap([])
        return

    for place in places:
        place_id = str(place["id"])
        kind = TYPES.get(place.get("type"), "Место")
        description = place_description(place)
        photo = place.get("photo_path")
        content = "\n".join([
            "    <h1>" + html.escape(place["name"]) + "</h1>",
            '    <p class="sub">' + html.escape(kind) + "</p>",
            '    <p class="desc">' + html.escape(description) + "</p>",
        ])
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
    print("Страниц мест: " + str(len(places)))
    write_sitemap(places)


def write_sitemap(places):
    """sitemap.xml: главная, пресс-страница и страницы мест (дата — последнее изменение места). Поисковикам его
    отдаём сами (Search Console): robots.txt на GitHub Pages проекта не положить — он в корне домена."""
    entries = [(ORIGIN + BASE, None), (ORIGIN + BASE + "press.html", None)]
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
