#!/usr/bin/env bash
# Проверки дизайна из DesignKit той версии, на которой собрано приложение
# (scripts/designkit_lint.py DesignKit, с 8.9.0; раньше — свои design_lint.py и
# section_rows_lint.py, правила те же):
#   tokens        — сырые значения дизайна сверх scripts/design-lint-baseline.json, без
#                   .swipeActions и системного Form; исключение — // design-lint:ignore <причина>;
#   section-rows  — строки стеклянных секций отступают сами и ставят разделитель под текстом;
#                   исключение — // section-rows-lint:ignore <причина> на первой строке ряда.
#
#   scripts/designkit_lint.sh                              # всё (CI, задача «Design lint»)
#   scripts/designkit_lint.sh tokens --report              # все находки по правилам
#   scripts/designkit_lint.sh tokens --update-baseline     # стало меньше — опустить базу
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -nE 's#.*github.com/dkicekeeper/DesignKit", exact: "([0-9]+\.[0-9]+\.[0-9]+)".*#\1#p' \
  ios/Packages/DaladaKit/Package.swift)
if [ -z "$VERSION" ]; then
  echo "В ios/Packages/DaladaKit/Package.swift нет DesignKit вида exact: \"X.Y.Z\"" >&2
  exit 1
fi
SCRIPT="${TMPDIR:-/tmp}/designkit_lint-$VERSION.py"
if [ ! -s "$SCRIPT" ]; then
  curl -fsSL "https://raw.githubusercontent.com/dkicekeeper/DesignKit/$VERSION/scripts/designkit_lint.py" -o "$SCRIPT"
fi

CHECK="${1:-all}"
[ $# -gt 0 ] && shift
exec python3 "$SCRIPT" "$CHECK" \
  --source ios/Dalada --source ios/DaladaWidgets --source ios/Packages/DaladaKit/Sources "$@"
