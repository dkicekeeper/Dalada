#!/usr/bin/env bash
# Промысловая мера по бассейнам (Правила рыболовства, приложение 1): мера своя у Павлодарской области
# и у Верхнетобольского и Каратомарского водохранилищ, поэтому им нужны свои зоны. Скрипт берёт из
# OpenStreetMap контуры Павлодарской области и двух водохранилищ, строит зоны в osm_src.zones
# локальной базы (zones_min_sizes.sql) и вырезает их из зон irtysh_east_waters и kostanay_waters.
# Нужны применённые миграции до …_min_sizes_kazakhstan.sql. Дальше — export_zones.py с перечнем id.
# Данные OSM © участники OpenStreetMap, лицензия ODbL.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .osm
UA="Dalada-dev/0.1 (+https://github.com/dkicekeeper/Dalada)"
DB=${DB:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}

# Nominatim: не чаще раза в секунду.
fetch() {
  for attempt in 1 2 3 4; do
    if curl -sS -m 180 -G -A "$UA" "https://nominatim.openstreetmap.org/lookup" \
         --data-urlencode "osm_ids=$1" --data-urlencode "format=json" \
         --data-urlencode "polygon_geojson=1" --data-urlencode "polygon_threshold=$2" -o ".osm/$3" \
       && python3 -c "import json, sys; assert json.load(open(sys.argv[1]))" ".osm/$3" 2>/dev/null; then
      sleep 1.2
      return
    fi
    sleep $((attempt * 5))
  done
  echo "Nominatim не ответил: $3" >&2
  exit 1
}

# Павлодарская область; Верхнетобольское и Каратомарское водохранилища.
fetch R215772 0.005 min_oblast.json
fetch R5477169,R5149278 0.0003 min_waters.json

python3 - <<'PY'
import json

names = {"R215772": "pavlodar", "R5477169": "verkhnetobolsk", "R5149278": "karatomar"}
with open(".osm/load_min.sql", "w") as out:
    out.write("create schema if not exists osm_src;\n")
    out.write("drop table if exists osm_src.min_raw;\n")
    out.write("create table osm_src.min_raw (key text, osm_id text, geom extensions.geometry);\n")
    for f in ["min_oblast", "min_waters"]:
        for r in json.load(open(f".osm/{f}.json")):
            osm_id = r["osm_type"][0].upper() + str(r["osm_id"])
            text = json.dumps(r["geojson"]).replace("'", "''")
            out.write(f"insert into osm_src.min_raw values ('{names[osm_id]}', '{osm_id}', "
                      f"extensions.st_setsrid(extensions.st_geomfromgeojson('{text}'), 4326));\n")
PY
psql "$DB" -q -f .osm/load_min.sql
psql "$DB" -q -f zones_min_sizes.sql
