#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
combined=$(mktemp /tmp/folder-in-bar-localization.XXXXXX.swift)
trap 'rm -f "$combined"' EXIT
python3 - "$root" "$combined" <<'PY'
from pathlib import Path
import sys
root, output = map(Path, sys.argv[1:])
parts = []
for name, marker in [('ui_smoke.swift', 'final class Smoke {'),
                     ('drag_smoke.swift', 'func runDragChecks(')]:
    source = (root / 'script' / name).read_text()
    assert source.count(marker) == 1, f'Shared helper boundary changed: {name}'
    parts.append(source.split(marker)[0])
parts.append((root / 'script/localization_smoke.swift').read_text())
output.write_text('\n'.join(parts))
PY
swift -module-cache-path /tmp/OneButtonSmokeModules "$combined" "$@"
