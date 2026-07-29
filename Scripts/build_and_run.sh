#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="macos-dock-cc-v2"
CLI_NAME="window-lab"
PROJECT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/macos-dock-cc-v2.xcodeproj"
DERIVED_DATA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/Debug/$APP_NAME.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
LOCAL_SIGNING_IDENTITY="macos-dock-cc Local Code Signing"

build_app() {
  xcodebuild -project "$PROJECT_PATH" -scheme "$APP_NAME" -configuration Debug -derivedDataPath "$DERIVED_DATA_DIR" build >/tmp/macos-dock-cc-v2-build.log 2>&1
}

sign_app() {
  if security find-identity -v -p codesigning | grep -Fq "\"$LOCAL_SIGNING_IDENTITY\""; then
    /usr/bin/codesign --force --deep --sign "$LOCAL_SIGNING_IDENTITY" "$APP_BUNDLE" >/tmp/macos-dock-cc-v2-codesign.log 2>&1
  else
    echo "warning: local signing identity not found; keeping Xcode's build signature" >&2
  fi
}

run_cli() {
  xcodebuild -project "$PROJECT_PATH" -scheme "$CLI_NAME" -configuration Debug -derivedDataPath "$DERIVED_DATA_DIR" build >/tmp/macos-dock-cc-v2-build.log 2>&1
  "$DERIVED_DATA_DIR/Build/Products/Debug/$CLI_NAME" "$@"
}

# 先确认旧进程真的退干净了再启动。原先这里用 `open -n`（强制再开一个新实例），
# 只要 pkill 慢一拍或有别处启动的实例没被 pkill 覆盖到，屏幕上就会出现两条一模一样
# 的任务条，验收时根本分不清测的是哪个版本。
wait_for_exit() {
  local attempt
  for attempt in $(seq 1 25); do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || return 0
    sleep 0.2
  done
  echo "warning: 旧实例 5 秒内未退出，强制结束" >&2
  pkill -9 -x "$APP_NAME" >/dev/null 2>&1 || true
  sleep 0.3
}

open_app() {
  wait_for_exit
  /usr/bin/open "$APP_BUNDLE"
}

wait_for_app() {
  local attempt
  for attempt in $(seq 1 20); do
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

case "$MODE" in
  run)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    build_app
    sign_app
    open_app
    ;;
  --debug|debug)
    build_app
    lldb -- "$APP_EXECUTABLE"
    ;;
  --logs|logs)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    build_app
    sign_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    build_app
    sign_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"com.caye.macosdockcc.v2\""
    ;;
  --verify|verify)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    build_app
    sign_app
    open_app
    wait_for_app
    ;;
  --lab|lab)
    run_cli "${@:2}"
    ;;
  --lab-minimize|lab-minimize)
    run_cli minimizeRestore "${@:2}"
    ;;
  --lab-close|lab-close)
    run_cli closeTarget "${@:2}"
    ;;
  --lab-replay|lab-replay)
    run_cli replay "${2:-minimize-restore-replay}"
    ;;
  --lab-placement|lab-placement)
    run_cli placementReplay "${2:-placement-permanent-hold-replay}"
    ;;
  --lab-transition|lab-transition)
    run_cli transitionReplay "${2:-focused-active-replay}"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--lab|--lab-minimize|--lab-close|--lab-replay [scenario-name]|--lab-placement [scenario-name]|--lab-transition [scenario-name]]" >&2
    exit 2
    ;;
esac
