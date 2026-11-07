#!/usr/bin/env python3
"""События App Store (In-App Events) и номинации на рекомендацию — из appstore/events/<событие>/.

    python3 appstore/featuring.py --check                    # проверить все события (CI, без ключа)
    python3 appstore/featuring.py event first_ice            # создать или обновить черновик события
    python3 appstore/featuring.py event first_ice --submit   # …и отправить его на проверку Apple
    python3 appstore/featuring.py event first_ice --submit --with-version   # вместе с версией 1.0.x
    python3 appstore/featuring.py nominate first_ice         # номинация на рекомендацию — черновик
    python3 appstore/featuring.py nominate first_ice --submit

Файлы события: event.json (сроки, тексты RU и EN, номинация) и картинки card.jpg (1920 × 1080) и
details.jpg (1080 × 1920) — рисует appstore/events/render.mjs по appstore/events/art/<событие>.html.
Тексты и порядок — docs/05-release/promotion-texts.md, план — docs/05-release/promotion.md.

Повторный запуск не плодит копий: событие ищется по referenceName, номинация — по name. Пока событие
на проверке или уже одобрено, его тексты не трогаем. Номинация прикрепляет событие, когда Apple его
одобрила (раньше App Store Connect не даёт). Ключ — ASC_KEY_ID, ASC_ISSUER_ID и ASC_KEY_PATH, как у
appstore/testflight_info.py.
"""

import argparse
import datetime
import json
import struct
import sys
import time
import urllib.request
from pathlib import Path

EVENTS = Path(__file__).resolve().parent / "events"
LIMITS = {"name": 30, "shortDescription": 50, "longDescription": 120}
SIZES = {"EVENT_CARD": (1920, 1080), "EVENT_DETAILS_PAGE": (1080, 1920)}
EDITABLE = {"DRAFT", "REJECTED"}
APPROVED = {"ACCEPTED", "APPROVED", "PUBLISHED"}


# --- Файлы ---------------------------------------------------------------------------------------

def load(name: str) -> dict:
    return json.loads((EVENTS / name / "event.json").read_text(encoding="utf-8"))


def moment(value: str) -> datetime.datetime:
    return datetime.datetime.fromisoformat(value)


def utc(value: str) -> str:
    return moment(value).astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def image_size(path: Path) -> tuple[int, int]:
    """Ширина и высота JPEG или PNG без сторонних библиотек."""
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    i = 2
    while i < len(data):
        marker, length = data[i + 1], struct.unpack(">H", data[i + 2:i + 4])[0]
        if marker in (0xC0, 0xC1, 0xC2):
            height, width = struct.unpack(">HH", data[i + 5:i + 9])
            return width, height
        i += 2 + length
    raise ValueError(f"{path.name}: не JPEG и не PNG")


def check_event(name: str) -> list[str]:
    problems = []
    try:
        event = load(name)
    except (OSError, ValueError) as error:
        return [f"{name}/event.json: {error}"]
    if len(event.get("referenceName", "")) not in range(1, 65):
        problems.append(f"{name}: referenceName — от 1 до 64 символов")
    for locale, texts in event.get("localizations", {}).items():
        for field, limit in LIMITS.items():
            value = texts.get(field, "")
            if not value or len(value) > limit:
                problems.append(f"{name} ({locale}): {field} — {len(value)} символов, нужно 1–{limit}")
    if event.get("primaryLocale") not in event.get("localizations", {}):
        problems.append(f"{name}: нет текстов на основном языке {event.get('primaryLocale')}")
    try:
        publish, start, end = (moment(event[k]) for k in ("publishStart", "eventStart", "eventEnd"))
        if not publish <= start < end:
            problems.append(f"{name}: нужно publishStart ≤ eventStart < eventEnd")
        if start - publish > datetime.timedelta(days=14):
            problems.append(f"{name}: анонс — не раньше чем за 14 дней до начала")
        if end - start > datetime.timedelta(days=31):
            problems.append(f"{name}: событие — не дольше 31 дня")
    except (KeyError, ValueError) as error:
        problems.append(f"{name}: даты — {error}")
    for kind, file in event.get("media", {}).items():
        path = EVENTS / name / file
        if kind not in SIZES:
            problems.append(f"{name}: неизвестный вид картинки {kind}")
        elif not path.exists():
            problems.append(f"{name}/{file}: нет файла")
        elif image_size(path) != SIZES[kind]:
            problems.append(f"{name}/{file}: {image_size(path)}, нужно {SIZES[kind]}")
    nomination = event.get("nomination")
    if nomination:
        if not nomination.get("name") or not nomination.get("description"):
            problems.append(f"{name}: у номинации нужны name и description")
        if nomination.get("type") not in ("APP_LAUNCH", "APP_ENHANCEMENTS", "NEW_CONTENT"):
            problems.append(f"{name}: тип номинации — APP_LAUNCH, APP_ENHANCEMENTS или NEW_CONTENT")
    return problems


def check() -> list[str]:
    return [p for folder in sorted(EVENTS.iterdir()) if (folder / "event.json").exists() for p in check_event(folder.name)]


# --- App Store Connect ---------------------------------------------------------------------------

def app_id() -> str:
    from testflight_info import BUNDLE_ID, call
    apps = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not apps:
        sys.exit(f"Приложение {BUNDLE_ID} не найдено в App Store Connect")
    return apps[0]["id"]


def find_event(app: str, reference: str) -> dict | None:
    from testflight_info import call
    events = call("GET", f"/apps/{app}/appEvents?limit=200")["data"]
    return next((e for e in events if e["attributes"].get("referenceName") == reference), None)


def event_attributes(event: dict) -> dict:
    attributes = {
        "referenceName": event["referenceName"],
        "badge": event["badge"],
        "purpose": event["purpose"],
        "priority": event["priority"],
        "primaryLocale": event["primaryLocale"],
        "territorySchedules": [{
            "territories": event["territories"],
            "publishStart": utc(event["publishStart"]),
            "eventStart": utc(event["eventStart"]),
            "eventEnd": utc(event["eventEnd"]),
        }],
    }
    if event.get("deepLink"):
        attributes["deepLink"] = event["deepLink"]
    # Без него событие нельзя отправить на проверку («нужна ли покупка»).
    attributes["purchaseRequirement"] = event.get("purchaseRequirement", "NO_COST_ASSOCIATED")
    return attributes


def upload_media(localization_id: str, kind: str, path: Path) -> None:
    """Картинка локализации: та же (имя и размер) — оставляем, другая — заменяем."""
    from testflight_info import call
    data = path.read_bytes()
    existing = [s for s in call("GET", f"/appEventLocalizations/{localization_id}/appEventScreenshots")["data"]
                if s["attributes"].get("appEventAssetType") == kind]
    if any(s["attributes"].get("fileName") == path.name and s["attributes"].get("fileSize") == len(data)
           for s in existing):
        print(f"  {kind}: {path.name} уже загружена")
        return
    for old in existing:
        call("DELETE", f"/appEventScreenshots/{old['id']}")
    shot = call("POST", "/appEventScreenshots", {"data": {
        "type": "appEventScreenshots",
        "attributes": {"fileName": path.name, "fileSize": len(data), "appEventAssetType": kind},
        "relationships": {"appEventLocalization": {"data": {"type": "appEventLocalizations", "id": localization_id}}}}})["data"]
    for operation in shot["attributes"]["uploadOperations"]:
        part = data[operation["offset"]:operation["offset"] + operation["length"]]
        request = urllib.request.Request(operation["url"], data=part, method=operation["method"],
                                         headers={h["name"]: h["value"] for h in operation.get("requestHeaders", [])})
        with urllib.request.urlopen(request, timeout=120):
            pass
    call("PATCH", f"/appEventScreenshots/{shot['id']}", {"data": {
        "type": "appEventScreenshots", "id": shot["id"], "attributes": {"uploaded": True}}})
    print(f"  {kind}: {path.name} загружена")


def wait_for_media(event_id: str) -> None:
    """Перед отправкой на проверку картинки должны обработаться (до ~10 минут)."""
    from testflight_info import call
    states = []
    for _ in range(60):
        states = []
        for localization in call("GET", f"/appEvents/{event_id}/localizations")["data"]:
            for shot in call("GET", f"/appEventLocalizations/{localization['id']}/appEventScreenshots")["data"]:
                states.append((shot["attributes"].get("assetDeliveryState") or {}).get("state"))
        if states and all(s == "COMPLETE" for s in states):
            return
        if any(s == "FAILED" for s in states):
            sys.exit("Картинка не прошла обработку в App Store Connect — проверьте размер и формат")
        time.sleep(10)
    print(f"::warning::Картинки ещё обрабатываются ({', '.join(str(s) for s in states)}) — отправляем как есть")


def release_version(app: str) -> dict:
    """Версия MARKETING_VERSION, которая готовится к отправке, со сборкой — иначе выходим с причиной."""
    from release import EDITABLE as VERSION_EDITABLE, marketing_version
    from testflight_info import call
    number = marketing_version()
    versions = call("GET", f"/apps/{app}/appStoreVersions?filter[platform]=IOS&filter[versionString]={number}")["data"]
    version = next((v for v in versions if v["attributes"].get("appStoreState") in VERSION_EDITABLE), None)
    if version is None:
        sys.exit(f"Версии {number} в подготовке к отправке нет — сначала App Store release")
    if not call("GET", f"/appStoreVersions/{version['id']}/build").get("data"):
        sys.exit(f"К версии {number} не привязана сборка — App Store release с номером сборки")
    print(f"Версия {number} со сборкой — готова к отправке")
    return version


def submit_event(app: str, event_id: str, version_id: str | None = None) -> None:
    """Заявка на проверку с событием (и с версией, если `version_id`).

    Если уже есть неотправленная заявка (например, владелец добавил версию через Add for Review),
    кладём событие в неё. С версией (`--with-version`, отправку попросил владелец) заявку отправляем;
    без неё и при чужих объектах в заявке — не отправляем: решение за владельцем, а проверять событие
    будут вместе с новой сборкой."""
    from testflight_info import call
    open_ones = call("GET", f"/apps/{app}/reviewSubmissions?filter[platform]=IOS&filter[state]=READY_FOR_REVIEW")["data"]
    submission = open_ones[0] if open_ones else None
    events, versions, others = [], [], 0
    if submission:
        items = call("GET", f"/reviewSubmissions/{submission['id']}/items?include=appEvent,appStoreVersion")["data"]
        for item in items:
            rel = item.get("relationships", {})
            event = (rel.get("appEvent", {}).get("data") or {}).get("id")
            version = (rel.get("appStoreVersion", {}).get("data") or {}).get("id")
            if event:
                events.append(event)
            if version:
                versions.append(version)
            mine = (event is not None and event == event_id) or (version is not None and version == version_id)
            if not mine:
                others += 1
    else:
        submission = call("POST", "/reviewSubmissions", {"data": {
            "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]

    def add(kind: str, type_name: str, item_id: str) -> None:
        call("POST", "/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission["id"]}},
                              kind: {"data": {"type": type_name, "id": item_id}}}}})

    if version_id and version_id not in versions:
        add("appStoreVersion", "appStoreVersions", version_id)
        print("Версия добавлена в заявку")
    if event_id not in events:
        add("appEvent", "appEvents", event_id)
        print("Событие добавлено в заявку")
    if not version_id and others:
        print("Событие добавлено в неотправленную заявку вместе с версией. Отправьте заявку в App Store Connect "
              "(Distribution → App Review → Submit for Review) — событие уйдёт вместе с ней")
        return
    call("PATCH", f"/reviewSubmissions/{submission['id']}", {"data": {
        "type": "reviewSubmissions", "id": submission["id"], "attributes": {"submitted": True}}})
    print("Отправлено на проверку Apple: " + ("версия и событие" if version_id else "событие"))


def run_event(name: str, submit: bool, with_version: bool = False) -> None:
    from testflight_info import call, upsert
    event = load(name)
    app = app_id()
    current = find_event(app, event["referenceName"])
    if current and current["attributes"].get("eventState") not in EDITABLE:
        print(f"Событие «{event['referenceName']}»: {current['attributes'].get('eventState')} — менять нечего")
        return
    attributes = event_attributes(event)
    if current:
        event_id = current["id"]
    else:
        # purchaseRequirement при создании API не принимает (500) — его задаёт PATCH ниже.
        created = {k: v for k, v in attributes.items() if k != "purchaseRequirement"}
        event_id = call("POST", "/appEvents", {"data": {"type": "appEvents", "attributes": created,
                        "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]["id"]
        print(f"Событие «{event['referenceName']}» создано")
    call("PATCH", f"/appEvents/{event_id}", {"data": {"type": "appEvents", "id": event_id, "attributes": attributes}})
    print(f"Событие «{event['referenceName']}»: сроки, значок, цель, «без покупок» — готово")
    localizations = {item["attributes"]["locale"]: item for item in call("GET", f"/appEvents/{event_id}/localizations")["data"]}
    for locale, texts in event["localizations"].items():
        fields = {k: texts[k] for k in LIMITS}
        if locale in localizations:
            upsert("appEventLocalizations", localizations[locale], fields, ("appEvent", "appEvents", event_id))
        else:
            call("POST", "/appEventLocalizations", {"data": {"type": "appEventLocalizations",
                 "attributes": dict(fields, locale=locale),
                 "relationships": {"appEvent": {"data": {"type": "appEvents", "id": event_id}}}}})
        print(f"Тексты ({locale}) — готово")
    localizations = {item["attributes"]["locale"]: item for item in call("GET", f"/appEvents/{event_id}/localizations")["data"]}
    for locale, localization in localizations.items():
        print(f"Картинки ({locale}):")
        for kind, file in event["media"].items():
            upload_media(localization["id"], kind, EVENTS / name / file)
    if submit:
        wait_for_media(event_id)
        submit_event(app, event_id, release_version(app)["id"] if with_version else None)


def run_nomination(name: str, submit: bool) -> None:
    from testflight_info import call
    event = load(name)
    nomination = event["nomination"]
    app = app_id()
    found = None
    for state in ("DRAFT", "SUBMITTED"):
        rows = call("GET", f"/nominations?filter[state]={state}&filter[relatedApps]={app}&limit=200")["data"]
        found = found or next((n for n in rows if n["attributes"].get("name") == nomination["name"]), None)
    current_event = find_event(app, event["referenceName"])
    event_state = current_event["attributes"].get("eventState") if current_event else "нет"
    attach = current_event is not None and event_state in APPROVED
    print(f"Событие «{event['referenceName']}»: {event_state}")
    state = found["attributes"].get("state") if found else None
    if state == "SUBMITTED" and not attach:
        # Отправленную номинацию трогаем, только когда есть что прикрепить.
        print(f"Номинация «{nomination['name']}» отправлена; событие прикрепим, когда Apple его одобрит")
        return
    attributes = {
        "name": nomination["name"],
        "type": nomination["type"],
        "description": nomination["description"],
        "notes": nomination.get("notes", ""),
        "publishStartDate": utc(nomination["publishStart"]),
        "publishEndDate": utc(nomination["publishEnd"]),
        "deviceFamilies": nomination["deviceFamilies"],
        "locales": nomination["locales"],
        "supplementalMaterialsUris": nomination.get("supplementalMaterialsUris", []),
        "hasInAppEvents": bool(attach),
    }
    relationships = {"supportedTerritories": {"data": [{"type": "territories", "id": t} for t in nomination["territories"]]}}
    if attach:
        relationships["inAppEvents"] = {"data": [{"type": "appEvents", "id": current_event["id"]}]}
    if found is None:
        attributes["submitted"] = submit
        relationships["relatedApps"] = {"data": [{"type": "apps", "id": app}]}
        call("POST", "/nominations", {"data": {"type": "nominations", "attributes": attributes, "relationships": relationships}})
        print(f"Номинация «{nomination['name']}» создана" + (" и отправлена" if submit else " (черновик)"))
    else:
        attributes.pop("type")  # после отправки тип не меняется
        # PATCH без submitted (или archived) API не принимает; отправленная остаётся отправленной.
        attributes["submitted"] = True if state == "SUBMITTED" else submit
        call("PATCH", f"/nominations/{found['id']}", {"data": {"type": "nominations", "id": found["id"],
             "attributes": attributes, "relationships": relationships}})
        print(f"Номинация «{nomination['name']}» обновлена ({found['attributes'].get('state')}"
              + (" → отправлена" if submit and found["attributes"].get("state") == "DRAFT" else "") + ")")
    print("Событие прикреплено к номинации" if attach else
          "Событие ещё не одобрено — прикрепим следующим запуском, когда Apple его одобрит")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="только проверить файлы событий")
    parser.add_argument("action", nargs="?", choices=["event", "nominate"])
    parser.add_argument("name", nargs="?", help="папка события в appstore/events/")
    parser.add_argument("--submit", action="store_true", help="отправить: событие — на проверку, номинацию — Apple")
    parser.add_argument("--with-version", action="store_true",
                        help="с --submit: отправить вместе с версией MARKETING_VERSION (решение владельца)")
    args = parser.parse_args()
    problems = check()
    for problem in problems:
        print(f"::error::{problem}")
    if problems:
        sys.exit(1)
    print("Файлы событий в порядке")
    if args.check:
        return
    if not args.action or not args.name:
        parser.error("нужно действие (event или nominate) и имя события")
    if args.action == "event":
        run_event(args.name, args.submit, args.with_version)
    else:
        run_nomination(args.name, args.submit)


if __name__ == "__main__":
    main()
