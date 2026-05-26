#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NATIVE="$ROOT/native"
RELEASE="$ROOT/release"
APP_NAME="Netra.app"
BINARY_NAME="Netra"
RESOURCES="$NATIVE/Sources/Netra/Resources"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$NATIVE/Info.plist" 2>/dev/null || echo "0.1.1-beta")"
ROOT_VERSION_FILE="$ROOT/VERSION"
if [[ -f "$ROOT_VERSION_FILE" ]]; then
  PLIST_VER="$(cat "$ROOT_VERSION_FILE" | tr -d '[:space:]')"
  if [[ "$PLIST_VER" != "$VERSION" ]]; then
    echo "⚠ VERSION 文件 ($PLIST_VER) 与 Info.plist ($VERSION) 不一致，以 Info.plist 为准" >&2
  fi
fi

echo "→ Swift 编译 (release)…"
cd "$NATIVE"
swift build -c release 2>&1

BIN="$NATIVE/.build/release/$BINARY_NAME"
if [[ ! -f "$BIN" ]]; then
  echo "错误: 未找到 $BIN" >&2
  exit 1
fi

STAGE="$NATIVE/.build/Netra.app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

cp "$BIN" "$STAGE/Contents/MacOS/$BINARY_NAME"
cp "$NATIVE/Info.plist" "$STAGE/Contents/Info.plist"
cp "$RESOURCES/master_oui.txt" "$STAGE/Contents/Resources/"

ICON_SRC="$RESOURCES/AppIcon.png"
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$STAGE/Contents/Resources/AppIcon.png"
  ICONSET="$NATIVE/.build/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  sips -z 16 16 "$ICON_SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET" -o "$STAGE/Contents/Resources/AppIcon.icns"
fi

chmod +x "$STAGE/Contents/MacOS/$BINARY_NAME"

ENTITLEMENTS="$NATIVE/Netra.entitlements"
echo "→ 代码签名 (ad-hoc，避免「已损坏」提示)…"
if [[ -f "$ENTITLEMENTS" ]]; then
  codesign --force --sign - --entitlements "$ENTITLEMENTS" --timestamp=none \
    "$STAGE/Contents/MacOS/$BINARY_NAME"
  codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" --timestamp=none \
    "$STAGE"
else
  codesign --force --sign - --timestamp=none "$STAGE/Contents/MacOS/$BINARY_NAME"
  codesign --force --deep --sign - --timestamp=none "$STAGE"
fi
codesign --verify --deep --strict "$STAGE" 2>&1
# 发布 zip 前去掉隔离标记（本机构建产物）
xattr -cr "$STAGE" 2>/dev/null || true

mkdir -p "$RELEASE"
rm -rf "$RELEASE/$APP_NAME"
cp -R "$STAGE" "$RELEASE/$APP_NAME"
xattr -cr "$RELEASE/$APP_NAME" 2>/dev/null || true

BUILD_TIME="$(date '+%Y-%m-%d %H:%M:%S %z')"
cat > "$RELEASE/BUILD.txt" <<EOF
Netra $VERSION (Swift Native)
Built: $BUILD_TIME
Path: $RELEASE/$APP_NAME
Runtime: SwiftUI + CoreWLAN
EOF

echo ""
echo "✓ 安装包:"
echo "  $RELEASE/$APP_NAME"
echo "  $RELEASE/BUILD.txt"
