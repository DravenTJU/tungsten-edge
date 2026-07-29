#!/usr/bin/env bash
# 构建 Release 版并用**固定的本地证书**签名后装进 /Applications，供 owner 日常使用
# 兼验收。
#
# 为什么需要这个脚本（2026-07-29 的教训）：
#   1. 日常包必须是 Release。Debug 没有编译器优化，最小化这类时序/动画敏感的操作
#      手感明显变差，曾被误判成版本回归（见 Obsidian「流程踩坑」2026-07-26）。
#   2. 但 package_release.sh 出的公开包是 **ad-hoc 签名**，没有稳定签名者身份，
#      系统只能拿每次构建都变的 CDHash 当身份 —— 于是每装一次新版，辅助功能授权
#      就失配一次，而系统设置里那条看着还是开的。
#   3. 开发构建与正式包 **bundle id 相同**，会抢同一条权限记录：给谁授权另一个就失效。
#
#   结论：日常只保留这一个包，用固定证书签名，授权一次即可跨重建延续。
#
# 与 package_release.sh 的分工：那个出对外发布的 ad-hoc 包，这个只装本机。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/macos-dock-cc-v2.xcodeproj"
SCHEME="macos-dock-cc-v2"
BUILT_NAME="macos-dock-cc-v2"
APP_NAME="Tungsten Edge"
DEST="/Applications/$APP_NAME.app"
IDENTITY="macos-dock-cc Local Code Signing"
DD="$ROOT/build/LocalReleaseDD"
PRODUCTS="$DD/Build/Products/Release"

if ! security find-identity -v -p codesigning | grep -Fq "\"$IDENTITY\""; then
  echo "error: 找不到固定签名证书「$IDENTITY」。" >&2
  echo "       没有它就只能 ad-hoc 签名，每次安装都会让辅助功能授权失效。" >&2
  exit 1
fi

echo "==> 构建 Release…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DD" build >/tmp/tungsten-local-install.log 2>&1
echo "    ok"

STAGE="$(mktemp -d)"
APP="$STAGE/$APP_NAME.app"
cp -R "$PRODUCTS/$BUILT_NAME.app" "$APP"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"   # 与发布包保持一致

echo "==> 用固定证书签名（授权跨重建延续的关键）…"
codesign --force --deep --sign "$IDENTITY" "$APP"
codesign -dvvv "$APP" 2>&1 | grep -E "^Authority|^Identifier" | sed 's/^/    /'

echo "==> 退出正在运行的实例…"
pkill -x "$BUILT_NAME" >/dev/null 2>&1 || true
for _ in $(seq 1 25); do
  pgrep -x "$BUILT_NAME" >/dev/null 2>&1 || break
  sleep 0.2
done

# 注意花括号：紧跟其后的省略号是多字节字符，写成 $DEST… 会被当成变量名的一部分，
# 在 set -u 下直接报 unbound variable。
echo "==> 安装到 ${DEST}…"
rm -rf "$DEST"
ditto "$APP" "$DEST"          # 必须用 ditto：普通 cp 不保留符号链接，会破坏签名
rm -rf "$STAGE"

VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DEST/Contents/Info.plist")"
echo "==> 完成：$VER ($BUILD)"
codesign --verify --deep --strict "$DEST" && echo "    签名校验通过"
echo "    启动：open \"$DEST\""
