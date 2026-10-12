#!/usr/bin/env python3
"""Проверка дизайна: в Swift-коде Dalada нет «сырых» значений.

Цвета, шрифты, отступы, скругления и анимации берутся из токенов DesignKit (AppColors,
AppColors.Palette, AppTypography, AppSpacing, AppRadius, AppAnimation) и его компонентов.
Скрипт находит такие значения-литералы в ios/Dalada, ios/DaladaWidgets и
ios/Packages/DaladaKit/Sources и сравнивает их число по файлам и правилам с
scripts/design-lint-baseline.json:

- больше, чем в базе: новое сырое значение, CI падает;
- меньше: код стал чище, базу опускает --update-baseline;
- в файле, которого нет в базе, сырых значений быть не должно.

Запуск:
    python3 scripts/design_lint.py                    # проверка (CI)
    python3 scripts/design_lint.py --report           # все находки по правилам
    python3 scripts/design_lint.py --update-baseline  # записать текущие числа в базу

Оправданное исключение — `// design-lint:ignore <причина>` в той же строке. Цвета из данных
(цвет из модели, выбор пользователя) — не значения дизайна: проверяются только литералы.
Порт scripts/design_lint.py из Tenra: правила те же.

В базе только два файла, оба намеренно:
- ShareCardViews — картинка для Stories на холсте фиксированного размера: шрифты и отступы в
  точках холста, не Dynamic Type, цвета — фирменный градиент картинки;
- TripLiveActivity — Live Activity на экране блокировки и в Dynamic Island: системные стили
  текста, как советует HIG.
"""

import collections
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
# Код интерфейса: приложение, виджеты и модули пакета (тесты и скриншот-тесты — нет).
SOURCES = ("ios/Dalada", "ios/DaladaWidgets", "ios/Packages/DaladaKit/Sources")
BASELINE = os.path.join(ROOT, "scripts", "design-lint-baseline.json")

EXCLUDED_DIRS = ()
EXCLUDED_SUFFIXES = ("Previews.swift",)

IGNORE_MARK = "design-lint:ignore"

RULES = {
    # Literal colours: Color(red: 0.2, …), Color(hex: "#…"), UIColor(white: 0.9, …), #colorLiteral.
    # Use AppColors / CategoryColors. A colour built from data (Color(hex: category.colorHex)) passes.
    "raw-color": re.compile(
        r'\b(?:Color|UIColor)\(\s*(?:red|green|blue|white|hue)\s*:\s*[\d.]'
        r'|\b(?:Color|UIColor)\(\s*hex\s*:\s*"'
        r'|#colorLiteral'
    ),
    # System palette colours (.red, Color.blue, …) in styling modifiers. Use AppColors
    # (accent, destructive, success, warning, income, expense, …).
    "system-color": re.compile(
        r'(?:foregroundStyle|foregroundColor|tint|background|fill|stroke|strokeBorder)'
        r'\(\s*(?:Color)?\.(?:red|blue|green|orange|yellow|purple|pink|gray|grey|mint|teal|cyan|indigo|brown)\b'
    ),
    # System text styles and literal font sizes. Use AppTypography (Inter, Dynamic Type).
    # `.font(.system(size: AppIconSize.md))` sizes an SF Symbol with a token and passes.
    "system-font": re.compile(
        r'\.font\(\s*(?:Font)?\.(?:system\(\s*size:\s*[\d.]|largeTitle\b|title\b|title2\b|title3\b'
        r'|headline\b|subheadline\b|body\b|callout\b|footnote\b|caption\b|caption2\b)'
        r'|\bFont\.custom\('
    ),
    # Literal padding. Use AppSpacing.
    "raw-padding": re.compile(r'\.padding\(\s*(?:\.[a-zA-Z]+\s*,\s*|\[[^\]]*\]\s*,\s*)?[1-9]\d*(?:\.\d+)?\s*\)'),
    # Literal stack spacing (0 is allowed). Use AppSpacing.
    "raw-spacing": re.compile(r'\bspacing:\s*[1-9]\d*(?:\.\d+)?\b'),
    # Literal corner radius. Use AppRadius.
    "raw-radius": re.compile(r'\bcornerRadius:\s*[1-9]\d*(?:\.\d+)?\b|\.cornerRadius\(\s*[1-9]'),
    # Hand-tuned curves. Use AppAnimation.
    "raw-animation": re.compile(
        r'\.(?:easeIn|easeOut|easeInOut|linear)\(\s*duration:\s*[\d.]'
        r'|\.spring\(\s*(?:response|duration|bounce)\s*:'
        r'|\.interpolatingSpring\('
    ),
}


def swift_files():
    for source in SOURCES:
        for dirpath, dirs, files in os.walk(os.path.join(ROOT, source)):
            dirs[:] = sorted(d for d in dirs if d != ".build")
            for name in sorted(files):
                if not name.endswith(".swift"):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
                if (EXCLUDED_DIRS and rel.startswith(EXCLUDED_DIRS)) or rel.endswith(EXCLUDED_SUFFIXES):
                    continue
                yield rel, path


def scan():
    """{file: {rule: [(line, text), …]}}"""
    hits = collections.defaultdict(lambda: collections.defaultdict(list))
    for rel, path in swift_files():
        with open(path, encoding="utf-8", errors="replace") as source:
            in_preview = False
            for number, line in enumerate(source, 1):
                stripped = line.strip()
                # #Preview blocks are not product UI; they end at the next top-level "}".
                if stripped.startswith("#Preview"):
                    in_preview = True
                if in_preview:
                    if line.startswith("}"):
                        in_preview = False
                    continue
                if stripped.startswith("//") or IGNORE_MARK in line:
                    continue
                for rule, pattern in RULES.items():
                    for _ in pattern.finditer(line):
                        hits[rel][rule].append((number, stripped))
    return hits


def counts(hits):
    return {rel: {rule: len(lines) for rule, lines in sorted(rules.items())}
            for rel, rules in sorted(hits.items())}


def main(argv):
    hits = scan()
    current = counts(hits)

    if "--update-baseline" in argv:
        with open(BASELINE, "w", encoding="utf-8") as out:
            json.dump(current, out, indent=2, sort_keys=True)
            out.write("\n")
        total = sum(sum(rules.values()) for rules in current.values())
        print(f"База записана: сырых значений {total} в {len(current)} файлах.")
        return 0

    if "--report" in argv:
        by_rule = collections.defaultdict(list)
        for rel, rules in sorted(hits.items()):
            for rule, lines in rules.items():
                by_rule[rule].extend(f"{rel}:{n}: {text}" for n, text in lines)
        for rule in RULES:
            print(f"\n{rule} ({len(by_rule[rule])})")
            for entry in by_rule[rule]:
                print(f"  {entry}")
        return 0

    try:
        with open(BASELINE, encoding="utf-8") as source:
            baseline = json.load(source)
    except FileNotFoundError:
        baseline = {}

    failures = 0
    improved = []
    for rel, rules in current.items():
        for rule, count in rules.items():
            allowed = baseline.get(rel, {}).get(rule, 0)
            if count > allowed:
                failures += count - allowed
                for number, text in hits[rel][rule]:
                    print(f"::error file={rel},line={number},title=design-lint {rule}::"
                          f"сырых значений: {count}, база разрешает {allowed}: {text}")
            elif count < allowed:
                improved.append(f"{rel} {rule}: {allowed} → {count}")
    for rel, rules in baseline.items():
        for rule, allowed in rules.items():
            if rel not in current or rule not in current[rel]:
                improved.append(f"{rel} {rule}: {allowed} → 0")

    total = sum(sum(rules.values()) for rules in current.values())
    print(f"design-lint: сырых значений {total} в {len(current)} файлах (в базе "
          f"{sum(sum(r.values()) for r in baseline.values())}).")
    if improved:
        print("Меньше, чем в базе (закрепить: --update-baseline):")
        for entry in improved:
            print(f"  {entry}")
    if failures:
        print(f"\nНовых сырых значений: {failures}. Возьми токены DesignKit (AppColors, AppColors.Palette, "
              "AppTypography, AppSpacing, AppRadius, AppAnimation) или отметь оправданное исключение "
              "`// design-lint:ignore <причина>`.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
