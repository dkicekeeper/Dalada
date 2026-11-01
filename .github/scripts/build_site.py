#!/usr/bin/env python3
"""Сборка сайта для GitHub Pages: docs/public и страницы «Поделиться» (docs/04-beta/M29-web-share.md).

- _site/s/index.html и _site/404.html — страница места, поездки, улова (данные грузит браузер);
- _site/p/<id>/index.html — статическая страница каждого публичного места с превью для Telegram
  (название, тип, описание, фото редакции);
- _site/s/config.js — адрес Supabase и публичный ключ гостя из секретов (в репозитории их нет);
- после выхода в App Store (APP_STORE_ID) — кнопка App Store вместо приглашения в бету и баннер
  Safari (Smart App Banner) на всех страницах.

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

TYPES = {
    "base": "База отдыха", "campsite": "Стоянка", "fishing_spot": "Точка ловли",
    "landmark": "Достопримечательность", "paid_pond": "Платник", "parking": "Съезд, парковка",
    "spring": "Родник", "tackle_shop": "Снасти и наживка", "water_body": "Водоём",
}


def release(page):
    """После выхода: без блоков <!-- beta -->…<!-- /beta -->, с блоками <!-- appstore …appstore -->
    и баннером Safari. До выхода страница не меняется."""
    if not APP_STORE_ID:
        return page
    page = re.sub(r"<!-- beta -->.*?<!-- /beta -->\n?", "", page, flags=re.S)
    page = re.sub(r"<!-- appstore\n?(.*?)appstore -->\n?", r"\1", page, flags=re.S)
    page = page.replace("{{APP_STORE_URL}}", APP_STORE_URL)
    return page.replace("</head>", '  <meta name="apple-itunes-app" content="app-id=' + APP_STORE_ID + '">\n</head>', 1)


def render(template, title, description, image, url, large):
    values = {
        "{{BASE}}": BASE,
        "{{OG_TITLE}}": html.escape(title, quote=True),
        "{{OG_DESCRIPTION}}": html.escape(description, quote=True),
        "{{OG_IMAGE}}": html.escape(image, quote=True),
        "{{OG_URL}}": html.escape(url, quote=True),
        "{{TWITTER_CARD}}": "summary_large_image" if large else "summary",
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

    host = os.environ.get("SUPABASE_HOST", "").strip()
    key = os.environ.get("SUPABASE_KEY", "").strip()
    url = ("https://" + host) if host and not host.startswith("http") else host
    config = {"url": url, "key": key, "photos": PHOTOS} if url and key else {}
    browser = dict(config, appStore=APP_STORE_URL) if APP_STORE_URL else config
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
        return
    try:
        places = fetch_places(url, key)
    except Exception as error:  # noqa: BLE001 — сайт важнее страниц мест
        print("Места не загрузились (" + type(error).__name__ + ") — страницы мест не собраны")
        return

    for place in places:
        place_id = str(place["id"])
        kind = TYPES.get(place.get("type"), "Место")
        description = short(place.get("description")) or kind + " на карте Dalada"
        photo = place.get("photo_path")
        page = render(
            template,
            place["name"] + " — " + kind,
            description,
            PHOTOS + "/" + photo if photo else generic_image,
            ORIGIN + BASE + "p/" + place_id + "/",
            bool(photo),
        )
        folder = os.path.join(OUTPUT, "p", place_id)
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "index.html"), "w", encoding="utf-8") as out:
            out.write(page)
    print("Страниц мест: " + str(len(places)))


if __name__ == "__main__":
    sys.exit(main())
