#!/bin/bash
# BocaBoa - 보카보카 커피 로스터 프로파일링 macOS App Build Script
# 사용법: chmod +x build.sh && ./build.sh

set -e

APP_NAME="BocaBoa"
EXECUTABLE_NAME="BluetoothSearch"
BUILD_CONFIG="debug"
# 유니버설 빌드(멀티 아키텍처)의 경우 빌드 결과물 바이너리가 .build/apple/Products/ 디렉토리에 생성되므로
# 바이너리 복사용 소스 디렉토리(SRC_BUILD_DIR)와 최종 .app 번들 생성용 디렉토리(DST_BUILD_DIR)를 나눕니다.
SRC_BUILD_DIR=".build/apple/Products/$BUILD_CONFIG"
DST_BUILD_DIR=".build/$BUILD_CONFIG"
APP_DIR="$DST_BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ENTITLEMENTS="Resources/BluetoothSearch.entitlements"
INFOPLIST="Resources/Info.plist"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🟢 BocaBoa - 보카보카 커피 로스터 프로파일링 - macOS App Build"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Swift 빌드
echo ""
echo "📦 [1/4] Swift 빌드 중..."
swift build -c $BUILD_CONFIG --arch arm64 --arch x86_64
echo "  ✅ 빌드 성공"

# 2. .app 번들 생성
echo ""
echo "🏗️  [2/4] .app 번들 생성 중..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
cp "$SRC_BUILD_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/"
cp "$INFOPLIST" "$CONTENTS_DIR/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/"
    echo "  🎨 앱 아이콘 복사 완료"
fi
if [ -f "Resources/coffee-bean.svg" ]; then
    cp "Resources/coffee-bean.svg" "$RESOURCES_DIR/"
    echo "  ☕ 커피 원두 이미지 복사 완료"
fi
if [ -f "Resources/appname.png" ]; then
    cp "Resources/appname.png" "$RESOURCES_DIR/"
    echo "  🏷️ 앱 이름 로고 복사 완료"
fi
for img in spon.png kakaobank.png paypal.png ror_chart.png; do
    if [ -f "Resources/$img" ]; then
        cp "Resources/$img" "$RESOURCES_DIR/"
        echo "  💰 후원 이미지 ($img) 복사 완료"
    fi
done
if [ -f "Resources/pencil.svg" ]; then
    cp "Resources/pencil.svg" "$RESOURCES_DIR/"
    echo "  ✏️  연필 아이콘 (pencil.svg) 복사 완료"
fi
if [ -f "Resources/bluetooth-off.svg" ]; then
    cp "Resources/bluetooth-off.svg" "$RESOURCES_DIR/"
    echo "  📶 블루투스 오프 아이콘 (bluetooth-off.svg) 복사 완료"
fi
echo "  ✅ 번들 생성 완료: $APP_DIR"

# 3. 코드 서명 (Ad-hoc + Entitlements)
echo ""
echo "🔏 [3/4] 코드 서명 중 (Ad-hoc + Bluetooth entitlements)..."
xattr -cr "$APP_DIR"
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_DIR"
echo "  ✅ 코드 서명 완료"

# 4. 실행
echo ""
echo "🚀 [4/4] 앱 실행 중..."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ 완료! BLE Scanner 실행됩니다."
echo "  ⚠️  처음 실행 시 Bluetooth 권한 요청이 나타납니다."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
open "$APP_DIR"
