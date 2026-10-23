#!/usr/bin/env python3
"""Версия для App Store: всё, что App Store Connect API позволяет заполнить до отправки на проверку.

    python3 appstore/release.py [--build 146]

Выставляет:
  - версию из MARKETING_VERSION (ios/project.yml), ручной выпуск после одобрения и авторские права
    (listing/copyright.txt);
  - права на контент: есть чужой контент и права на него (OpenStreetMap, фото Wikimedia Commons);
  - возрастной рейтинг — ответы из listing/age_rating.json (только вопросы, которые знает API);
  - цену: бесплатно (если цена ещё не задана);
  - доступность: только Казахстан, в новых странах — нет;
  - данные для проверки Apple: заметки (testflight/review_notes.txt), почту для связи, демо-аккаунт
    из секретов ASC_DEMO_USER / ASC_DEMO_PASSWORD (в лог не выводится);
  - сборку с --build (её версия должна совпадать с версией в App Store Connect).
На проверку не отправляет — это решение владельца (docs/05-release/README.md, R3). В конце
печатает, что осталось сделать руками: имя и телефон для связи, скриншоты, сборка; анкету
приватности (в API её нет) — напоминает.

Нужны ASC_KEY_ID, ASC_ISSUER_ID и ASC_KEY_PATH — как у appstore/testflight_info.py. Контактные
данные и пароль демо-аккаунта в лог не выводятся: логи Actions открытого репозитория видны всем.
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

from testflight_info import BUNDLE_ID, FEEDBACK_EMAIL, ApiError, builds, call, text

ROOT = Path(__file__).resolve().parent
LISTING = ROOT / "listing"
PROJECT = ROOT.parent / "ios" / "project.yml"
LOCALES = ["ru", "en-US"]
# Витрина — только Казахстан (docs/05-release/README.md, решение 2).
TERRITORY = "KAZ"
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}

todo: list[str] = []


def marketing_version() -> str:
    match = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', PROJECT.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"Нет MARKETING_VERSION в {PROJECT}")
    return match.group(1)


# Версия ушла дальше подготовки, но ещё не в App Store: проверка, ожидание выпуска.
FINISHED = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_VERSION", "REMOVED_FROM_SALE",
            "DEVELOPER_REMOVED_FROM_SALE"}


def editable_version(app_id: str, version_string: str) -> dict:
    """Версия, которая готовится к отправке (с нужным номером), или новая.

    Пока версия на проверке или ждёт выпуска, менять в App Store Connect нечего (и новую версию не
    создать), как и когда версия с этим номером уже в App Store: печатаем состояние и выходим без
    ошибки. Для обновления после выхода — поднять MARKETING_VERSION.
    """
    versions = call("GET", f"/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20")["data"]
    version = next((v for v in versions if v["attributes"].get("appStoreState") in EDITABLE), None)
    if version is None:
        in_flight = next((v for v in versions if v["attributes"].get("appStoreState") not in FINISHED), None)
        same = next((v for v in versions if v["attributes"]["versionString"] == version_string), None)
        if in_flight or same:
            blocker = in_flight or same
            print(f"Версия {blocker['attributes']['versionString']}: {blocker['attributes'].get('appStoreState')} — "
                  + ("на проверке или ждёт выпуска, менять нечего" if in_flight
                     else "уже в App Store; для обновления поднимите MARKETING_VERSION"))
            sys.exit(0)
        version = call("POST", "/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": version_string},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print(f"Создана версия {version_string}")
    return version


def update_version(version: dict, version_string: str) -> None:
    attributes = {"releaseType": "MANUAL", "copyright": (LISTING / "copyright.txt").read_text(encoding="utf-8").strip()}
    if version["attributes"]["versionString"] != version_string:
        attributes["versionString"] = version_string
    call("PATCH", f"/appStoreVersions/{version['id']}",
         {"data": {"type": "appStoreVersions", "id": version["id"], "attributes": attributes}})
    print(f"Версия {version_string}: ручной выпуск, авторские права — готово")


def update_content_rights(app_id: str) -> None:
    call("PATCH", f"/apps/{app_id}", {"data": {"type": "apps", "id": app_id,
                                                "attributes": {"contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT"}}})
    print("Права на контент: чужой контент с правами на него (OpenStreetMap, Wikimedia Commons) — готово")


def update_age_rating(app_id: str) -> None:
    answers = json.loads((LISTING / "age_rating.json").read_text(encoding="utf-8"))
    infos = call("GET", f"/apps/{app_id}/appInfos")["data"]
    info = next((i for i in infos if i["attributes"].get("state") != "READY_FOR_DISTRIBUTION"), infos[0])
    declaration = call("GET", f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    known = declaration["attributes"]
    # Вопросы анкеты Apple меняет; отправляем только те, что API знает сейчас.
    attributes = {key: value for key, value in answers.items() if key in known}
    call("PATCH", f"/ageRatingDeclarations/{declaration['id']}",
         {"data": {"type": "ageRatingDeclarations", "id": declaration["id"], "attributes": attributes}})
    print(f"Возрастной рейтинг: {len(attributes)} ответов — готово")
    unknown = sorted(set(answers) - set(known))
    if unknown:
        print(f"::warning::Этих вопросов в анкете больше нет: {', '.join(unknown)} (listing/age_rating.json)")
    unanswered = sorted(key for key, value in known.items()
                        if value is None and key not in answers and not key.endswith(("Override", "OverrideV2", "Url"))
                        and key not in ("kidsAgeBand", "gracRatingClassificationNumber"))
    if unanswered:
        todo.append(f"возрастной рейтинг: новые вопросы без ответа — {', '.join(unanswered)} (listing/age_rating.json)")


def update_price(app_id: str) -> None:
    try:
        schedule = call("GET", f"/apps/{app_id}/appPriceSchedule")["data"]
    except ApiError as error:
        if error.code != 404:
            raise
        schedule = None
    # Расписание цен у приложения бывает и пустым: App Store Connect заводит его сам, а цену не ставит
    # («Необходимо указать ценовой ярус»). Задана ли цена — смотрим по ручным ценам расписания.
    if schedule:
        prices = call("GET", f"/appPriceSchedules/{schedule['id']}/manualPrices?include=appPricePoint&limit=50")
        points = [i for i in prices.get("included", []) if i["type"] == "appPricePoints"]
        if prices["data"]:
            price = points[0]["attributes"].get("customerPrice") if points else "?"
            print(f"Цена уже задана ({price}) — не трогаю")
            return
    points = call("GET", f"/apps/{app_id}/appPricePoints?filter[territory]={TERRITORY}&limit=200")["data"]
    free = next((p for p in points if float(p["attributes"]["customerPrice"]) == 0), None)
    if free is None:
        sys.exit("::error::Не нашлась бесплатная цена в App Store Connect")
    call("POST", "/appPriceSchedules", {
        "data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": app_id}},
            "baseTerritory": {"data": {"type": "territories", "id": TERRITORY}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]}}},
        "included": [{"type": "appPrices", "id": "${free}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}}}]})
    print("Цена: бесплатно — готово")


def update_availability(app_id: str) -> None:
    try:
        availability = call("GET", f"/apps/{app_id}/appAvailabilityV2")["data"]
    except ApiError as error:
        if error.code != 404:
            raise
        availability = None
    if availability is None:
        territories = call("GET", "/territories?limit=200")["data"]
        call("POST", "/v2/appAvailabilities", {
            "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": False},
                     "relationships": {
                         "app": {"data": {"type": "apps", "id": app_id}},
                         "territoryAvailabilities": {"data": [
                             {"type": "territoryAvailabilities", "id": "${" + t["id"] + "}"} for t in territories]}}},
            "included": [{"type": "territoryAvailabilities", "id": "${" + t["id"] + "}",
                          "attributes": {"available": t["id"] == TERRITORY},
                          "relationships": {"territory": {"data": {"type": "territories", "id": t["id"]}}}}
                         for t in territories]})
        print("Доступность: только Казахстан — готово")
        return
    if availability["attributes"].get("availableInNewTerritories"):
        todo.append("доступность: выключить «новые страны и регионы» (App Store Connect → Цены и доступность)")
    changed = 0
    path = f"/v2/appAvailabilities/{availability['id']}/territoryAvailabilities?limit=200&include=territory"
    while path:
        page = call("GET", path)
        for item in page["data"]:
            territory = item["relationships"]["territory"]["data"]["id"]
            wanted = territory == TERRITORY
            if item["attributes"].get("available") != wanted:
                call("PATCH", f"/territoryAvailabilities/{item['id']}",
                     {"data": {"type": "territoryAvailabilities", "id": item["id"], "attributes": {"available": wanted}}})
                changed += 1
        next_link = page.get("links", {}).get("next")
        path = next_link.split("api.appstoreconnect.apple.com", 1)[1] if next_link else None
    print(f"Доступность: только Казахстан (изменено стран: {changed}) — готово")


CONTACT = ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")


def update_review_detail(app_id: str, version: dict) -> None:
    try:
        detail = call("GET", f"/appStoreVersions/{version['id']}/appStoreReviewDetail")["data"]
    except ApiError as error:
        if error.code != 404:
            raise
        detail = None
    attributes = {"notes": text("review_notes.txt")}
    if not detail:
        # Без имени и телефона Apple данные для проверки не создаёт: берём контакт бета-проверки,
        # который владелец уже заполнил в TestFlight (в лог не выводится).
        beta = call("GET", f"/apps/{app_id}/betaAppReviewDetail")["data"]["attributes"]
        attributes.update({key: beta[key] for key in CONTACT if beta.get(key)})
        if not all(attributes.get(key) for key in CONTACT[:3]):
            todo.append("контакт для проверки: имя, фамилия, телефон (App Store Connect → версия → "
                        "App Review Information), затем снова App Store release — допишет заметки")
            return
    demo_user = os.environ.get("DEMO_USER", "").strip()
    demo_password = os.environ.get("DEMO_PASSWORD", "")
    if demo_user and demo_password:
        attributes.update({"demoAccountRequired": True, "demoAccountName": demo_user,
                           "demoAccountPassword": demo_password})
    current = detail["attributes"] if detail else {}
    if not current.get("contactEmail") and not attributes.get("contactEmail"):
        attributes["contactEmail"] = FEEDBACK_EMAIL
    try:
        if detail:
            call("PATCH", f"/appStoreReviewDetails/{detail['id']}",
                 {"data": {"type": "appStoreReviewDetails", "id": detail["id"], "attributes": attributes}})
        else:
            call("POST", "/appStoreReviewDetails", {"data": {
                "type": "appStoreReviewDetails", "attributes": attributes,
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})
    except ApiError as error:
        # Чаще всего — телефон не в формате «+7 …»; текст ошибки Apple контактов не содержит.
        todo.append(f"данные для проверки не сохранились ({error.code}): проверить имя и телефон «+7 …» "
                    "в App Store Connect → версия → App Review Information")
        print(f"::warning::Данные для проверки: {error}")
        return
    print("Данные для проверки: заметки" + (", демо-аккаунт" if demo_user and demo_password else "") + " — готово")
    merged = {**current, **attributes}
    if not (merged.get("demoAccountRequired") and merged.get("demoAccountName")):
        todo.append("демо-аккаунт для проверки: секреты ASC_DEMO_USER и ASC_DEMO_PASSWORD (Guideline 2.1)")
    missing = [label for key, label in (("contactFirstName", "имя"), ("contactLastName", "фамилия"),
                                        ("contactPhone", "телефон")) if not merged.get(key)]
    if missing:
        todo.append(f"контакт для проверки: {', '.join(missing)} (App Store Connect → версия → App Review Information)")


def attach_build(app_id: str, version: dict, version_string: str, number: str) -> None:
    build = next((b for b in builds(app_id, limit=30) if b["number"] == number), None)
    if build is None:
        sys.exit(f"::error::Сборки {number} нет в App Store Connect")
    if build["version"] != version_string:
        sys.exit(f"::error::Сборка {number} — версии {build['version']}, а в App Store Connect — {version_string}")
    if build["processing"] != "VALID":
        sys.exit(f"::error::Сборка {number} ещё не обработана ({build['processing']})")
    call("PATCH", f"/appStoreVersions/{version['id']}/relationships/build",
         {"data": {"type": "builds", "id": build["id"]}})
    print(f"Сборка {number} привязана к версии {version_string} — готово")


def check_screenshots(version: dict) -> None:
    for localization in call("GET", f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]:
        locale = localization["attributes"]["locale"]
        sets = call("GET", f"/appStoreVersionLocalizations/{localization['id']}/appScreenshotSets"
                           "?include=appScreenshots&limit=50")
        count = len([i for i in sets.get("included", []) if i["type"] == "appScreenshots"])
        if count == 0:
            todo.append(f"скриншоты ({locale}): не загружены")
        else:
            print(f"Скриншоты ({locale}): {count}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--build", help="номер сборки, которую привязать к версии")
    args = parser.parse_args()

    apps = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not apps:
        sys.exit(f"Приложение {BUNDLE_ID} не найдено в App Store Connect")
    app_id = apps[0]["id"]
    version_string = marketing_version()
    version = editable_version(app_id, version_string)
    # Номер нужен сайту в день выхода (APP_STORE_ID в .github/scripts/build_site.py).
    print(f"Apple ID приложения: {app_id}")

    update_version(version, version_string)
    update_content_rights(app_id)
    update_age_rating(app_id)
    update_price(app_id)
    update_availability(app_id)
    update_review_detail(app_id, version)
    if args.build:
        attach_build(app_id, version, version_string, args.build)
    else:
        try:
            attached = call("GET", f"/appStoreVersions/{version['id']}/build")["data"]
        except ApiError as error:
            if error.code != 404:
                raise
            attached = None
        if attached:
            print(f"Сборка {attached['attributes']['version']} привязана раньше")
        else:
            todo.append("сборка: привязать (workflow App Store release с номером сборки)")
    check_screenshots(version)
    # Анкеты приватности в API нет: опубликована ли она, отсюда не видно.
    print("Анкета приватности (App Privacy): в API её нет — опубликована ли, смотреть в App Store Connect "
          "(ответы — docs/05-release/README.md, «Анкеты»)")

    lines = ["Осталось до отправки на проверку:"] + [f"- {item}" for item in todo]
    print("\n".join(lines))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("### App Store: версия " + version_string + "\n\n" + "\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
