#!/usr/bin/env python3
"""События App Store (In-App Events) и номинации на рекомендацию — из appstore/events/<событие>/.

    python3 appstore/featuring.py --check                    # проверить все события (CI, без ключа)
    python3 appstore/featuring.py event first_ice            # создать или обновить черновик события
    python3 appstore/featuring.py event first_ice --submit   # …и отправить его на проверку Apple
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
    """Перед отправкой на проверку картинки должны обработаться (до ~3 минут)."""
    from testflight_info import call
    for _ in range(18):
        states = []
        for localization in call("GET", f"/appEvents/{event_id}/localizations")["data"]:
            for shot in call("GET", f"/appEventLocalizations/{localization['id']}/appEventScreenshots")["data"]:
                states.append((shot["attributes"].get("assetDeliveryState") or {}).get("state"))
        if states and all(s == "COMPLETE" for s in states):
            return
        if any(s == "FAILED" for s in states):
            sys.exit("Картинка не прошла обработку в App Store Connect — проверьте размер и формат")
        time.sleep(10)
    print("::warning::Картинки ещё обрабатываются — отправляем как есть")


def submit_event(app: str, event_id: str) -> None:
    """Своя заявка на проверку только с событием. Если уже есть неотправленная заявка с чем-то ещё
    (например, с версией) — не трогаем её: отправить вместе — в App Store Connect."""
    from testflight_info import call
    open_ones = call("GET", f"/apps/{app}/reviewSubmissions?filter[platform]=IOS&filter[state]=READY_FOR_REVIEW")["data"]
    submission = None
    for candidate in open_ones:
        items = call("GET", f"/reviewSubmissions/{candidate['id']}/items?include=appEvent")["data"]
        if all((i.get("relationships", {}).get("appEvent", {}).get("data") or {}).get("id") == event_id for i in items):
            submission = candidate
        else:
            sys.exit("Есть неотправленная заявка на проверку с другими объектами — отправьте событие вместе с ней "
                     "в App Store Connect (Distribution → App Review)")
    if submission is None:
        submission = call("POST", "/reviewSubmissions", {"data": {
            "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]
        call("POST", "/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission["id"]}},
                              "appEvent": {"data": {"type": "appEvents", "id": event_id}}}}})
    call("PATCH", f"/reviewSubmissions/{submission['id']}", {"data": {
        "type": "reviewSubmissions", "id": submission["id"], "attributes": {"submitted": True}}})
    print("Событие отправлено на проверку Apple")


def run_event(name: str, submit: bool) -> None:
    from testflight_info import call, upsert
    event = load(name)
    app = app_id()
    current = find_event(app, event["referenceName"])
    if current and current["attributes"].get("eventState") not in EDITABLE:
        print(f"Событие «{event['referenceName']}»: {current['attributes'].get('eventState')} — менять нечего")
        return
    attributes = event_attributes(event)
    if current:
        call("PATCH", f"/appEvents/{current['id']}", {"data": {"type": "appEvents", "id": current["id"], "attributes": attributes}})
        event_id = current["id"]
        print(f"Событие «{event['referenceName']}» обновлено")
    else:
        event_id = call("POST", "/appEvents", {"data": {"type": "appEvents", "attributes": attributes,
                        "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]["id"]
        print(f"Событие «{event['referenceName']}» создано")
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
        submit_event(app, event_id)


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
    attach = current_event and current_event["attributes"].get("eventState") in APPROVED
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
        if found["attributes"].get("state") == "DRAFT":
            attributes["submitted"] = submit
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
        run_event(args.name, args.submit)
    else:
        run_nomination(args.name, args.submit)


if __name__ == "__main__":
    main()
