#!/bin/bash
set -e

echo "🔧 Jenkins Comprehensive Mirror 조립 중..."

# 모든 파트가 있는지 확인
PARTS=(jenkins-plugins-comprehensive-part*.tar.gz)
if [ ${#PARTS[@]} -eq 0 ]; then
    echo "❌ 파트 파일을 찾을 수 없습니다"
    exit 1
fi

echo "📦 발견된 파트: ${#PARTS[@]}개"

# 체크섬 검증
echo "🔍 체크섬 검증 중..."
for file in jenkins-plugins-comprehensive-part*.tar.gz; do
    if [ -f "${file}.sha256" ]; then
        echo "검증: $file"
        sha256sum -c "${file}.sha256" || {
            echo "❌ 체크섬 검증 실패: $file"
            exit 1
        }
    fi
done

# 조립 디렉토리 생성
MIRROR_DIR="jenkins-comprehensive-mirror"
rm -rf "$MIRROR_DIR"
mkdir -p "$MIRROR_DIR"

echo "🔄 파트 조립 중..."
# 분할된 파일들을 순서대로 결합하여 원본 tar 복원
cat jenkins-plugins-comprehensive-part*.tar.gz | gunzip | tar -xf - -C "$MIRROR_DIR"

echo "✅ 조립 완료!"
echo "📊 최종 미러 크기: $(du -sh "$MIRROR_DIR" | cut -f1)"
echo "📁 미러 위치: ./$MIRROR_DIR"
echo ""
echo "🚀 사용 방법:"
echo "   1. 웹 서버에 $MIRROR_DIR 디렉토리 복사"
echo "   2. Jenkins에서 Update Site URL을 http://your-server/$MIRROR_DIR/update-center2/update-center.json 로 설정"
