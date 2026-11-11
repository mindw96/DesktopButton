#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
combined=$(mktemp /tmp/folder-in-bar-drag.XXXXXX.swift)
trap 'rm -f "$combined"' EXIT
python3 - "$root" "$combined" <<'PY'
from pathlib import Path
import sys
root, output = map(Path, sys.argv[1:])
source = (root / 'script/ui_smoke.swift').read_text()
marker = 'final class Smoke {'
assert source.count(marker) == 1, 'Shared UI helper boundary changed'
output.write_text(source.split(marker)[0] + (root / 'script/drag_smoke.swift').read_text())
PY
swift -module-cache-path /tmp/OneButtonSmokeModules "$combined" "$@"
