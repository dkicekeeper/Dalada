#!/usr/bin/env python3
"""Фото мест редакции: Wikimedia Commons → photos.csv → миграция; файлы — на R2 (workflow Editorial photos).

    python3 supabase/data/places/photos.py check                    # проверить таблицу и миграцию (CI)
    python3 supabase/data/places/photos.py candidates [--sheets DIR] [--progress F]  # кандидаты → photo_candidates.csv
    python3 supabase/data/places/photos.py sheets DIR               # листы превью кандидатов для просмотра
    python3 supabase/data/places/photos.py accept                   # include=yes из кандидатов → photos.csv
    python3 supabase/data/places/photos.py migration                # записать миграцию из photos.csv
    python3 supabase/data/places/photos.py fetch DIR [--existing F] # скачать недостающие файлы для R2 (CI)

Фото — только со свободной лицензией (CC0, CC BY, CC BY-SA, общественное достояние); автор и лицензия
показываются в приложении под фото. Подробности — README.md рядом.
"""

import csv
import hashlib
import html
import io
import json
import math
import re
import sys
import time
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
PLACES = HERE / "places.csv"
TABLE = HERE / "photos.csv"
CANDIDATES = HERE / "photo_candidates.csv"
MIGRATIONS = HERE.parent.parent / "migrations"
SUFFIX = "_editorial_photos.sql"
FIELDS = ["id", "place_id", "position", "file", "author", "license", "license_url", "width", "height"]
CANDIDATE_FIELDS = [
    "include", "place_id", "place", "type", "file", "score", "reason", "author", "license", "license_url",
    "width", "height", "page", "thumb",
]

USER_AGENT = "DaladaEditorialPhotos/1.0 (https://github.com/dkicekeeper/Dalada)"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
OSM_API = "https://api.openstreetmap.org/api/0.6"
# Фото на место — не больше.
MAX_PER_PLACE = 5
# Радиус поиска фото вокруг места по типу, м (у больших водоёмов центр далеко от берега).
RADIUS_M = {
    "water_body": 5000, "landmark": 1000, "spring": 500, "campsite": 1000, "fishing_spot": 2000,
    "paid_pond": 500, "base": 500, "parking": 300, "tackle_shop": 200,
}
MIN_WIDTH = 1000
LICENSE = re.compile(r"^(CC0|CC BY(-SA)? \d\.\d|CC BY(-SA)? \d\.\d [a-z]{2}|CC BY(-SA)?|Public domain|PD.*)$", re.I)


def fail(errors: list[str]) -> None:
    for error in errors:
        print(f"ошибка: {error}", file=sys.stderr)
    sys.exit(1)


def read_csv(path: Path) -> list[dict]:
    if not path.exists():
        return []
    with path.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, fields: list[str], rows: list[dict]) -> None:
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row.get(k, "") for k in fields})


def validate(rows: list[dict]) -> list[str]:
    errors = []
    places = {r["id"] for r in read_csv(PLACES)}
    seen_ids, seen_files = set(), set()
    for i, r in enumerate(rows, start=2):
        where = f"{TABLE.name}:{i}"
        try:
            uuid.UUID(r["id"])
        except ValueError:
            errors.append(f"{where}: id — не UUID")
        if r["id"] in seen_ids:
            errors.append(f"{where}: id повторяется")
        seen_ids.add(r["id"])
        if r["place_id"] not in places:
            errors.append(f"{where}: place_id нет в places.csv")
        if not r["file"].startswith("File:"):
            errors.append(f"{where}: file — название файла на Commons, «File:…»")
        if (r["place_id"], r["file"]) in seen_files:
            errors.append(f"{where}: фото у места повторяется")
        seen_files.add((r["place_id"], r["file"]))
        if not r["author"].strip():
            errors.append(f"{where}: нет автора")
        if not LICENSE.match(r["license"].strip()):
            errors.append(f"{where}: лицензия «{r['license']}» — нужна CC0, CC BY, CC BY-SA или PD")
        for key in ("position", "width", "height"):
            if not r[key].isdigit():
                errors.append(f"{where}: {key} — число")
    for place in {r["place_id"] for r in rows}:
        count = sum(1 for r in rows if r["place_id"] == place)
        if count > MAX_PER_PLACE:
            errors.append(f"у места {place} {count} фото — не больше {MAX_PER_PLACE}")
    return errors


def table_hash() -> str:
    return hashlib.sha256(TABLE.read_bytes()).hexdigest() if TABLE.exists() else ""


def latest_migration() -> Path | None:
    found = sorted(MIGRATIONS.glob(f"*{SUFFIX}"))
    return found[-1] if found else None


def check() -> None:
    rows = read_csv(TABLE)
    errors = validate(rows)
    last = latest_migration()
    if rows and last is None:
        errors.append("нет миграции с фото мест — выполните `photos.py migration`")
    elif last is not None and f"photos.csv sha256: {table_hash()}" not in last.read_text(encoding="utf-8"):
        errors.append(f"{TABLE.name} изменилась после {last.name} — выполните `photos.py migration`")
    if errors:
        fail(errors)
    places = len({r["place_id"] for r in rows})
    print(f"{TABLE.name}: {len(rows)} фото у {places} мест")


# Поиск кандидатов -----------------------------------------------------------------------------

def get_json(url: str, params: dict | None = None, retries: int = 6) -> dict:
    if params:
        url += "?" + urllib.parse.urlencode(params)
    for attempt in range(retries):
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.loads(response.read().decode("utf-8"))
        except Exception as error:  # noqa: BLE001 — сеть: повторяем
            if attempt == retries - 1:
                raise
            # 429 — подождать подольше (или сколько просит сервер).
            wait = 5 * 2 ** attempt
            retry_after = getattr(error, "headers", None) and error.headers.get("Retry-After")
            if retry_after and retry_after.isdigit():
                wait = max(wait, int(retry_after))
            host = urllib.parse.urlsplit(url).hostname
            print(f"  {host}: повтор через {wait} с: {error}", file=sys.stderr)
            time.sleep(wait)
    return {}


def commons(params: dict) -> dict:
    time.sleep(2)
    return get_json(COMMONS_API, {"format": "json", "formatversion": "2", **params})


def osm_tags(source: str) -> dict:
    match = re.fullmatch(r"osm:([nwr])(\d+)", source)
    if not match:
        return {}
    kind = {"n": "node", "w": "way", "r": "relation"}[match.group(1)]
    time.sleep(0.2)
    try:
        data = get_json(f"{OSM_API}/{kind}/{match.group(2)}.json")
    except Exception:  # noqa: BLE001 — нет объекта: без тегов
        return {}
    elements = data.get("elements") or [{}]
    return elements[0].get("tags", {})


def file_title(value: str) -> str | None:
    """«File:X.jpg» из тега OSM (название файла или ссылка на Commons)."""
    value = urllib.parse.unquote(value.strip())
    match = re.search(r"(File:[^|#?]+\.(?:jpe?g|png))", value, re.I)
    if match:
        return match.group(1).replace("_", " ")
    return None


def tokens(*names: str) -> set[str]:
    words = set()
    for name in names:
        for word in re.findall(r"[\w-]+", name.lower()):
            word = word.replace("ё", "е")
            if len(word) >= 4 and word not in {"озеро", "lake", "река", "river", "родник", "spring", "водопад", "waterfall"}:
                words.add(word[:6])
    return words


IMAGE_INFO = {
    "prop": "imageinfo|coordinates", "iiprop": "url|size|mime|extmetadata", "iiurlwidth": "330",
    "iiextmetadatafilter": "LicenseShortName|LicenseUrl|Artist", "colimit": "max",
}


def pages_with_info(params: dict) -> list[dict]:
    """Файлы из генератора вместе со сведениями об изображении — одним запросом."""
    result = commons({"action": "query", **params, **IMAGE_INFO})
    return result.get("query", {}).get("pages", [])


def meta_of(page: dict) -> dict | None:
    ii = (page.get("imageinfo") or [None])[0]
    if not ii:
        return None
    meta = ii.get("extmetadata", {})
    return {
        "mime": ii.get("mime", ""),
        "width": ii.get("width", 0),
        "height": ii.get("height", 0),
        "page": ii.get("descriptionurl", ""),
        "thumb": ii.get("thumburl", ""),
        "license": plain(meta.get("LicenseShortName", {}).get("value", "")),
        "license_url": plain(meta.get("LicenseUrl", {}).get("value", "")),
        "author": author_name(plain(meta.get("Artist", {}).get("value", ""))),
    }


def author_name(text: str) -> str:
    """Имя автора без служебного: «User:», телефонов и приписок о склейке панорам."""
    text = re.sub(r"\+?\d[\d\s()-]{6,}\d", "", text)
    text = re.sub(r"\bUser:", "", text)
    text = re.sub(r"\s*This panoramic image was created.*$", "", text)
    text = re.sub(r"\s+stitched by\s+", ", ", text)
    return re.sub(r"\s+", " ", text).strip(" ,")


def distance_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 2 * 6_371_000 * math.asin(math.sqrt(h))


def candidates_for(place: dict, tags: dict) -> dict[str, tuple[float, str, dict]]:
    """Кандидаты места: файл → (оценка, откуда, сведения)."""
    found: dict[str, tuple[float, str, dict]] = {}

    def add(page: dict, score: float, reason: str) -> None:
        meta = meta_of(page)
        title = page.get("title", "")
        if meta and (title not in found or found[title][0] < score):
            found[title] = (score, reason, meta)

    for key in ("wikimedia_commons", "image"):
        value = tags.get(key, "")
        if title := file_title(value):
            for page in pages_with_info({"titles": title}):
                add(page, 5, f"osm {key}")
        elif value.startswith("Category:"):
            for page in pages_with_info({
                "generator": "categorymembers", "gcmtitle": value, "gcmtype": "file", "gcmlimit": "15",
            }):
                add(page, 4, "osm category")
    if qid := tags.get("wikidata"):
        for page in pages_with_info({
            "generator": "search", "gsrsearch": f"haswbstatement:P180={qid}", "gsrnamespace": "6", "gsrlimit": "15",
        }):
            add(page, 4, "wikidata depicts")

    names = [place["name"]] + [tags.get(k, "") for k in ("name", "name:ru", "name:kk", "name:en")]
    words = tokens(*names)
    radius = RADIUS_M.get(place["type"], 1000)
    here = (float(place["lat"]), float(place["lon"]))
    for page in pages_with_info({
        "generator": "geosearch", "ggscoord": f"{place['lat']}|{place['lon']}", "ggsradius": str(radius),
        "ggsnamespace": "6", "ggslimit": "40",
    }):
        lowered = page.get("title", "").lower().replace("ё", "е").replace("_", " ")
        named = any(w in lowered for w in words)
        coords = (page.get("coordinates") or [{}])[0]
        dist = distance_m(here, (coords.get("lat", here[0]), coords.get("lon", here[1])))
        score = 1.0 + (1.5 if named else 0) - min(dist / radius, 1) * 0.5
        add(page, score, "nearby, name" if named else "nearby")
    return found


def plain(text: str) -> str:
    text = re.sub(r"<[^>]+>", "", text or "")
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def find_candidates(sheets: Path | None, only: set[str] | None, progress: Path | None) -> None:
    """Ищет кандидатов и сохраняет таблицу после каждого места; с progress — продолжает с места остановки."""
    places = [p for p in read_csv(PLACES) if not only or p["id"] in only]
    order = {p["id"]: i for i, p in enumerate(read_csv(PLACES))}
    done = set(progress.read_text().split()) if progress and progress.exists() else set()
    current = read_csv(CANDIDATES)
    previous = {(r["place_id"], r["file"]): r["include"] for r in current}
    for n, place in enumerate(places, start=1):
        if place["id"] in done:
            continue
        print(f"[{n}/{len(places)}] {place['name']}", file=sys.stderr)
        tags = osm_tags(place["source"])
        found = candidates_for(place, tags)
        usable = []
        for title, (score, reason, meta) in found.items():
            if meta["mime"] not in ("image/jpeg", "image/png"):
                continue
            if meta["width"] < MIN_WIDTH or not LICENSE.match(meta["license"]) or not meta["author"]:
                continue
            usable.append((score, title, reason, meta))
        usable.sort(key=lambda x: -x[0])
        place_rows = [{
            "include": previous.get((place["id"], title), ""),
            "place_id": place["id"], "place": place["name"], "type": place["type"], "file": title,
            "score": f"{score:.2f}", "reason": reason, "author": meta["author"][:200],
            "license": meta["license"], "license_url": meta["license_url"],
            "width": meta["width"], "height": meta["height"], "page": meta["page"], "thumb": meta["thumb"],
        } for score, title, reason, meta in usable[:12]]
        current = [r for r in current if r["place_id"] != place["id"]] + place_rows
        current.sort(key=lambda r: order.get(r["place_id"], 1 << 30))
        write_csv(CANDIDATES, CANDIDATE_FIELDS, current)
        if progress:
            with progress.open("a") as f:
                f.write(place["id"] + "\n")
    print(f"записано {CANDIDATES.name}: {len(current)} кандидатов у {len({r['place_id'] for r in current})} мест")
    if sheets:
        contact_sheets(current, sheets)


def contact_sheets(rows: list[dict], folder: Path) -> None:
    """Листы превью для просмотра: по месту — пронумерованные превью (готовые листы не пересобираются)."""
    from PIL import Image, ImageDraw

    folder.mkdir(parents=True, exist_ok=True)
    by_place: dict[str, list[dict]] = {}
    for r in rows:
        by_place.setdefault(r["place_id"], []).append(r)
    size = 220
    for place_id, items in by_place.items():
        target = folder / f"{place_id}.jpg"
        if target.exists():
            continue
        sheet = Image.new("RGB", (size * min(len(items), 6), (size + 20) * math.ceil(len(items) / 6)), "white")
        draw = ImageDraw.Draw(sheet)
        for i, r in enumerate(items):
            # Превью стандартной ширины Commons — нестандартные он отдаёт неохотно.
            url = re.sub(r"/\d+px-", "/330px-", r["thumb"])
            try:
                image = Image.open(io.BytesIO(get_bytes(url, retries=4))).convert("RGB")
            except Exception:  # noqa: BLE001 — без превью: пустая клетка
                continue
            image.thumbnail((size - 6, size - 6))
            x, y = (i % 6) * size, (i // 6) * (size + 20)
            sheet.paste(image, (x + 3, y + 3))
            draw.text((x + 4, y + size), f"{i + 1}. {r['score']} {r['reason']}", fill="black")
        sheet.save(target, quality=80)
        print(f"лист {target.name}: {items[0]['place']}", file=sys.stderr)


# Принятые кандидаты → photos.csv ---------------------------------------------------------------

def accept() -> None:
    rows = read_csv(TABLE)
    existing = {(r["place_id"], r["file"]) for r in rows}
    added = 0
    # include: «yes» или номер — порядок фото у места (1 — обложка).
    chosen = [c for c in read_csv(CANDIDATES) if c["include"].strip().lower() == "yes" or c["include"].strip().isdigit()]
    chosen.sort(key=lambda c: int(c["include"]) if c["include"].strip().isdigit() else 1 << 20)
    for c in chosen:
        if (c["place_id"], c["file"]) in existing:
            continue
        position = 1 + max((int(r["position"]) for r in rows if r["place_id"] == c["place_id"]), default=0)
        rows.append({
            "id": str(uuid.uuid4()), "place_id": c["place_id"], "position": str(position), "file": c["file"],
            "author": c["author"], "license": c["license"], "license_url": c["license_url"],
            "width": c["width"], "height": c["height"],
        })
        existing.add((c["place_id"], c["file"]))
        added += 1
    order = {p["id"]: i for i, p in enumerate(read_csv(PLACES))}
    rows.sort(key=lambda r: (order.get(r["place_id"], 1 << 30), int(r["position"])))
    errors = validate(rows)
    if errors:
        fail(errors)
    write_csv(TABLE, FIELDS, rows)
    print(f"{TABLE.name}: добавлено {added}, всего {len(rows)}")


# Миграция --------------------------------------------------------------------------------------

def literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def migration() -> None:
    rows = read_csv(TABLE)
    errors = validate(rows)
    if errors:
        fail(errors)
    last = latest_migration()
    digest = table_hash()
    if last is not None and f"photos.csv sha256: {digest}" in last.read_text(encoding="utf-8"):
        print(f"{TABLE.name} не менялась после {last.name}")
        return

    newest = sorted(MIGRATIONS.glob("*.sql"))[-1].name[:14]
    stamp = max(
        datetime.strptime(newest, "%Y%m%d%H%M%S").replace(hour=10, minute=0, second=0) + timedelta(days=1),
        datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0),
    ).strftime("%Y%m%d%H%M%S")
    out = io.StringIO()
    out.write(
        "-- Фото мест редакции из supabase/data/places/photos.csv — собрано photos.py, руками не править.\n"
        f"-- photos.csv sha256: {digest}\n"
        "-- Фото — с Wikimedia Commons под свободными лицензиями; файлы на R2 кладёт workflow Editorial photos.\n"
        "--\n"
        "-- Новые фото добавляются, изменённые обновляются, убранные из таблицы удаляются.\n\n"
    )
    if rows:
        out.write(
            "insert into public.place_editorial_photos as f (\n"
            "  id, place_id, position, commons_file, author, license, license_url, width, height\n"
            ")\nvalues\n"
        )
        values = []
        for r in rows:
            license_url = literal(r["license_url"]) if r["license_url"] else "null"
            values.append(
                f"  ({literal(r['id'])}, {literal(r['place_id'])}, {int(r['position'])}, {literal(r['file'])}, "
                f"{literal(r['author'])}, {literal(r['license'])}, {license_url}, {int(r['width'])}, {int(r['height'])})"
            )
        out.write(",\n".join(values))
        out.write(
            "\non conflict (id) do update\n"
            "   set place_id = excluded.place_id,\n"
            "       position = excluded.position,\n"
            "       commons_file = excluded.commons_file,\n"
            "       author = excluded.author,\n"
            "       license = excluded.license,\n"
            "       license_url = excluded.license_url,\n"
            "       width = excluded.width,\n"
            "       height = excluded.height;\n\n"
        )
    ids = ", ".join(literal(r["id"]) for r in rows)
    out.write(
        "delete from public.place_editorial_photos"
        + (f"\n where id <> all (array[{ids}]::uuid[]);\n" if rows else ";\n")
    )
    path = MIGRATIONS / f"{stamp}{SUFFIX}"
    path.write_text(out.getvalue(), encoding="utf-8")
    print(f"записано {path.relative_to(HERE.parent.parent.parent)}: {len(rows)} фото")


# Файлы для R2 ----------------------------------------------------------------------------------

# Размеры — из стандартного ряда превью Commons (другие размеры Commons отдаёт неохотно).
FULL_WIDTH = 1280
THUMB_WIDTH = 500
THUMB_SIDE = 400


def get_bytes(url: str, retries: int = 6) -> bytes:
    for attempt in range(retries):
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return response.read()
        except Exception as error:  # noqa: BLE001 — сеть: повторяем
            if attempt == retries - 1:
                raise
            wait = 5 * 2 ** attempt
            print(f"  повтор через {wait} с: {error}", file=sys.stderr)
            time.sleep(wait)
    return b""


def jpeg(data: bytes, max_side: int | None = None, min_side: int | None = None) -> bytes:
    """JPEG без метаданных: вписать в max_side или уменьшить до min_side по короткой стороне."""
    from PIL import Image

    image = Image.open(io.BytesIO(data)).convert("RGB")
    if max_side and max(image.size) > max_side:
        image.thumbnail((max_side, max_side), Image.LANCZOS)
    if min_side and min(image.size) > min_side:
        scale = min_side / min(image.size)
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    out = io.BytesIO()
    image.save(out, "JPEG", quality=82, optimize=True, progressive=True)
    return out.getvalue()


def fetch(folder: Path, existing_list: Path | None) -> None:
    """Скачивает с Commons фото, которых ещё нет на R2: <id>.jpg и <id>_thumb.jpg."""
    rows = read_csv(TABLE)
    existing = set(existing_list.read_text().split()) if existing_list and existing_list.exists() else set()
    missing = [r for r in rows if not {f"{r['id']}.jpg", f"{r['id']}_thumb.jpg"} <= existing]
    folder.mkdir(parents=True, exist_ok=True)
    urls: dict[str, tuple[str, str]] = {}
    titles = sorted({r["file"] for r in missing})
    for i in range(0, len(titles), 40):
        for width, slot in ((FULL_WIDTH, 0), (THUMB_WIDTH, 1)):
            result = commons({
                "action": "query", "titles": "|".join(titles[i:i + 40]), "prop": "imageinfo",
                "iiprop": "url", "iiurlwidth": str(width),
            })
            for page in result.get("query", {}).get("pages", []):
                ii = (page.get("imageinfo") or [None])[0]
                if ii:
                    pair = list(urls.get(page["title"], ("", "")))
                    pair[slot] = ii.get("thumburl") or ii.get("url", "")
                    urls[page["title"]] = (pair[0], pair[1])
    failed = []
    for r in missing:
        full_url, thumb_url = urls.get(r["file"], ("", ""))
        if not full_url:
            failed.append(r["file"])
            continue
        print(f"{r['file']}", file=sys.stderr)
        full = get_bytes(full_url)
        (folder / f"{r['id']}.jpg").write_bytes(jpeg(full, max_side=FULL_WIDTH))
        thumb = get_bytes(thumb_url) if thumb_url and thumb_url != full_url else full
        (folder / f"{r['id']}_thumb.jpg").write_bytes(jpeg(thumb, min_side=THUMB_SIDE))
        time.sleep(1)
    print(f"скачано {len(missing) - len(failed)} из {len(missing)} недостающих фото (всего {len(rows)})")
    if failed:
        fail([f"нет файла на Commons: {title}" for title in failed])


def main(argv: list[str]) -> None:
    if argv[:1] == ["check"]:
        check()
    elif argv[:1] == ["candidates"]:
        sheets = Path(argv[argv.index("--sheets") + 1]) if "--sheets" in argv else None
        only = set(argv[argv.index("--place") + 1].split(",")) if "--place" in argv else None
        progress = Path(argv[argv.index("--progress") + 1]) if "--progress" in argv else None
        find_candidates(sheets, only, progress)
    elif argv[:1] == ["sheets"] and len(argv) >= 2:
        contact_sheets(read_csv(CANDIDATES), Path(argv[1]))
    elif argv[:1] == ["accept"]:
        accept()
    elif argv[:1] == ["migration"]:
        migration()
    elif argv[:1] == ["fetch"] and len(argv) >= 2:
        existing = Path(argv[argv.index("--existing") + 1]) if "--existing" in argv else None
        fetch(Path(argv[1]), existing)
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv[1:])
