#!/bin/bash
# 把源码编译成本地 .app（不安装、不改动系统）
# 产物：build/MenuBarAlert.app
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MenuBarAlert"
BUNDLE="build/$APP_NAME.app"

echo "==> 编译 $APP_NAME"
mkdir -p build
swiftc -O -o "build/$APP_NAME.bin" src/main.swift

mkdir -p "$BUNDLE/Contents/MacOS"
mv -f "build/$APP_NAME.bin" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp -f resources/Info.plist "$BUNDLE/Contents/Info.plist"

# 本地自签名（没有证书也能跑，这步失败不影响本机使用）
codesign --force -s - "$BUNDLE" >/dev/null 2>&1 || true

echo "==> 完成：$PWD/$BUNDLE"
