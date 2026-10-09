#!/usr/bin/env bash
# Скачивает из OpenStreetMap границы нацпарков и заповедника и государственные границы (Казахстан,
# Китай, Кыргызстан) для слоёв карты «Нацпарки» и «Погранзона» (M16) и загружает их в схему osm_src
# локальной базы. Дальше — areas.sql и export_areas.py.
# Данные OSM © участники OpenStreetMap, лицензия ODbL.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .osm
UA="Dalada-dev/0.1 (+https://github.com/dkicekeeper/Dalada)"
DB=${DB:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}

# Nominatim: не чаще раза в секунду.
fetch() {
  curl -sS -m 120 -G -A "$UA" "https://nominatim.openstreetmap.org/lookup" \
    --data-urlencode "osm_ids=$1" --data-urlencode "format=json" \
    --data-urlencode "polygon_geojson=1" --data-urlencode "polygon_threshold=$2" -o ".osm/$3"
  sleep 1.2
}

fetch R21255164 0.0005 ile_alatau.json      # Иле-Алатауский национальный парк
fetch R5935486 0.0005 altyn_emel.json       # Алтын-Эмель
fetch W1185318988 0.0005 charyn.json        # Шарын (Чарынский)
fetch R17950167 0.0005 kolsai.json          # Көлсай көлдері (Кольсайские озёра)
fetch W978788009 0.0005 zhongar_alatau.json # Жонгар-Алатауский
fetch R20688891 0.0005 almaty_reserve.json  # Алматинский заповедник
# M34: нацпарки и заповедники остального Казахстана.
fetch R6311971 0.0005 bayanaul.json         # Баянаульский
fetch W978784431 0.0005 burabay.json        # Бурабай
fetch R19815661 0.0005 kokshetau.json       # Кокшетау
fetch R13158745 0.0005 tarbagatai.json      # Тарбагатай
fetch R13158670 0.0005 karkaraly.json       # Каркаралинский
fetch R13158691 0.0005 katon_karagay.json   # Катон-Карагайский
fetch R21196302 0.0005 buiratau.json        # Буйратау
fetch R13549455 0.0005 sairam_ugam.json     # Сайрам-Угамский
fetch R3388788 0.0005 aksu_zhabagly.json    # Аксу-Жабаглинский заповедник
fetch R6056653 0.0005 korgalzhyn.json       # Коргалжынский заповедник
fetch R2676852 0.0005 naurzum.json          # Наурзумский заповедник
fetch W493654755 0.0005 ustyurt.json        # Устюртский заповедник
fetch R214665 0.002 kz.json                 # Казахстан
fetch R270056 0.002 cn.json                 # Китай
fetch R178009 0.002 kg.json                 # Кыргызстан

python3 - <<'PY'
import json
files = ["ile_alatau", "altyn_emel", "charyn", "kolsai", "zhongar_alatau", "almaty_reserve",
         "bayanaul", "burabay", "kokshetau", "tarbagatai", "karkaraly", "katon_karagay", "buiratau",
         "sairam_ugam", "aksu_zhabagly", "korgalzhyn", "naurzum", "ustyurt", "kz", "cn", "kg"]
with open(".osm/load.sql", "w") as out:
    out.write("create schema if not exists osm_src;\n")
    out.write("drop table if exists osm_src.areas_raw;\n")
    out.write("create table osm_src.areas_raw (key text primary key, osm_id text, geom extensions.geometry);\n")
    for key in files:
        rows = json.load(open(f".osm/{key}.json"))
        assert len(rows) == 1, (key, len(rows))
        r = rows[0]
        osm_id = r["osm_type"][0].upper() + str(r["osm_id"])
        geojson = json.dumps(r["geojson"]).replace("'", "''")
        out.write(f"insert into osm_src.areas_raw values ('{key}', '{osm_id}', "
                  f"extensions.st_setsrid(extensions.st_geomfromgeojson('{geojson}'), 4326));\n")
PY
psql "$DB" -q -f .osm/load.sql
psql "$DB" -q -f areas.sql
