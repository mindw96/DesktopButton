#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
  run|--debug|--logs|--telemetry|--verify) ;;
  *) echo "usage: $0 [--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="OneButton"
APP_BUNDLE="$PROJECT_ROOT/build/Build/Products/Debug/$APP_NAME.app"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
xcodebuild -project "$PROJECT_ROOT/OneButton.xcodeproj" -scheme "$APP_NAME" \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$PROJECT_ROOT/build" build -quiet

if [[ "$MODE" == --debug ]]; then
  exec lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi
/usr/bin/open -n "$APP_BUNDLE"
case "$MODE" in
  --logs) exec /usr/bin/log stream --info --style compact --predicate 'process == "OneButton"' ;;
  --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.onebutton.desktop"' ;;
  --verify)
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "OneButton 실행 확인: $APP_BUNDLE"
    ;;
esac
