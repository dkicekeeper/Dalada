#!/usr/bin/env python3
"""Скриншоты для App Store: снимок экрана в рамке с подписью (docs/05-release/README.md#скриншоты).

    python3 appstore/screenshots/frame.py <снимки> <готовые> --font Inter.ttf [--language ru]

<снимки>/<язык>/<экран>.png — сырые снимки симулятора (UI-тест DaladaScreenshots); экраны и подписи —
captions.json рядом со скриптом. Результат — <готовые>/<язык>/<экран>.png, 1320 × 2868 (iPhone 6,9″).
Если на экране фото по лицензии CC BY, в captions.json у него есть «credit» — подпись внизу.
"""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

WIDTH, HEIGHT = 1320, 2868
TOP, BOTTOM = (11, 54, 70), (35, 127, 120)  # цвета фона иконки
SIDE = 80
SCREEN_WIDTH = 1080
RADIUS = 72


def font(path: str, size: int, weight: int) -> ImageFont.FreeTypeFont:
    result = ImageFont.truetype(path, size)
    try:
        axes = result.get_variation_axes()
        result.set_variation_by_axes([size if "ptical" in str(a.get("name", "")) else weight for a in axes])
    except (OSError, AttributeError):
        pass  # не вариативный шрифт
    return result


def gradient() -> Image.Image:
    column = Image.new("RGB", (1, HEIGHT))
    for y in range(HEIGHT):
        t = min(y / (HEIGHT * 0.75), 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return column.resize((WIDTH, HEIGHT))


def wrap(draw: ImageDraw.ImageDraw, text: str, typeface: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines, line = [], ""
    for word in text.split():
        candidate = f"{line} {word}".strip()
        if draw.textlength(candidate, font=typeface) <= width or not line:
            line = candidate
        else:
            lines.append(line)
            line = word
    return lines + [line] if line else lines


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *image.size), radius=radius, fill=255)
    image = image.convert("RGBA")
    image.putalpha(mask)
    return image


def frame(shot: Path, caption: str, credit: str | None, font_path: str) -> Image.Image:
    canvas = gradient().convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    title = font(font_path, 92, 760)
    lines = wrap(draw, caption, title, WIDTH - 2 * SIDE)
    y = 190
    for line in lines:
        draw.text((WIDTH / 2, y), line, font=title, fill="white", anchor="ma")
        y += 112
    top = y + 90

    screen = Image.open(shot).convert("RGB")
    screen = screen.resize((SCREEN_WIDTH, round(screen.height * SCREEN_WIDTH / screen.width)), Image.LANCZOS)
    screen = rounded(screen, RADIUS)
    left = (WIDTH - SCREEN_WIDTH) // 2

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (left, top + 24, left + SCREEN_WIDTH, top + 24 + screen.height), radius=RADIUS, fill=(0, 0, 0, 110))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(40)))
    canvas.alpha_composite(screen, (left, top))
    ImageDraw.Draw(canvas).rounded_rectangle(
        (left, top, left + SCREEN_WIDTH, top + screen.height), radius=RADIUS, outline=(255, 255, 255, 60), width=4)

    if credit:
        small = font(font_path, 30, 500)
        draw = ImageDraw.Draw(canvas)
        width = draw.textlength(credit, font=small)
        box = (WIDTH / 2 - width / 2 - 28, HEIGHT - 120, WIDTH / 2 + width / 2 + 28, HEIGHT - 60)
        overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(overlay).rounded_rectangle(box, radius=30, fill=(0, 0, 0, 150))
        canvas = Image.alpha_composite(canvas, overlay)
        ImageDraw.Draw(canvas).text((WIDTH / 2, HEIGHT - 90), credit, font=small, fill=(255, 255, 255, 230), anchor="mm")

    return canvas.convert("RGB")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("raw", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--font", required=True, help="Inter (вариативный TTF из DesignKit)")
    parser.add_argument("--language", action="append", help="ru, en (по умолчанию — все папки в <снимки>)")
    args = parser.parse_args()

    captions = json.loads((Path(__file__).with_name("captions.json")).read_text(encoding="utf-8"))
    languages = args.language or sorted(p.name for p in args.raw.iterdir() if p.is_dir())
    for language in languages:
        (args.out / language).mkdir(parents=True, exist_ok=True)
        for screen, texts in captions.items():
            shot = args.raw / language / f"{screen}.png"
            if not shot.exists():
                print(f"{language}/{screen}: снимка нет — пропускаю")
                continue
            credit = (texts.get("credit") or {}).get(language)
            image = frame(shot, texts[language], credit, args.font)
            image.save(args.out / language / f"{screen}.png", optimize=True)
            print(f"{language}/{screen}: готово")


if __name__ == "__main__":
    main()
