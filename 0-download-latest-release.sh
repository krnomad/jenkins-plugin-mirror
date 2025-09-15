#!/bin/bash
set -e

REPO_URL=$(git remote get-url origin 2>/dev/null || echo "https://github.com/krnomad/jenkins-plugin-mirror")
REPO_NAME=$(echo "$REPO_URL" | sed -e 's/.*github\.com[:/]//' -e 's/\.git$//')
DOWNLOAD_DIR="jenkins-mirror"

# 기존 다운로드 디렉토리가 있으면 삭제 후 시작
if [ -d "$DOWNLOAD_DIR" ]; then
    echo "🧹 기존 $DOWNLOAD_DIR 디렉토리 삭제 중..."
    rm -rf "$DOWNLOAD_DIR"
fi
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed. Please install it to proceed."
    exit 1
fi

echo "🔍 Fetching latest release from repository: $REPO_NAME"

# Check if release has multi-part files
RELEASE_INFO=$(gh release view --repo "$REPO_NAME" --json assets)
MULTI_PART=$(echo "$RELEASE_INFO" | jq -r '.assets[].name' | grep -c "jenkins-plugins-comprehensive-part.*\.tar$" || echo "0")

if [ "$MULTI_PART" -gt 0 ]; then
    echo "📦 Multi-part release detected (${MULTI_PART} parts)"
    echo "Downloading all parts and assembly script..."
    
    # Get the latest release tag
    RELEASE_TAG=$(gh release list --repo "$REPO_NAME" --limit 1 | grep comprehensive | cut -f3)
    echo "Downloading release: $RELEASE_TAG"
    
    # Create download directory
    mkdir -p "$DOWNLOAD_DIR"
    cd "$DOWNLOAD_DIR"
    
    # Use curl for stable download of large files (gh CLI has issues with 1GB+ files)
    echo "Using curl for reliable large file downloads..."
    DOWNLOADED_PARTS=0
    for i in $(seq 1 $MULTI_PART); do
        echo "Attempting to download part $i..."
        curl -L -s -f -o "jenkins-plugins-comprehensive-part$i.tar" \
            "https://github.com/$REPO_NAME/releases/download/$RELEASE_TAG/jenkins-plugins-comprehensive-part$i.tar" || {
            echo "❌ Error: Failed to download part $i"
            echo "❌ 다운로드 오류가 발생했습니다. 다운로드된 파일들을 정리하고 다시 시도해주세요."
            cd ..
            rm -rf "$DOWNLOAD_DIR"
            exit 1
        }
        curl -L -s -f -o "jenkins-plugins-comprehensive-part$i.tar.sha256" \
            "https://github.com/$REPO_NAME/releases/download/$RELEASE_TAG/jenkins-plugins-comprehensive-part$i.tar.sha256" || {
            echo "Checksum for part $i not found"
        }
        DOWNLOADED_PARTS=$((DOWNLOADED_PARTS + 1))
    done
    
    # 다운로드된 파트 개수 확인
    if [ $DOWNLOADED_PARTS -ne $MULTI_PART ]; then
        echo "❌ Error: Expected $MULTI_PART parts, but only downloaded $DOWNLOADED_PARTS"
        echo "❌ 다운로드 오류가 발생했습니다. 다운로드된 파일들을 정리하고 다시 시도해주세요."
        cd ..
        rm -rf "$DOWNLOAD_DIR"
        exit 1
    fi
    
    # 로컬의 조립 스크립트 복사
    echo "Using local assembly script..."
    if [ -f "../1-assemble-comprehensive-mirror.sh" ]; then
        cp "../1-assemble-comprehensive-mirror.sh" "assemble-comprehensive-mirror.sh"
        chmod +x "assemble-comprehensive-mirror.sh"
    else
        echo "❌ Error: Local assembly script (1-assemble-comprehensive-mirror.sh) not found"
        cd ..
        rm -rf "$DOWNLOAD_DIR"
        exit 1
    fi
    
    echo "🔍 Verifying checksums..."
    for checksum_file in jenkins-plugins-comprehensive-part*.tar.sha256; do
        if [ -f "$checksum_file" ]; then
            echo "Verifying $checksum_file..."
            sha256sum -c "$checksum_file" || {
                echo "❌ Error: Checksum verification failed for $checksum_file"
                echo "❌ 체크섬 검증 실패. 다운로드된 파일들을 정리하고 다시 시도해주세요."
                cd ..
                rm -rf "$DOWNLOAD_DIR"
                exit 1
            }
        fi
    done
    
    echo "🔧 Assembling multi-part release..."
    chmod +x assemble-comprehensive-mirror.sh
    ./assemble-comprehensive-mirror.sh
    
    echo "🧹 Cleaning up part files..."
    rm -f jenkins-plugins-comprehensive-part*.tar* assemble-comprehensive-mirror.sh
    
    # 상위 디렉토리로 돌아가기
    cd ..
    
else
    echo "❌ Error: No multi-part release found. This script only supports multi-part releases."
    exit 1
fi

# MIRROR_DIR은 항상 jenkins-comprehensive-mirror 사용 (조립 스크립트에서 생성되는 디렉토리명)
MIRROR_DIR="$DOWNLOAD_DIR/jenkins-comprehensive-mirror"

PLUGIN_COUNT=$(find "$MIRROR_DIR" -name "*.hpi" -o -name "*.jpi" 2>/dev/null | wc -l || echo "0")
TOTAL_SIZE_MB=$(du -sm "$MIRROR_DIR" 2>/dev/null | cut -f1 || echo "0")

echo ""
echo "✅ Success! Jenkins mirror is ready!"
echo "📊 Statistics:"
echo "   - Directory: $MIRROR_DIR/"
echo "   - Plugins: $PLUGIN_COUNT"
echo "   - Total Size: ${TOTAL_SIZE_MB}MB"
echo ""
echo "🔧 Next Steps:"
echo "   1. Deploy the mirror using one of these methods:"
echo "      - Docker Compose (recommended): cd server/docker-image-layered && docker-compose up"
echo "      - Host Nginx: Copy $MIRROR_DIR to /var/www/ and configure nginx"
echo "   2. Configure Jenkins Update Site URL:"
echo "      http://your-server/$MIRROR_DIR/update-center2/update-center.json"
