#!/usr/bin/env python3
"""Страница App Store из файлов appstore/listing/ — через App Store Connect API.

    python3 appstore/listing.py --check              # только проверить длины и состав файлов
    python3 appstore/listing.py [--version 1.0]      # отправить в App Store Connect

Файлы:
  <локаль>/name.txt (30), subtitle.txt (30) — информация о приложении;
  <локаль>/keywords.txt (100), promotional_text.txt (170), description.txt (4000) — версия;
  support_url.txt, marketing_url.txt, privacy_policy_url.txt — общие для всех локалей.
Локали: ru (основной язык приложения) и en-US. Категории: «Спорт» и «Путешествия».

Версию (по умолчанию 1.0) берёт ту, что готовится к отправке, или создаёт. Сборку к версии не
привязывает и на проверку не отправляет — это отдельный шаг (docs/05-release/README.md, R3).
Нужны ASC_KEY_ID, ASC_ISSUER_ID и ASC_KEY_PATH — как у appstore/testflight_info.py.
"""

import argparse
import sys
from pathlib import Path

LISTING = Path(__file__).resolve().parent / "listing"
LOCALES = ["ru", "en-US"]
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotional_text": 170, "description": 4000}
SHARED = ["support_url", "marketing_url", "privacy_policy_url"]
CATEGORIES = {"primaryCategory": "SPORTS", "secondaryCategory": "TRAVEL"}
# Версия, в которую ещё можно писать тексты.
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}


def read(name: str, locale: str | None = None) -> str:
    path = LISTING / locale / f"{name}.txt" if locale else LISTING / f"{name}.txt"
    return path.read_text(encoding="utf-8").strip()


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

    # Версия: та, что готовится к отправке, или новая.
    versions = call("GET", f"/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20")["data"]
    version = next((v for v in versions if v["attributes"].get("appStoreState") in EDITABLE), None)
    if version is None:
        version = call("POST", "/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": version_string},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print(f"Создана версия {version_string}")
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
        if locale not in current:
            attributes["locale"] = locale
        upsert("appStoreVersionLocalizations", current.get(locale), attributes,
               ("appStoreVersion", "appStoreVersions", version["id"]))
        print(f"Тексты версии ({locale}): описание, ключевые слова, промотекст, ссылки — готово")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="только проверить файлы")
    parser.add_argument("--version", default="1.0", help="версия, если её ещё нет (по умолчанию 1.0)")
    args = parser.parse_args()
    problems = check()
    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        sys.exit(1)
    print("Файлы страницы App Store в порядке")
    if not args.check:
        upload(args.version)


if __name__ == "__main__":
    main()
