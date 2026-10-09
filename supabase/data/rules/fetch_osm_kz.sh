#!/usr/bin/env bash
# M34: геометрии для зон правил остальных бассейнов Казахстана (приказ № 78, главы 2 и 4–9) —
# области и районы, водохранилища, озёра и реки из OpenStreetMap — в таблицу osm_src.kz_raw
# локальной базы. Дальше — zones_kazakhstan.sql и export_zones.py с перечнем id.
# Нужны применённые миграции: границы Балхаш-Алакольских зон берутся из public.rule_zones.
# Данные OSM © участники OpenStreetMap, лицензия ODbL.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .osm
UA="Dalada-dev/0.1 (+https://github.com/dkicekeeper/Dalada)"
DB=${DB:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}
OVERPASS=https://maps.mail.ru/osm/tools/overpass/api/interpreter

# Nominatim: не чаще раза в секунду; до 50 объектов за запрос.
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

# Overpass отвечает 504, когда занят: повторяем.
overpass() {
  for attempt in 1 2 3 4 5 6; do
    if curl -sS -m 200 -A "$UA" --data-urlencode "data=$1" -o ".osm/$2" "$OVERPASS" \
       && head -c1 ".osm/$2" | grep -q '{'; then
      return
    fi
    sleep $((attempt * 10))
  done
  echo "Overpass не ответил: $2" >&2
  exit 1
}

# Области: Туркестанская, Кызылординская, Павлодарская, Восточно-Казахстанская, Абай, Астана,
# Акмолинская, Северо-Казахстанская.
fetch R215739,R215727,R215772,R215699,R14243026,R3087155,R215743,R215760 0.005 kz_oblasts1.json
# Карагандинская, Улытау, Костанайская, Актюбинская, Западно-Казахстанская, Атырауская, Жамбылская.
fetch R215776,R14312737,R1288730,R215683,R215441,R214834,R215722 0.005 kz_oblasts2.json
# Аркалык (городская администрация), Амангельдинский и Джангельдинский районы.
fetch R2068931,R2068895,R2067946 0.002 kz_districts.json
# Шардара, Малый Арал, Зайсан, Бухтарма, Усть-Каменогорское, Шульбинское и Тасоткельское
# водохранилища.
fetch R2860201,R8728779,R35913,R1204368,R2087409,R2083103,W38857985 0.0003 kz_waters.json
# Сырдарья, Арысь, Иртыш, Кара Ертис, Шу, Талас, Урал (Жайык).
fetch R1206456,R3388066,R2098340,R9394151,R10674492,R13034734,R214415 0.0003 kz_rivers.json
fetch R214665 0.005 kz_border.json
# Келес, Кигаш и Аса — линиями (way).
overpass '[out:json][timeout:180];area(id:3600214665)->.r;(
way["waterway"="river"]["name"~"^(Келес|Keles)$"](area.r);
rel(18788536);way(r);
way(22376756);
);out geom;' kz_ways.json

python3 - <<'PY'
import json

names = {
    "R215739": "turkestan", "R215727": "kyzylorda", "R215772": "pavlodar", "R215699": "vko",
    "R14243026": "abai", "R3087155": "astana", "R215743": "akmola", "R215760": "nko",
    "R215776": "karaganda", "R14312737": "ulytau", "R1288730": "kostanay", "R215683": "aktobe",
    "R215441": "wko", "R214834": "atyrau", "R215722": "zhambyl",
    "R2068931": "arkalyk", "R2068895": "amangeldy", "R2067946": "zhangeldy",
    "R2860201": "shardara", "R8728779": "small_aral", "R35913": "zaysan", "R1204368": "bukhtarma",
    "R2087409": "ust_kamenogorsk", "R2083103": "shulba", "W38857985": "tasotkel",
    "R1206456": "syrdarya", "R3388066": "arys", "R2098340": "irtysh", "R9394151": "kara_ertis",
    "R10674492": "shu", "R13034734": "talas", "R214415": "ural", "R214665": "kz",
    "W22376756": "asa",
}
rows = []
for f in ["kz_oblasts1", "kz_oblasts2", "kz_districts", "kz_waters", "kz_rivers", "kz_border"]:
    for r in json.load(open(f".osm/{f}.json")):
        osm_id = r["osm_type"][0].upper() + str(r["osm_id"])
        rows.append((names[osm_id], osm_id, r["geojson"]))
for e in json.load(open(".osm/kz_ways.json"))["elements"]:
    if e["type"] != "way":
        continue
    tags = e.get("tags", {})
    coords = [[p["lon"], p["lat"]] for p in e["geometry"]]
    osm_id = f"W{e['id']}"
    if osm_id in names:
        key = names[osm_id]
    elif "Келес" in tags.get("name", "") or "Keles" in tags.get("name", ""):
        key = "keles"
    else:
        key = "kigash"
    rows.append((key, osm_id, {"type": "LineString", "coordinates": coords}))
with open(".osm/load_kz.sql", "w") as out:
    out.write("create schema if not exists osm_src;\n")
    out.write("drop table if exists osm_src.kz_raw;\n")
    out.write("create table osm_src.kz_raw (key text, osm_id text, geom extensions.geometry);\n")
    for key, osm_id, geojson in rows:
        text = json.dumps(geojson).replace("'", "''")
        out.write(f"insert into osm_src.kz_raw values ('{key}', '{osm_id}', "
                  f"extensions.st_setsrid(extensions.st_geomfromgeojson('{text}'), 4326));\n")
PY
psql "$DB" -q -f .osm/load_kz.sql
psql "$DB" -q -f zones_kazakhstan.sql
