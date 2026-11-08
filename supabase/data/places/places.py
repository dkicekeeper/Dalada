#!/usr/bin/env python3
"""Места редакции (@dalada): таблица places.csv → миграция.

    python3 supabase/data/places/places.py check             # проверить таблицу и миграцию (CI)
    python3 supabase/data/places/places.py import FILE        # добавить места из KML/KMZ/CSV
    python3 supabase/data/places/places.py migration         # записать миграцию из places.csv

places.csv — единственный источник мест редакции: миграция добавляет новые места, обновляет
изменённые и скрывает удалённые из таблицы. place_info.csv — сведения о месте для карточки (виды
рыбы, подъезд, платно ли, способы ловли, удобства, связь, сезон, особенности): миграция кладёт их в
attributes. Править их в Studio бесполезно — следующая миграция перезапишет. Подробности — README.md
рядом и docs/05-release/content.md.
"""

import csv
import hashlib
import io
import json
import math
import re
import sys
import uuid
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from xml.etree import ElementTree

HERE = Path(__file__).resolve().parent
TABLE = HERE / "places.csv"
MIGRATIONS = HERE.parent.parent / "migrations"
SUFFIX = "_editorial_places.sql"
FIELDS = ["id", "type", "name", "lat", "lon", "access_lat", "access_lon", "description", "source"]
INFO = HERE / "place_info.csv"
PHOTOS = HERE / "photos.csv"
INFO_FIELDS = ["id", "name", "species", "access", "fee", "price_kzt", "price_unit", "contact", "methods",
               "amenities", "signal", "months", "features", "sources"]
# Значения — как в приложении (DaladaCore/PlaceInfo.swift); виды рыбы — public.fish_species.
SPECIES = ["common_carp", "zander", "asp", "wels_catfish", "snakehead", "pike", "perch", "balkhash_perch", "bream",
           "crucian_carp", "silver_carp", "grass_carp", "marinka", "rainbow_trout", "roach", "tench", "other"]
ACCESS = ["asphalt", "dirt", "offroad", "foot", "boat"]
FEES = ["free", "paid"]
PRICE_UNITS = ["entry", "day", "hour", "kg"]
METHODS = ["shore", "boat", "spinning", "feeder", "float", "fly", "bottom", "ice"]
AMENITIES = ["parking", "toilet", "shade", "tent", "fireplace", "drinking_water", "shop", "boat_rental"]
SIGNALS = ["none", "weak", "good"]

TYPES = [
    "fishing_spot", "water_body", "campsite", "paid_pond", "base", "parking", "spring", "tackle_shop",
    "landmark",
]
# Казахстан — с запасом (M34; раньше — Алматинская область, Жетісу и Алматы).
LAT = (40.5, 55.5)
LON = (46.4, 87.4)
# Ближе — считаем повтором того же места того же типа.
DUPLICATE_M = 300
# Точка подъезда — не дальше от места.
ACCESS_M = 20_000

# Папки Google My Maps (слои) → тип места: достаточно части слова.
FOLDER_TYPES = [
    ("платн", "paid_pond"), ("paid", "paid_pond"),
    ("ловл", "fishing_spot"), ("рыбалк", "fishing_spot"), ("балық аулау", "fishing_spot"), ("fishing", "fishing_spot"),
    ("водо", "water_body"), ("озер", "water_body"), ("көл", "water_body"), ("water", "water_body"), ("lake", "water_body"),
    ("стоянк", "campsite"), ("кемпинг", "campsite"), ("camp", "campsite"),
    ("баз", "base"), ("base", "base"),
    ("съезд", "parking"), ("парков", "parking"), ("parking", "parking"),
    ("родник", "spring"), ("источник", "spring"), ("бұлақ", "spring"), ("spring", "spring"),
    ("снаст", "tackle_shop"), ("магазин", "tackle_shop"), ("shop", "tackle_shop"),
    ("достопр", "landmark"), ("интерес", "landmark"), ("landmark", "landmark"),
]


def fail(errors: list[str]) -> None:
    for error in errors:
        print(f"ошибка: {error}", file=sys.stderr)
    sys.exit(1)


def distance_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat = math.radians((a[0] + b[0]) / 2)
    dy = (a[0] - b[0]) * 111_320
    dx = (a[1] - b[1]) * 111_320 * math.cos(lat)
    return math.hypot(dx, dy)


def typographic(name: str) -> str:
    """Кавычки-«ёлочки»: «База "Радуга"» → «База «Радуга»», непарная кавычка — закрывается."""
    name = name.replace("«", '"').replace("»", '"').replace("“", '"').replace("”", '"')
    if name.count('"') % 2:
        name += '"'
    if name.startswith('"') and name.endswith('"') and name.count('"') == 2:
        name = name[1:-1]
    opened = False
    out = []
    for ch in name:
        if ch == '"':
            out.append("»" if opened else "«")
            opened = not opened
        else:
            out.append(ch)
    return "".join(out)


def normalized(name: str) -> str:
    return re.sub(r"[^\w]+", " ", name.lower().replace("ё", "е")).strip()


def read_table() -> list[dict]:
    if not TABLE.exists():
        return []
    with TABLE.open(encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != FIELDS:
            fail([f"{TABLE.name}: колонки должны быть {','.join(FIELDS)}"])
        return list(reader)


def write_table(rows: list[dict]) -> None:
    rows.sort(key=lambda r: (TYPES.index(r["type"]) if r["type"] in TYPES else 99, normalized(r["name"]), r["id"]))
    with TABLE.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def validate(rows: list[dict]) -> list[str]:
    errors = []
    ids = set()
    for n, r in enumerate(rows, start=2):
        where = f"{TABLE.name}:{n} «{r.get('name', '')}»"
        try:
            if str(uuid.UUID(r["id"])) != r["id"]:
                raise ValueError
        except ValueError:
            errors.append(f"{where}: id — UUID в нижнем регистре")
        if r["id"] in ids:
            errors.append(f"{where}: id повторяется")
        ids.add(r["id"])
        if r["type"] not in TYPES:
            errors.append(f"{where}: тип «{r['type']}» — один из {', '.join(TYPES)}")
        if not 1 <= len(r["name"].strip()) <= 80 or r["name"] != r["name"].strip():
            errors.append(f"{where}: название — 1–80 символов без пробелов по краям")
        if len(r["description"]) > 2000:
            errors.append(f"{where}: описание длиннее 2000 символов")
        try:
            point = (float(r["lat"]), float(r["lon"]))
            if not (LAT[0] <= point[0] <= LAT[1] and LON[0] <= point[1] <= LON[1]):
                errors.append(f"{where}: точка {point} вне Алматинской области и Жетісу")
            if r["access_lat"] or r["access_lon"]:
                access = (float(r["access_lat"]), float(r["access_lon"]))
                if distance_m(point, access) > ACCESS_M:
                    errors.append(f"{where}: точка подъезда дальше {ACCESS_M // 1000} км от места")
        except ValueError:
            errors.append(f"{where}: координаты — числа (широта, долгота)")
    if errors:
        return errors
    for i, a in enumerate(rows):
        for b in rows[i + 1:]:
            if (a["type"] == b["type"] and normalized(a["name"]) == normalized(b["name"])
                    and distance_m((float(a["lat"]), float(a["lon"])), (float(b["lat"]), float(b["lon"]))) < DUPLICATE_M):
                errors.append(f"«{a['name']}» ({a['type']}) повторяется: {a['id']} и {b['id']}")
    return errors


def read_info() -> list[dict]:
    if not INFO.exists():
        return []
    with INFO.open(encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != INFO_FIELDS:
            fail([f"{INFO.name}: колонки должны быть {','.join(INFO_FIELDS)}"])
        return list(reader)


def split(value: str) -> list[str]:
    """Несколько значений в ячейке — через «;»."""
    return [v.strip() for v in value.split(";") if v.strip()]


def validate_info(rows: list[dict], places: list[dict]) -> list[str]:
    errors = []
    names = {p["id"]: p["name"] for p in places}
    seen = set()
    allowed = {"species": SPECIES, "access": ACCESS, "methods": METHODS, "amenities": AMENITIES}
    for n, r in enumerate(rows, start=2):
        where = f"{INFO.name}:{n} «{r.get('name', '')}»"
        if r["id"] not in names:
            errors.append(f"{where}: такого id нет в {TABLE.name}")
            continue
        if r["id"] in seen:
            errors.append(f"{where}: id повторяется")
        seen.add(r["id"])
        if r["name"] != names[r["id"]]:
            errors.append(f"{where}: название не совпадает с {TABLE.name} («{names[r['id']]}»)")
        for field, values in allowed.items():
            bad = [v for v in split(r[field]) if v not in values]
            if bad:
                errors.append(f"{where}: {field} — {', '.join(bad)} нет среди {', '.join(values)}")
            if len(set(split(r[field]))) != len(split(r[field])):
                errors.append(f"{where}: {field} — значение повторяется")
        if r["fee"] and r["fee"] not in FEES:
            errors.append(f"{where}: fee — free или paid")
        if r["price_kzt"] or r["price_unit"]:
            if r["fee"] != "paid":
                errors.append(f"{where}: цена — только у платного места (fee=paid)")
            if not r["price_kzt"].isdigit() or r["price_unit"] not in PRICE_UNITS:
                errors.append(f"{where}: price_kzt — целое число тенге, price_unit — {', '.join(PRICE_UNITS)}")
        if r["signal"] and r["signal"] not in SIGNALS:
            errors.append(f"{where}: signal — {', '.join(SIGNALS)}")
        if any(not m.isdigit() or not 1 <= int(m) <= 12 for m in split(r["months"])):
            errors.append(f"{where}: months — номера месяцев 1–12 через «;»")
        # Те же пределы, что у базы (private.place_attributes_valid) и PlaceInfo в приложении.
        if len(r["features"]) > 1000 or len(r["contact"]) > 100:
            errors.append(f"{where}: features — до 1000 символов, contact — до 100")
        if not r["sources"].strip():
            errors.append(f"{where}: sources — откуда сведения (ссылки через «;»)")
    return errors


def info_value(r: dict) -> dict:
    """Сведения из place_info.csv в виде attributes (ключи — как в PlaceInfo.swift)."""
    value = {}
    for field in ("species", "access", "methods", "amenities"):
        if split(r[field]):
            value[field] = split(r[field])
    for field in ("fee", "price_unit", "contact", "signal", "features"):
        if r[field].strip():
            value[field] = r[field].strip()
    if r["price_kzt"].strip():
        value["price_kzt"] = int(r["price_kzt"])
    if split(r["months"]):
        value["months"] = sorted({int(m) for m in split(r["months"])})
    return value


def table_hash() -> str:
    """Отпечаток places.csv и place_info.csv: миграцию надо пересобрать, если изменился любой."""
    if not TABLE.exists():
        return ""
    digest = hashlib.sha256(TABLE.read_bytes())
    if INFO.exists():
        digest.update(INFO.read_bytes())
    return digest.hexdigest()


def latest_migration() -> Path | None:
    found = sorted(MIGRATIONS.glob(f"*{SUFFIX}"))
    return found[-1] if found else None


def check() -> None:
    rows = read_table()
    errors = validate(rows) + validate_info(read_info(), rows)
    last = latest_migration()
    if rows and last is None:
        errors.append("нет миграции с местами редакции — выполните `places.py migration`")
    elif last is not None and f"places.csv sha256: {table_hash()}" not in last.read_text(encoding="utf-8"):
        errors.append(f"{TABLE.name} изменилась после {last.name} — выполните `places.py migration`")
    if errors:
        fail(errors)
    counts = {t: sum(1 for r in rows if r["type"] == t) for t in TYPES}
    print(f"{TABLE.name}: {len(rows)} мест — " + ", ".join(f"{t} {c}" for t, c in counts.items() if c))
    # Сводка для плана наполнения (docs/05-release/content.md, «Метрики»).
    with_photo = set()
    if PHOTOS.exists():
        with PHOTOS.open(encoding="utf-8", newline="") as f:
            with_photo = {r["place_id"] for r in csv.DictReader(f)}
    described = sum(1 for r in rows if len(r["description"]) >= 150)
    print(f"наполнение: описание от 150 знаков — {described}, сведения ({INFO.name}) — {len(read_info())}, "
          f"фото — {sum(1 for r in rows if r['id'] in with_photo)} мест")


# Импорт ----------------------------------------------------------------------------------------

def folder_type(name: str) -> str | None:
    name = name.lower()
    return next((t for word, t in FOLDER_TYPES if word in name), None)


def strip_html(text: str) -> str:
    text = re.sub(r"<br\s*/?>", "\n", text or "", flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    return " ".join(text.replace("&nbsp;", " ").split())


def read_kml(path: Path, default_type: str | None) -> list[dict]:
    if path.suffix.lower() == ".kmz":
        with zipfile.ZipFile(path) as z:
            data = z.read(next(n for n in z.namelist() if n.lower().endswith(".kml")))
    else:
        data = path.read_bytes()
    root = ElementTree.fromstring(data)
    ns = {"k": root.tag.split("}")[0].strip("{")} if root.tag.startswith("{") else {"k": ""}
    q = (lambda tag: f"k:{tag}") if ns["k"] else (lambda tag: tag)
    found = []

    def walk(node, folder: str | None) -> None:
        for child in node:
            tag = child.tag.split("}")[-1]
            if tag in ("Folder", "Document"):
                title = child.findtext(q("name"), default="", namespaces=ns)
                walk(child, folder_type(title) or folder)
            elif tag == "Placemark":
                coords = child.findtext(f".//{q('Point')}/{q('coordinates')}", default="", namespaces=ns).strip()
                if not coords:
                    continue  # линии и контуры не переносим
                lon, lat = (float(x) for x in coords.split(",")[:2])
                found.append({
                    "type": folder or default_type or "",
                    "name": " ".join(child.findtext(q("name"), default="", namespaces=ns).split()),
                    "lat": lat, "lon": lon,
                    "description": strip_html(child.findtext(q("description"), default="", namespaces=ns)),
                    "source": "",
                })

    walk(root, None)
    return found


def read_csv(path: Path, default_type: str | None) -> list[dict]:
    with path.open(encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    found = []
    for r in rows:
        # osm_candidates.csv: только отобранные.
        if "include" in r and r["include"].strip().lower() not in ("yes", "да", "1", "+"):
            continue
        found.append({
            "id": (r.get("id") or "").strip(),
            "type": (r.get("type") or default_type or "").strip(),
            "name": " ".join((r.get("name") or "").split()),
            "lat": float(r["lat"]), "lon": float(r["lon"]),
            "access_lat": (r.get("access_lat") or "").strip(), "access_lon": (r.get("access_lon") or "").strip(),
            "description": " ".join((r.get("description") or "").split()),
            "source": (r.get("source") or "").strip(),
        })
    return found


def import_file(path: Path, default_type: str | None) -> None:
    if path.suffix.lower() in (".kml", ".kmz"):
        incoming = read_kml(path, default_type)
    else:
        incoming = read_csv(path, default_type)
    rows = read_table()
    added, skipped, untyped = 0, 0, []
    for place in incoming:
        if place["type"] not in TYPES:
            untyped.append(place["name"])
            continue
        name = typographic(place["name"])[:80].strip()
        if name[:1].islower():
            name = name[:1].upper() + name[1:]
        point = (place["lat"], place["lon"])
        duplicate = next((
            r for r in rows
            if (place.get("id") and r["id"] == place["id"])
            or (place["source"] and r["source"] == place["source"])
            or (r["type"] == place["type"] and normalized(r["name"]) == normalized(name)
                and distance_m(point, (float(r["lat"]), float(r["lon"]))) < DUPLICATE_M)
        ), None)
        if duplicate:
            skipped += 1
            continue
        rows.append({
            "id": place.get("id") or str(uuid.uuid4()),
            "type": place["type"],
            "name": name,
            "lat": f"{place['lat']:.6f}",
            "lon": f"{place['lon']:.6f}",
            "access_lat": place.get("access_lat", ""),
            "access_lon": place.get("access_lon", ""),
            "description": place["description"][:2000],
            "source": place["source"] or f"import:{path.name}",
        })
        added += 1
    errors = validate(rows)
    if errors:
        fail(errors)
    write_table(rows)
    print(f"добавлено {added}, уже есть {skipped}, всего {len(rows)}")
    if untyped:
        print(f"без типа (укажите --type или слой с понятным названием): {len(untyped)} — "
              + ", ".join(untyped[:10]), file=sys.stderr)


# Миграция --------------------------------------------------------------------------------------

def literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def point(lat: str, lon: str) -> str:
    return f"'SRID=4326;POINT({float(lon):.6f} {float(lat):.6f})'"


def attributes(source: str, info: dict | None = None) -> str:
    if source.startswith("osm:"):
        value = {"source": "osm", "osm": source[4:]}
    else:
        value = {"source": "editorial"}
    value.update(info_value(info) if info else {})
    return literal(json.dumps(value, ensure_ascii=False, separators=(", ", ": ")))


def migration() -> None:
    rows = read_table()
    infos = read_info()
    errors = validate(rows) + validate_info(infos, rows)
    if errors:
        fail(errors)
    info_by_id = {r["id"]: r for r in infos}
    last = latest_migration()
    digest = table_hash()
    if last is not None and f"places.csv sha256: {digest}" in last.read_text(encoding="utf-8"):
        print(f"{TABLE.name} не менялась после {last.name}")
        return

    newest = sorted(MIGRATIONS.glob("*.sql"))[-1].name[:14]
    stamp = max(
        datetime.strptime(newest, "%Y%m%d%H%M%S").replace(hour=10, minute=0, second=0) + timedelta(days=1),
        datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0),
    ).strftime("%Y%m%d%H%M%S")
    out = io.StringIO()
    out.write(
        "-- Места редакции (@dalada) из supabase/data/places/places.csv — собрано places.py, руками не править.\n"
        f"-- places.csv sha256: {digest}\n"
        "-- Места с source «osm:…» в таблице — © участники OpenStreetMap, лицензия ODbL.\n"
        "--\n"
        "-- Новые места добавляются, изменённые обновляются, убранные из таблицы скрываются (deleted_at).\n"
        "-- Статус модерации и скрытие в Studio не трогаются.\n\n"
    )
    if rows:
        out.write(
            "insert into public.places as p (\n"
            "  id, owner_id, type, name, description, geom, access_point, attributes, visibility, approximate, status\n"
            ")\nvalues\n"
        )
        values = []
        for r in rows:
            access = point(r["access_lat"], r["access_lon"]) if r["access_lat"] else "null"
            description = literal(r["description"]) if r["description"] else "null"
            values.append(
                f"  ({literal(r['id'])}, private.editorial_id(), {literal(r['type'])}, {literal(r['name'])}, "
                f"{description}, {point(r['lat'], r['lon'])}, {access}, {attributes(r['source'], info_by_id.get(r['id']))}, "
                "'public', false, 'published')"
            )
        out.write(",\n".join(values))
        out.write(
            "\non conflict (id) do update\n"
            "   set type = excluded.type,\n"
            "       name = excluded.name,\n"
            "       description = excluded.description,\n"
            "       geom = excluded.geom,\n"
            "       access_point = excluded.access_point,\n"
            "       attributes = excluded.attributes\n"
            " where p.owner_id = private.editorial_id();\n\n"
        )
    ids = ", ".join(literal(r["id"]) for r in rows)
    out.write(
        "update public.places\n"
        "   set deleted_at = now()\n"
        " where owner_id = private.editorial_id()\n"
        "   and deleted_at is null"
        + (f"\n   and id <> all (array[{ids}]::uuid[]);\n" if rows else ";\n")
    )
    path = MIGRATIONS / f"{stamp}{SUFFIX}"
    path.write_text(out.getvalue(), encoding="utf-8")
    print(f"записано {path.relative_to(HERE.parent.parent.parent)}: {len(rows)} мест")


def main(argv: list[str]) -> None:
    if len(argv) >= 1 and argv[0] == "check":
        check()
    elif len(argv) >= 2 and argv[0] == "import":
        default_type = None
        if "--type" in argv:
            default_type = argv[argv.index("--type") + 1]
            if default_type not in TYPES:
                fail([f"--type — один из {', '.join(TYPES)}"])
        import_file(Path(argv[1]), default_type)
    elif len(argv) >= 1 and argv[0] == "migration":
        migration()
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv[1:])
