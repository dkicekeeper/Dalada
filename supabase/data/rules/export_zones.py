#!/usr/bin/env python3
"""Печатает SQL с геометриями зон из osm_src.zones — для новой миграции с обновлением границ.

Запуск: python3 export_zones.py [id …] > /tmp/zones_geometry.sql (нужен psql и локальная база);
с перечнем id — только эти зоны (для миграции, которая добавляет новые зоны).
"""
import os
import subprocess
import sys

DB = os.environ.get("DB", "postgresql://postgres:postgres@127.0.0.1:54322/postgres")
ids = sys.argv[1:]
where = " where id in (" + ", ".join(f"'{i}'" for i in ids) + ")" if ids else ""
rows = subprocess.run(
    ["psql", DB, "-At", "-F", "\t", "-c",
     f"select id, extensions.st_astext(geom, 5) from osm_src.zones{where} order by id"],
    check=True, capture_output=True, text=True,
).stdout.strip().splitlines()

for row in rows:
    zone_id, wkt = row.split("\t", 1)
    print(f"update public.rule_zones\n   set geom = extensions.st_geomfromtext('{wkt}', 4326)\n"
          f" where id = '{zone_id}';\n")
