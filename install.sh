#!/bin/bash
# 编译并安装到 ~/Applications/MenuBarAlert.app（覆盖旧版本）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MenuBarAlert"
DEST="$HOME/Applications/$APP_NAME.app"

./build.sh

echo "==> 安装到 $DEST"
mkdir -p "$DEST/Contents/MacOS"
cp -f "build/$APP_NAME.app/Contents/MacOS/$APP_NAME" "$DEST/Contents/MacOS/$APP_NAME"
cp -f "build/$APP_NAME.app/Contents/Info.plist" "$DEST/Contents/Info.plist"
codesign --force -s - "$DEST" >/dev/null 2>&1 || true

cat <<EOF
==> 安装完成

启动：        open "$DEST"
查看日志：    tail -n 20 ~/Library/Logs/$APP_NAME.log
EOF

if pgrep -x "$APP_NAME" >/dev/null; then
    echo "注意：$APP_NAME 正在运行，需重启后新版本才生效："
    echo "      pkill -x $APP_NAME; sleep 1; open \"$DEST\""
fi
