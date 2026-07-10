#!/bin/bash
# 보카보아 macOS App DMG 패키징 스크립트

set -e

APP_NAME="BocaBoa.app"
BUILD_DIR=".build/debug"
APP_PATH="$BUILD_DIR/$APP_NAME"
DMG_NAME="BocaBoa.dmg"
BG_IMAGE="dmg_background.png"

echo "📦 DMG 패키징을 시작합니다..."

if [ ! -d "$APP_PATH" ]; then
    echo "❌ 에러: $APP_PATH 가 없습니다. 먼저 ./build.sh 를 실행하세요."
    exit 1
fi

if ! command -v create-dmg &> /dev/null; then
    echo "❌ 에러: create-dmg가 설치되어 있지 않습니다. 'brew install create-dmg' 명령어로 설치해주세요."
    exit 1
fi

# 이전 파일 정리
rm -f "$DMG_NAME"
rm -rf tmp_dmg
mkdir tmp_dmg

# 앱 이름 변경해서 복사
cp -r "$APP_PATH" "tmp_dmg/보카보아.app"

# 이름 변경 후 복사된 번들에 대해 Ad-hoc 서명을 재적용하여 서명 깨짐 방지
echo "🔏 보카보아.app 서명 재적용 중..."
xattr -cr "tmp_dmg/보카보아.app"
codesign --force --sign - --entitlements "Resources/BluetoothSearch.entitlements" "tmp_dmg/보카보아.app"

# 배경 이미지 설정
BG_FLAG=""
if [ -f "$BG_IMAGE" ]; then
    echo "🎨 배경 이미지 ($BG_IMAGE)를 적용합니다."
    BG_FLAG="--background $BG_IMAGE"
else
    echo "⚠️ $BG_IMAGE 파일이 없어 기본 배경을 사용합니다."
fi

# create-dmg 실행
create-dmg \
  --volname "보카보아 설치" \
  --volicon "Resources/AppIcon.icns" \
  $BG_FLAG \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "보카보아.app" 150 180 \
  --hide-extension "보카보아.app" \
  --app-drop-link 450 180 \
  "$DMG_NAME" \
  "tmp_dmg/"

rm -rf tmp_dmg

echo "🖼️ DMG 파일 자체의 아이콘을 변경합니다..."
cat << 'EOF' > set_dmg_icon.swift
import Cocoa

let args = CommandLine.arguments
if args.count < 3 { exit(1) }
let iconPath = args[1]
let targetPath = args[2]

if let icon = NSImage(contentsOfFile: iconPath) {
    let success = NSWorkspace.shared.setIcon(icon, forFile: targetPath, options: [])
    if success {
        print("✅ 아이콘이 파일에 적용되었습니다.")
    } else {
        print("❌ 아이콘 적용 실패.")
    }
} else {
    print("❌ 아이콘 파일을 읽을 수 없습니다.")
}
EOF

swift set_dmg_icon.swift "Resources/AppIcon.icns" "$DMG_NAME"
rm set_dmg_icon.swift

echo "✅ $DMG_NAME 파일이 성공적으로 생성 및 아이콘 적용 되었습니다!"
