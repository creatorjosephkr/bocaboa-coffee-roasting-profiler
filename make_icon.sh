#!/bin/bash
# 1024x1024 크기의 icon.png 이미지 파일을 기반으로 macOS AppIcon.icns 생성

set -e

SOURCE_IMAGE="icon.png"

if [ ! -f "$SOURCE_IMAGE" ]; then
    echo "❌ 에러: 프로젝트 루트에 $SOURCE_IMAGE 파일이 없습니다."
    echo "   1024x1024 크기의 PNG 이미지를 $SOURCE_IMAGE 이름으로 저장한 후 다시 실행해줘."
    exit 1
fi

echo "🎨 AppIcon.icns 생성 시작..."

ICONSET_DIR="AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

# 해상도별 이미지 생성
sips -z 16 16     "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null 2>&1
sips -z 32 32     "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null 2>&1
sips -z 32 32     "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null 2>&1
sips -z 64 64     "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null 2>&1
sips -z 128 128   "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null 2>&1
sips -z 256 256   "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null 2>&1
sips -z 256 256   "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null 2>&1
sips -z 512 512   "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null 2>&1
sips -z 512 512   "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null 2>&1
sips -z 1024 1024 "$SOURCE_IMAGE" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null 2>&1

# Resources 디렉토리가 없으면 생성
mkdir -p Resources

# iconutil로 .icns 파일 변환
iconutil -c icns "$ICONSET_DIR" -o Resources/AppIcon.icns

# 임시 디렉토리 제거
rm -rf "$ICONSET_DIR"

echo "✅ Resources/AppIcon.icns 파일이 생성되었어!"
echo "   이제 ./build.sh 를 실행하면 아이콘이 적용된 앱이 빌드돼."
