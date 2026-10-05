#!/usr/bin/env python3
"""Печатает SQL со слоями карты (M16): тексты из areas.json, геометрии из osm_src.areas — для миграции.

Запуск: python3 export_areas.py > /tmp/map_areas.sql (нужны psql и локальная база после fetch_osm.sh).
Даты проверки — VERIFIED_ON; тарифы — в МРП, только со страниц тарифов самих парков.
"""
import json
import os
import subprocess
from pathlib import Path

DB = os.environ.get("DB", "postgresql://postgres:postgres@127.0.0.1:54322/postgres")
VERIFIED_ON = "2026-10-05"

areas = json.loads((Path(__file__).parent / "areas.json").read_text())
rows = subprocess.run(
    ["psql", DB, "-At", "-F", "\t", "-c", "select id, extensions.st_astext(geom, 5) from osm_src.areas order by id"],
    check=True, capture_output=True, text=True,
).stdout.strip().splitlines()
geometry = dict(row.split("\t", 1) for row in rows)


def text(value):
    return "null" if value is None else "'" + str(value).replace("'", "''") + "'"


def number(value):
    return "null" if value is None else str(value)


print("insert into public.map_areas (id, kind, name_ru, name_kk, name_en, info_ru, info_kk, info_en,")
print("  fee_person_mrp, fee_car_mrp, fee_fishing_mrp, website_url, tickets_url, source_title, source_url,")
print("  verified_on, sort_order, geom) values")
values = []
for area in areas:
    assert area["id"] in geometry, area["id"]
    fees = area.get("fees", {})
    values.append(
        "(" + ", ".join([
            text(area["id"]), text(area["kind"]), *map(text, area["name"]), *map(text, area["info"]),
            number(fees.get("person")), number(fees.get("car")), number(fees.get("fishing")),
            text(area["website_url"]), text(area["tickets_url"]), text(area["source_title"]),
            text(area["source_url"]), text(VERIFIED_ON), str(area["sort_order"]),
            f"extensions.st_geomfromtext('{geometry[area['id']]}', 4326)",
        ]) + ")"
    )
print(",\n".join(values) + ";")
