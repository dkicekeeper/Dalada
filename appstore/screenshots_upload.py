#!/usr/bin/env python3
"""Скриншоты для App Store → версия, которая готовится к отправке, через App Store Connect API.

    python3 appstore/screenshots_upload.py <папка framed> [--display APP_IPHONE_67]

Берёт <папка>/ru/*.png → локаль ru и <папка>/en/*.png → en-US (по имени файла: 01-map, 02-place…,
не больше 10) и заменяет ими скриншоты iPhone 6,9″ версии: старые удаляет, новые загружает по
порядку. Размер — 1320 × 2868 (appstore/screenshots/frame.py).

Нужны ASC_KEY_ID, ASC_ISSUER_ID и ASC_KEY_PATH — как у appstore/testflight_info.py.
"""

import argparse
import hashlib
import sys
import urllib.request
from pathlib import Path

from testflight_info import BUNDLE_ID, call

FOLDERS = {"ru": "ru", "en-US": "en"}
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
LIMIT = 10


def screenshot_set(localization_id: str, display: str) -> str:
    sets = call("GET", f"/appStoreVersionLocalizations/{localization_id}/appScreenshotSets"
                       f"?filter[screenshotDisplayType]={display}")["data"]
    if sets:
        return sets[0]["id"]
    return call("POST", "/appScreenshotSets", {"data": {
        "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
        "relationships": {"appStoreVersionLocalization": {
            "data": {"type": "appStoreVersionLocalizations", "id": localization_id}}}}})["data"]["id"]


def upload(set_id: str, path: Path) -> None:
    data = path.read_bytes()
    screenshot = call("POST", "/appScreenshots", {"data": {
        "type": "appScreenshots", "attributes": {"fileName": path.name, "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
    for operation in screenshot["attributes"]["uploadOperations"]:
        part = data[operation["offset"]:operation["offset"] + operation["length"]]
        request = urllib.request.Request(operation["url"], data=part, method=operation["method"],
                                         headers={h["name"]: h["value"] for h in operation.get("requestHeaders", [])})
        with urllib.request.urlopen(request, timeout=120):
            pass
    call("PATCH", f"/appScreenshots/{screenshot['id']}", {"data": {
        "type": "appScreenshots", "id": screenshot["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("folder", type=Path, help="папка с ru/ и en/ (выход frame.py)")
    parser.add_argument("--display", default="APP_IPHONE_67",
                        help="тип экрана в App Store Connect (6,7″ и 6,9″ — APP_IPHONE_67)")
    args = parser.parse_args()

    files = {locale: sorted((args.folder / folder).glob("*.png"))[:LIMIT] for locale, folder in FOLDERS.items()}
    for locale, paths in files.items():
        if not paths:
            sys.exit(f"::error::Нет скриншотов для {locale} в {args.folder / FOLDERS[locale]}")

    apps = call("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not apps:
        sys.exit(f"Приложение {BUNDLE_ID} не найдено в App Store Connect")
    versions = call("GET", f"/apps/{apps[0]['id']}/appStoreVersions?filter[platform]=IOS&limit=20")["data"]
    version = next((v for v in versions if v["attributes"].get("appStoreState") in EDITABLE), None)
    if version is None:
        sys.exit("::error::Нет версии, которая готовится к отправке (сначала App Store release)")
    localizations = {item["attributes"]["locale"]: item["id"] for item in
                     call("GET", f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]}

    for locale, paths in files.items():
        if locale not in localizations:
            sys.exit(f"::error::У версии нет локали {locale} (сначала App Store page)")
        set_id = screenshot_set(localizations[locale], args.display)
        for old in call("GET", f"/appScreenshotSets/{set_id}/appScreenshots?limit=50")["data"]:
            call("DELETE", f"/appScreenshots/{old['id']}")
        for path in paths:
            upload(set_id, path)
        print(f"Скриншоты ({locale}): {', '.join(p.stem for p in paths)} — загружены")


if __name__ == "__main__":
    main()
