#!/usr/bin/env python3
"""Рельеф для своей карты из Copernicus DEM GLO-30 (высоты с шагом ~30 м).

    python3 map/relief.py areas                  — горные районы построчно: запад юг восток север
    python3 map/relief.py download DIR [W S E N]  — листы DEM 1°×1° (с запасом) → DIR/*.tif
    python3 map/relief.py terrain DEM OUT [W S E N] — тайлы высот terrarium OUT/{z}/{x}/{y}.png
                                            (масштабы — config.json → relief.terrain_zooms)
Без W S E N — все горные районы (relief.areas в config.json). Workflow Map tiles обрабатывает
районы по одному: скачал листы района → горизонтали и тайлы высот → удалил листы.

Горизонтали строит workflow Map tiles (gdal_contour + tippecanoe), отмывку рисует MapLibre по
тайлам высот (слой hillshade). Нужны GDAL с Python, numpy и Pillow.

Лицензия данных: © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under
COPERNICUS by the European Union and ESA; all rights reserved — указываем в атрибуции стиля.
"""

import io
import json
import math
import sys
import urllib.error
import urllib.request
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG = json.loads((HERE / "config.json").read_text())
DEM_URL = "https://copernicus-dem-30m.s3.amazonaws.com/{name}/{name}.tif"
TERRAIN_ZOOMS = range(CONFIG["relief"]["terrain_zooms"][0], CONFIG["relief"]["terrain_zooms"][1] + 1)
TILE = 256
EARTH = 6378137.0


def areas() -> list[list[float]]:
    """Горные районы с рельефом (relief.areas: запад, юг, восток, север); без списка — весь bounds.
    Высоты всей страны не помещаются на диск сборщика, а в степи горизонтали не нужны."""
    return CONFIG["relief"].get("areas") or [CONFIG["bounds"]]


def dem_names(selected: list[list[float]] | None = None) -> list[str]:
    """Листы, покрывающие районы, и ещё по градусу вокруг: тайлы мелких масштабов выходят за границы
    района, и без высот там был бы обрыв до нуля."""
    names = []
    for west, south, east, north in selected or areas():
        for lat in range(math.floor(south) - 1, math.floor(north) + 2):
            for lon in range(math.floor(west) - 1, math.floor(east) + 2):
                ns = f"N{lat:02d}" if lat >= 0 else f"S{-lat:02d}"
                ew = f"E{lon:03d}" if lon >= 0 else f"W{-lon:03d}"
                name = f"Copernicus_DSM_COG_10_{ns}_00_{ew}_00_DEM"
                if name not in names:
                    names.append(name)
    return names


def fetch(name: str, out: Path) -> str:
    path = out / f"{name}.tif"
    if path.exists():
        return "есть"
    for attempt in range(3):
        try:
            with urllib.request.urlopen(DEM_URL.format(name=name), timeout=120) as response:
                path.write_bytes(response.read())
            return "скачан"
        except urllib.error.HTTPError as error:
            if error.code in (403, 404):
                return "нет листа"  # море или лист не выпущен
            if attempt == 2:
                raise
        except OSError:
            if attempt == 2:
                raise
    return "?"


def download(out: Path, selected: list[list[float]] | None = None) -> None:
    out.mkdir(parents=True, exist_ok=True)
    names = dem_names(selected)
    with ThreadPoolExecutor(8) as pool:
        results = list(pool.map(lambda name: fetch(name, out), names))
    for state in sorted(set(results)):
        print(f"{state}: {results.count(state)}")
    if results.count("скачан") + results.count("есть") == 0:
        sys.exit("Не скачано ни одного листа DEM")


def tile_columns(zoom: int, selected: list[list[float]] | None = None) -> dict[int, list[int]]:
    """Тайлы масштаба, покрывающие горные районы: столбец x → строки y."""

    def tile(lon: float, lat: float) -> tuple[int, int]:
        n = 1 << zoom
        x = int((lon + 180) / 360 * n)
        y = int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n)
        return min(x, n - 1), min(y, n - 1)

    columns: dict[int, set[int]] = {}
    for west, south, east, north in selected or areas():
        x0, y0 = tile(west, north)
        x1, y1 = tile(east, south)
        for x in range(x0, x1 + 1):
            columns.setdefault(x, set()).update(range(y0, y1 + 1))
    return {x: sorted(ys) for x, ys in sorted(columns.items())}


def mercator_bounds(z: int, x: int, y: int) -> tuple[float, float, float, float]:
    size = 2 * math.pi * EARTH / (1 << z)
    minx = -math.pi * EARTH + x * size
    maxy = math.pi * EARTH - y * size
    return minx, maxy - size, minx + size, maxy


def render_column(job: tuple[str, str, int, int, list[int]]) -> tuple[int, int]:
    """Столбец тайлов одного масштаба (отдельный процесс). Возвращает число тайлов и байт."""
    import numpy as np
    from osgeo import gdal
    from PIL import Image

    gdal.UseExceptions()
    dem_path, out, z, x, ys = job
    dem = gdal.Open(dem_path)
    count, size = 0, 0
    for y in ys:
        warped = gdal.Warp(
            "", dem, format="MEM", outputBounds=mercator_bounds(z, x, y), width=TILE, height=TILE,
            dstSRS="EPSG:3857", resampleAlg="average",
        )
        heights = warped.GetRasterBand(1).ReadAsArray().astype(np.float64)
        # Terrarium: высота + 32768 в R·256 + G (+ B/256). Высоты — целые метры: тайл сжимается
        # в разы лучше, отмывке точнее не нужно.
        value = np.clip(np.round(heights) + 32768, 0, 65535).astype(np.uint32)
        rgb = np.dstack([value >> 8, value & 0xFF, np.zeros_like(value)]).astype(np.uint8)
        buffer = io.BytesIO()
        Image.fromarray(rgb, "RGB").save(buffer, "PNG", optimize=True)
        path = Path(out) / str(z) / str(x) / f"{y}.png"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(buffer.getvalue())
        count += 1
        size += buffer.tell()
    return count, size


def terrain(dem: Path, out: Path, selected: list[list[float]] | None = None) -> None:
    jobs = []
    for z in TERRAIN_ZOOMS:
        jobs += [(str(dem), str(out), z, x, ys) for x, ys in tile_columns(z, selected).items()]
    with ProcessPoolExecutor() as pool:
        results = list(pool.map(render_column, jobs))
    count = sum(c for c, _ in results)
    size = sum(s for _, s in results)
    print(f"Тайлы высот z{TERRAIN_ZOOMS.start}–{TERRAIN_ZOOMS.stop - 1}: {count}, {size / 1024 / 1024:.0f} МБ")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "areas":
        for area in areas():
            print(*area)
    elif len(sys.argv) in (3, 7) and sys.argv[1] == "download":
        download(Path(sys.argv[2]), [list(map(float, sys.argv[3:7]))] if len(sys.argv) == 7 else None)
    elif len(sys.argv) in (4, 8) and sys.argv[1] == "terrain":
        terrain(Path(sys.argv[2]), Path(sys.argv[3]), [list(map(float, sys.argv[4:8]))] if len(sys.argv) == 8 else None)
    else:
        sys.exit(__doc__)
