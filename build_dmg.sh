#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="Screenshot"
VERSION="1.1.1"
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
VOLUME_NAME="${APP_NAME} ${VERSION}"

echo "==> 清理旧构建..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/archive"
mkdir -p "$BUILD_DIR/dmg_stage"

echo "==> 编译 Release..."
xcodebuild archive \
  -project "$PROJECT_DIR/${APP_NAME}.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -archivePath "$BUILD_DIR/archive/${APP_NAME}.xcarchive" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  | grep -E "^(error:|warning:|Archive|Build succeeded|Build FAILED|===)" || true

echo "==> 导出 .app..."
APP_IN_ARCHIVE="$BUILD_DIR/archive/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app"
if [ ! -d "$APP_IN_ARCHIVE" ]; then
  echo "错误：找不到 .app，构建可能失败"
  exit 1
fi
cp -R "$APP_IN_ARCHIVE" "$BUILD_DIR/dmg_stage/${APP_NAME}.app"
ln -s /Applications "$BUILD_DIR/dmg_stage/Applications"

echo "==> 创建 DMG..."
DMG_TEMP="$BUILD_DIR/${APP_NAME}-temp.dmg"
DMG_FINAL="$PROJECT_DIR/dist/${DMG_NAME}"
mkdir -p "$PROJECT_DIR/dist"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$BUILD_DIR/dmg_stage" \
  -ov \
  -format UDRW \
  -fs HFS+ \
  "$DMG_TEMP" > /dev/null

echo "==> 压缩为只读 DMG..."
hdiutil convert "$DMG_TEMP" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_FINAL" > /dev/null

echo ""
echo "✓ 完成：dist/${DMG_NAME}"
echo "  大小：$(du -sh "$DMG_FINAL" | cut -f1)"
