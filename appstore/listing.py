#!/usr/bin/env python3
"""Страница App Store из файлов appstore/listing/ — через App Store Connect API.

    python3 appstore/listing.py --check              # только проверить длины и состав файлов
    python3 appstore/listing.py [--version 1.0]      # отправить в App Store Connect

Файлы:
  <локаль>/name.txt (30), subtitle.txt (30) — информация о приложении;
  <локаль>/keywords.txt (100), promotional_text.txt (170), description.txt (4000) — версия;
  <локаль>/whats_new/<версия>.txt (4000) — «Что нового» у обновления: у первой версии этого поля
  нет, у остальных App Store без него на проверку не примет;
  support_url.txt, marketing_url.txt, privacy_policy_url.txt — общие для всех локалей.
Локали: ru (основной язык приложения) и en-US. Категории: «Спорт» и «Путешествия».

Версию берёт ту, что готовится к отправке, или создаёт (номер — MARKETING_VERSION из
ios/project.yml). Сборку к версии не привязывает и на проверку не отправляет — это
appstore/release.py (docs/05-release/README.md, R3).

Рекламный текст (promotional_text.txt) Apple разрешает менять и у версии, которая уже в App Store,
без проверки — его отправляем и туда: так текст под сезон виден сразу, не дожидаясь обновления
(docs/05-release/promotion.md, «Страница и ключевые слова»).
Нужны ASC_KEY_ID, ASC_ISSUER_ID и ASC_KEY_PATH — как у appstore/testflight_info.py.
"""

import argparse
import re
import sys
from pathlib import Path

LISTING = Path(__file__).resolve().parent / "listing"
LOCALES = ["ru", "en-US"]
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotional_text": 170, "description": 4000}
WHATS_NEW_LIMIT = 4000
SHARED = ["support_url", "marketing_url", "privacy_policy_url"]
CATEGORIES = {"primaryCategory": "SPORTS", "secondaryCategory": "TRAVEL"}


def read(name: str, locale: str | None = None) -> str:
    path = LISTING / locale / f"{name}.txt" if locale else LISTING / f"{name}.txt"
    return path.read_text(encoding="utf-8").strip()


def whats_new(locale: str, version: str) -> str | None:
    path = LISTING / locale / "whats_new" / f"{version}.txt"
    return path.read_text(encoding="utf-8").strip() if path.exists() else None


def check() -> list[str]:
    problems = []
    for locale in LOCALES:
        for name, limit in LIMITS.items():
            try:
                value = read(name, locale)
            except FileNotFoundError:
                problems.append(f"{locale}/{name}.txt: нет файла")
                continue
            if not value:
                problems.append(f"{locale}/{name}.txt: пусто")
            if len(value) > limit:
                problems.append(f"{locale}/{name}.txt: {len(value)} символов, можно {limit}")
        keywords = [k.strip() for k in read("keywords", locale).split(",")]
        if any(not k for k in keywords):
            problems.append(f"{locale}/keywords.txt: пустое слово между запятыми")
        if len({k.lower() for k in keywords}) != len(keywords):
            problems.append(f"{locale}/keywords.txt: слова повторяются")
    # «Что нового»: файл на каждую версию, у каждой версии — на всех языках.
    found = {locale: {p.stem for p in (LISTING / locale / "whats_new").glob("*.txt")} for locale in LOCALES}
    for version in sorted(set().union(*found.values())):
        if not re.fullmatch(r"\d+\.\d+\.\d+", version):
            problems.append(f"whats_new/{version}.txt: имя файла — номер версии, например 1.0.1.txt")
        for locale in LOCALES:
            value = whats_new(locale, version)
            if value is None:
                problems.append(f"{locale}/whats_new/{version}.txt: нет файла (для другого языка есть)")
            elif not value:
                problems.append(f"{locale}/whats_new/{version}.txt: пусто")
            elif len(value) > WHATS_NEW_LIMIT:
                problems.append(f"{locale}/whats_new/{version}.txt: {len(value)} символов, можно {WHATS_NEW_LIMIT}")
    for name in SHARED:
        try:
            if not read(name).startswith("https://"):
                problems.append(f"{name}.txt: нужна ссылка https://")
        except FileNotFoundError:
            problems.append(f"{name}.txt: нет файла")
    return problems


def upload(version_string: str) -> None:
    # API нужен только здесь: для --check не требуются ни ключ, ни pyjwt.
    from testflight_info import BUNDLE_ID, call, upsert

    apps = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not apps:
        sys.exit(f"Приложение {BUNDLE_ID} не найдено в App Store Connect")
    app_id = apps[0]["id"]
    promote_live(app_id)
    # Версия: та, что готовится к отправке, или новая. Пока версия на проверке, тексты не меняются.
    from release import editable_version, is_update
    version = editable_version(app_id, version_string)
    update = is_update(app_id, version_string)

    # Информация о приложении: название, подзаголовок, политика, категории.
    infos = call("GET", f"/apps/{app_id}/appInfos")["data"]
    info = next((i for i in infos if i["attributes"].get("state") != "READY_FOR_DISTRIBUTION"), infos[0])
    current = {i["attributes"]["locale"]: i for i in call("GET", f"/appInfos/{info['id']}/appInfoLocalizations")["data"]}
    for locale in LOCALES:
        attributes = {"name": read("name", locale), "subtitle": read("subtitle", locale),
                      "privacyPolicyUrl": read("privacy_policy_url")}
        if locale not in current:
            attributes["locale"] = locale
        upsert("appInfoLocalizations", current.get(locale), attributes, ("appInfo", "appInfos", info["id"]))
        print(f"Информация о приложении ({locale}): название, подзаголовок, политика — готово")
    call("PATCH", f"/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
        name: {"data": {"type": "appCategories", "id": category}} for name, category in CATEGORIES.items()}}})
    print("Категории: Спорт, Путешествия — готово")

    print(f"Версия {version['attributes']['versionString']} ({version['attributes'].get('appStoreState')})")

    current = {v["attributes"]["locale"]: v for v in
               call("GET", f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]}
    for locale in LOCALES:
        attributes = {
            "description": read("description", locale),
            "keywords": read("keywords", locale),
            "promotionalText": read("promotional_text", locale),
            "supportUrl": read("support_url"),
            "marketingUrl": read("marketing_url"),
        }
        # «Что нового» есть только у обновлений; нет файла — release.py напомнит.
        notes = whats_new(locale, version_string) if update else None
        if notes:
            attributes["whatsNew"] = notes
        if locale not in current:
            attributes["locale"] = locale
        upsert("appStoreVersionLocalizations", current.get(locale), attributes,
               ("appStoreVersion", "appStoreVersions", version["id"]))
        print(f"Тексты версии ({locale}): описание, ключевые слова, промотекст, ссылки"
              + (", что нового" if notes else "") + " — готово")


def promote_live(app_id: str) -> None:
    """Рекламный текст версии, которая сейчас в App Store: меняется без проверки."""
    from testflight_info import call
    from release import LIVE

    versions = call("GET", f"/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20")["data"]
    live = next((v for v in versions if v["attributes"].get("appStoreState") in LIVE), None)
    if live is None:
        return
    name = live["attributes"]["versionString"]
    for item in call("GET", f"/appStoreVersions/{live['id']}/appStoreVersionLocalizations")["data"]:
        locale = item["attributes"]["locale"]
        if locale not in LOCALES:
            continue
        text = read("promotional_text", locale)
        if item["attributes"].get("promotionalText") == text:
            print(f"Рекламный текст {name} в App Store ({locale}) — без изменений")
            continue
        call("PATCH", f"/appStoreVersionLocalizations/{item['id']}", {"data": {
            "type": "appStoreVersionLocalizations", "id": item["id"], "attributes": {"promotionalText": text}}})
        print(f"Рекламный текст {name} в App Store ({locale}) — обновлён")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="только проверить файлы")
    parser.add_argument("--version", help="версия, если её ещё нет (по умолчанию — MARKETING_VERSION)")
    args = parser.parse_args()
    problems = check()
    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        sys.exit(1)
    print("Файлы страницы App Store в порядке")
    if not args.check:
        from release import marketing_version
        upload(args.version or marketing_version())


if __name__ == "__main__":
    main()
