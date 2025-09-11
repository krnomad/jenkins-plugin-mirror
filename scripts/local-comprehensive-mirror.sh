#!/bin/bash
# Local Comprehensive Jenkins Mirror Generator
# 로컬 환경에서 전체 미러 생성 후 GitHub Release 용 패키징

set -e

MIRROR_ROOT="/tmp/jenkins-comprehensive-mirror"
PACKAGE_DIR="/tmp/jenkins-release-packages"
MAX_PART_SIZE_GB=1.8  # GitHub 2GB 제한 고려

# 컬러 출력
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# 1. 환경 준비
prepare_environment() {
    log "환경 준비 중..."
    
    # 디렉토리 생성
    mkdir -p "$MIRROR_ROOT"/{download/plugins,update-center2}
    mkdir -p "$PACKAGE_DIR"
    
    # 디스크 공간 확인
    AVAILABLE_GB=$(df /tmp | awk 'NR==2 {print int($4/1024/1024)}')
    if [ $AVAILABLE_GB -lt 50 ]; then
        error "디스크 공간 부족: ${AVAILABLE_GB}GB 사용 가능 (최소 50GB 필요)"
        exit 1
    fi
    
    success "환경 준비 완료 (사용 가능: ${AVAILABLE_GB}GB)"
}

# 2. 전체 미러 생성 (기존 스크립트 기반)
create_comprehensive_mirror() {
    log "전체 Jenkins Plugin 미러 생성 중..."
    
    cd /tmp
    
    # Update Center 메타데이터 다운로드
    log "Update Center 메타데이터 다운로드..."
    wget -q --timeout=30 --tries=3 -O update-center.json "https://updates.jenkins.io/update-center.json"
    wget -q --timeout=30 --tries=3 -O update-center.actual.json "https://updates.jenkins.io/update-center.actual.json"
    
    cp *.json "$MIRROR_ROOT/update-center2/"
    
    # 최신 플러그인 다운로드
    log "최신 플러그인 다운로드..."
    PLUGIN_LIST=$(jq -r '.plugins | keys[]' update-center.actual.json)
    TOTAL_PLUGINS=$(echo "$PLUGIN_LIST" | wc -l)
    CURRENT=0
    
    for plugin in $PLUGIN_LIST; do
        CURRENT=$((CURRENT + 1))
        
        if [ $((CURRENT % 100)) -eq 0 ]; then
            log "진행률: $CURRENT/$TOTAL_PLUGINS (최신 버전)"
        fi
        
        PLUGIN_URL=$(jq -r ".plugins[\"$plugin\"].url" update-center.actual.json)
        
        if [ "$PLUGIN_URL" != "null" ]; then
            PLUGIN_FILE=$(basename "$PLUGIN_URL")
            PLUGIN_DIR="$MIRROR_ROOT/download/plugins/$plugin"
            
            mkdir -p "$PLUGIN_DIR"
            
            if [ ! -f "$PLUGIN_DIR/$PLUGIN_FILE" ]; then
                wget -q --timeout=60 --tries=3 -O "$PLUGIN_DIR/$PLUGIN_FILE" "$PLUGIN_URL" || {
                    warning "$plugin 다운로드 실패"
                    rm -f "$PLUGIN_DIR/$PLUGIN_FILE"
                }
            fi
        fi
    done
    
    # 전체 rsync 동기화 (핵심!)
    log "전체 rsync 히스토리 동기화 중... (시간이 오래 걸립니다)"
    rsync -av --timeout=600 --delete --exclude="*.tmp" \
        rsync://rsync.osuosl.org/jenkins/plugins/ \
        "$MIRROR_ROOT/download/plugins/" \
        2>&1 | tee rsync.log || warning "rsync 동기화에서 일부 오류 발생"
    
    # 통계 출력
    PLUGIN_COUNT=$(find "$MIRROR_ROOT/download/plugins" -name "*.hpi" -o -name "*.jpi" | wc -l)
    TOTAL_SIZE_GB=$(du -sh "$MIRROR_ROOT" | cut -f1)
    
    success "미러 생성 완료: ${PLUGIN_COUNT}개 파일, 총 크기: ${TOTAL_SIZE_GB}"
    
    rm -f /tmp/*.json /tmp/rsync.log
}

# 3. 스마트 패키징 (크기별 분할)
create_release_packages() {
    log "GitHub Release용 패키징 중..."
    
    cd "$MIRROR_ROOT"
    
    # 전체 크기 계산
    TOTAL_SIZE_MB=$(du -sm . | cut -f1)
    MAX_PART_SIZE_MB=$(($(echo "$MAX_PART_SIZE_GB * 1024" | bc | cut -d. -f1)))
    ESTIMATED_PARTS=$(((TOTAL_SIZE_MB + MAX_PART_SIZE_MB - 1) / MAX_PART_SIZE_MB))
    
    log "총 크기: ${TOTAL_SIZE_MB}MB, 예상 파트 수: ${ESTIMATED_PARTS}개"
    
    # 플러그인을 크기별로 정렬하고 분할
    find download/plugins -name "*.hpi" -o -name "*.jpi" | \
        xargs -I {} du -m {} | sort -nr > /tmp/plugin_sizes.txt
    
    part_num=1
    current_size=0
    current_part_dir="$PACKAGE_DIR/part${part_num}"
    
    mkdir -p "$current_part_dir/download/plugins"
    cp -r update-center2 "$current_part_dir/"
    
    while read size_mb filepath; do
        # 새 파트가 필요한지 확인
        if [ $((current_size + size_mb)) -gt $MAX_PART_SIZE_MB ] && [ $current_size -gt 0 ]; then
            log "Part $part_num: ${current_size}MB 완료"
            
            part_num=$((part_num + 1))
            current_size=0
            current_part_dir="$PACKAGE_DIR/part${part_num}"
            
            mkdir -p "$current_part_dir/download/plugins"
            cp -r update-center2 "$current_part_dir/"
        fi
        
        # 플러그인 디렉토리 구조 유지하며 복사
        plugin_name=$(basename $(dirname "$filepath"))
        mkdir -p "$current_part_dir/download/plugins/$plugin_name"
        cp "$filepath" "$current_part_dir/download/plugins/$plugin_name/"
        
        current_size=$((current_size + size_mb))
    done < /tmp/plugin_sizes.txt
    
    log "Part $part_num: ${current_size}MB 완료"
    
    # 각 파트를 압축
    cd "$PACKAGE_DIR"
    for part_dir in part*; do
        if [ -d "$part_dir" ]; then
            part_name=$(basename "$part_dir")
            log "압축 중: jenkins-plugins-comprehensive-${part_name}.tar.gz"
            
            tar -czf "jenkins-plugins-comprehensive-${part_name}.tar.gz" -C "$part_dir" .
            sha256sum "jenkins-plugins-comprehensive-${part_name}.tar.gz" > "jenkins-plugins-comprehensive-${part_name}.tar.gz.sha256"
            
            # 압축된 크기 확인
            compressed_size=$(du -m "jenkins-plugins-comprehensive-${part_name}.tar.gz" | cut -f1)
            log "완료: ${part_name} (압축 후: ${compressed_size}MB)"
        fi
    done
    
    # 조립 스크립트 생성
    create_assembly_script
    
    success "패키징 완료: $(ls jenkins-plugins-comprehensive-part*.tar.gz | wc -l)개 파트"
    
    rm -f /tmp/plugin_sizes.txt
}

# 4. 조립 스크립트 생성
create_assembly_script() {
    cat > "$PACKAGE_DIR/assemble-comprehensive-mirror.sh" << 'EOF'
#!/bin/bash
# Jenkins Comprehensive Mirror Assembly Script

set -e

MIRROR_DIR="jenkins-comprehensive-mirror"

echo "🔧 Jenkins Comprehensive Plugin Mirror Assembly"
echo "=============================================="
echo ""

# 디스크 공간 확인
REQUIRED_GB=30
AVAILABLE_GB=$(df . | awk 'NR==2 {print int($4/1024/1024)}')

if [ $AVAILABLE_GB -lt $REQUIRED_GB ]; then
    echo "❌ 디스크 공간 부족: ${AVAILABLE_GB}GB (최소 ${REQUIRED_GB}GB 필요)"
    exit 1
fi

# 타겟 디렉토리 생성
mkdir -p "$MIRROR_DIR"

# 모든 파트 추출
echo "📦 압축 파일 추출 중..."
for part in jenkins-plugins-comprehensive-part*.tar.gz; do
    if [ -f "$part" ]; then
        echo "  - $part 추출 중..."
        tar -xzf "$part" -C "$MIRROR_DIR" --skip-old-files
    fi
done

# 통계 계산
PLUGIN_COUNT=$(find "$MIRROR_DIR" -name "*.hpi" -o -name "*.jpi" | wc -l)
TOTAL_SIZE_GB=$(du -sh "$MIRROR_DIR" | cut -f1)
UNIQUE_PLUGINS=$(find "$MIRROR_DIR/download/plugins" -maxdepth 1 -type d | wc -l)

echo ""
echo "✅ 조립 완료!"
echo "📊 통계:"
echo "   - 총 플러그인 파일: $PLUGIN_COUNT개"
echo "   - 고유 플러그인: $((UNIQUE_PLUGINS - 1))개"  
echo "   - 전체 크기: $TOTAL_SIZE_GB"
echo "   - 미러 디렉토리: $MIRROR_DIR/"
echo ""
echo "🚀 다음 단계:"
echo "   1. $MIRROR_DIR/update-center2/update-center.json 파일에서"
echo "      'https://updates.jenkins.io'를 여러분의 서버 URL로 변경"
echo "   2. 웹서버 설정: nginx/apache로 $MIRROR_DIR 서빙"
echo "   3. Jenkins에서 업데이트 사이트 URL을 여러분 서버로 변경"
echo ""
echo "💡 Docker 빠른 시작:"
echo "   cd server/docker-image-layered"
echo "   docker-compose up"
EOF
    
    chmod +x "$PACKAGE_DIR/assemble-comprehensive-mirror.sh"
}

# 5. 업로드 가이드 생성
create_upload_guide() {
    cat > "$PACKAGE_DIR/UPLOAD_GUIDE.md" << EOF
# GitHub Release 업로드 가이드

## 📋 생성된 파일들

$(ls -la jenkins-plugins-comprehensive-part*.tar.gz* | awk '{print "- " $9 " (" $5 " bytes)"}')
- assemble-comprehensive-mirror.sh (조립 스크립트)

## 🚀 GitHub Release 생성

\`\`\`bash
# 1. 릴리즈 생성
gh release create comprehensive-v$(date +'%Y.%m.%d') \\
  --title "Jenkins Comprehensive Plugin Mirror - v$(date +'%Y.%m.%d')" \\
  --notes "Complete Jenkins plugin mirror with historical versions

📊 **Statistics:**
- Plugin Files: $(find $MIRROR_ROOT -name "*.hpi" -o -name "*.jpi" | wc -l)
- Total Size: $(du -sh $MIRROR_ROOT | cut -f1)
- Parts: $(ls jenkins-plugins-comprehensive-part*.tar.gz | wc -l) files

🚀 **Usage:**
1. Download all parts and assembly script
2. Run: \\\`./assemble-comprehensive-mirror.sh\\\`  
3. Deploy using provided Docker configuration

**Complete Legacy Support:**
- Historical plugin versions included
- Offline Jenkins environments supported
- Compatible with older Jenkins versions"

# 2. 파일 업로드
$(for file in jenkins-plugins-comprehensive-part*.tar.gz jenkins-plugins-comprehensive-part*.tar.gz.sha256 assemble-comprehensive-mirror.sh; do
    echo "gh release upload comprehensive-v$(date +'%Y.%m.%d') $file"
done)
\`\`\`

## ⚡ 자동 업로드 스크립트

\`\`\`bash
$(cat << 'SCRIPT'
#!/bin/bash
RELEASE_TAG="comprehensive-v$(date +'%Y.%m.%d')"

# 릴리즈 생성 (기존 것이 있으면 삭제)
gh release list | grep -q "$RELEASE_TAG" && gh release delete "$RELEASE_TAG" -y || true

gh release create "$RELEASE_TAG" \\
  --title "Jenkins Comprehensive Plugin Mirror - $RELEASE_TAG" \\
  --notes-file RELEASE_NOTES.md \\
  jenkins-plugins-comprehensive-part*.tar.gz \\
  jenkins-plugins-comprehensive-part*.tar.gz.sha256 \\
  assemble-comprehensive-mirror.sh
SCRIPT
)
\`\`\`
EOF
}

# 6. 메인 실행
main() {
    echo -e "${BLUE}"
    echo "==============================================="
    echo "  Jenkins Comprehensive Mirror Generator"
    echo "  로컬 환경에서 전체 미러 생성 + GitHub 배포용 패키징"
    echo "==============================================="
    echo -e "${NC}"
    
    prepare_environment
    create_comprehensive_mirror
    create_release_packages
    create_upload_guide
    
    echo ""
    success "🎉 전체 프로세스 완료!"
    echo ""
    log "📁 결과 위치: $PACKAGE_DIR"
    log "📚 업로드 가이드: $PACKAGE_DIR/UPLOAD_GUIDE.md"
    echo ""
    log "🚀 다음 단계:"
    echo "   1. cd $PACKAGE_DIR"
    echo "   2. UPLOAD_GUIDE.md 참조하여 GitHub Release 생성"
    echo "   3. 생성된 파트 파일들과 조립 스크립트 업로드"
    
    # 최종 통계
    FINAL_PARTS=$(ls "$PACKAGE_DIR"/jenkins-plugins-comprehensive-part*.tar.gz | wc -l)
    FINAL_SIZE=$(du -sh "$PACKAGE_DIR" | cut -f1)
    
    echo ""
    echo -e "${GREEN}📊 최종 통계:${NC}"
    echo "   - 미러 크기: $(du -sh $MIRROR_ROOT | cut -f1)"
    echo "   - 패키지 수: ${FINAL_PARTS}개 파트"
    echo "   - 패키지 크기: ${FINAL_SIZE}"
    echo "   - 플러그인 파일: $(find $MIRROR_ROOT -name "*.hpi" -o -name "*.jpi" | wc -l)개"
}

# Cleanup on exit
cleanup() {
    if [ -n "$MIRROR_ROOT" ] && [ "$MIRROR_ROOT" != "/" ]; then
        warning "정리 중: $MIRROR_ROOT"
        rm -rf "$MIRROR_ROOT"
    fi
}

trap cleanup EXIT

# 실행
main "$@"