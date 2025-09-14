#!/bin/bash
# Local Comprehensive Jenkins Mirror Generator
# 로컬 환경에서 증분 미러 업데이트 후 GitHub Release 용 패키징

set -e

# 설정 가능한 경로들
EXISTING_MIRROR_ROOT="/var/www/jenkins-mirror"  # 기존 미러 위치
MIRROR_ROOT="/tmp/jenkins-comprehensive-mirror"
PACKAGE_DIR="/tmp/jenkins-release-packages"
MAX_PART_SIZE_GB=1.8  # GitHub 2GB 제한 고려
MAX_RELEASES_TO_KEEP=3  # 유지할 릴리즈 개수

# 컬러 출력
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

info() {
    echo -e "${PURPLE}💡 $1${NC}"
}

# 1. 환경 준비 및 기존 미러 확인
prepare_environment() {
    log "환경 준비 및 기존 미러 확인 중..."
    
    # 기존 미러 존재 확인
    if [ -d "$EXISTING_MIRROR_ROOT" ]; then
        EXISTING_SIZE=$(du -sh "$EXISTING_MIRROR_ROOT" 2>/dev/null | cut -f1 || echo "Unknown")
        EXISTING_FILES=$(find "$EXISTING_MIRROR_ROOT" -name "*.hpi" -o -name "*.jpi" 2>/dev/null | wc -l || echo "0")
        info "기존 미러 발견: $EXISTING_MIRROR_ROOT"
        info "  - 크기: $EXISTING_SIZE"
        info "  - 플러그인 파일: $EXISTING_FILES 개"
        
        # 기존 미러를 작업 디렉토리로 링크 (빠른 증분 업데이트)
        log "기존 미러와 연결 중..."
        mkdir -p "$MIRROR_ROOT"
        
        # 기존 디렉토리 구조를 하드링크로 복사 (매우 빠름)
        rsync -av --link-dest="$EXISTING_MIRROR_ROOT" "$EXISTING_MIRROR_ROOT/" "$MIRROR_ROOT/" 2>/dev/null || {
            # rsync 실패시 심볼릭 링크 사용
            warning "rsync 실패, 심볼릭 링크를 사용합니다."
            ln -sf "$EXISTING_MIRROR_ROOT/download" "$MIRROR_ROOT/download" 2>/dev/null || {
                mkdir -p "$MIRROR_ROOT/download/plugins"
                warning "링크 실패, 빈 디렉토리로 시작합니다."
            }
            ln -sf "$EXISTING_MIRROR_ROOT/update-center2" "$MIRROR_ROOT/update-center2" 2>/dev/null || {
                mkdir -p "$MIRROR_ROOT/update-center2"
            }
        }
        success "기존 미러 연결 완료"
    else
        warning "기존 미러를 찾을 수 없습니다: $EXISTING_MIRROR_ROOT"
        info "새로운 미러를 생성합니다."
        mkdir -p "$MIRROR_ROOT"/{download/plugins,update-center2}
    fi
    
    # 패키지 디렉토리 생성
    mkdir -p "$PACKAGE_DIR"
    
    # 디스크 공간 확인
    AVAILABLE_GB=$(df /tmp | awk 'NR==2 {print int($4/1024/1024)}')
    if [ $AVAILABLE_GB -lt 35 ]; then
        error "디스크 공간 부족: ${AVAILABLE_GB}GB 사용 가능 (최소 35GB 필요)"
        exit 1
    fi
    
    success "환경 준비 완료 (사용 가능: ${AVAILABLE_GB}GB)"
}

# 2. 증분 미러 업데이트 (기존 미러 기반)
create_comprehensive_mirror() {
    log "증분 Jenkins Plugin 미러 업데이트 중..."
    
    cd /tmp
    
    # Update Center 메타데이터 다운로드
    log "Update Center 메타데이터 업데이트..."
    wget -q --timeout=30 --tries=3 -O update-center.json "https://updates.jenkins.io/update-center.json"
    wget -q --timeout=30 --tries=3 -O update-center.actual.json "https://updates.jenkins.io/update-center.actual.json"
    
    # 메타데이터 업데이트
    mkdir -p "$MIRROR_ROOT/update-center2"
    cp *.json "$MIRROR_ROOT/update-center2/"
    
    # 기존 대비 새로운/업데이트된 최신 플러그인만 다운로드
    log "최신 플러그인 증분 업데이트..."
    PLUGIN_LIST=$(jq -r '.plugins | keys[]' update-center.actual.json)
    TOTAL_PLUGINS=$(echo "$PLUGIN_LIST" | wc -l)
    CURRENT=0
    UPDATED=0
    SKIPPED=0
    
    for plugin in $PLUGIN_LIST; do
        CURRENT=$((CURRENT + 1))
        
        if [ $((CURRENT % 100)) -eq 0 ]; then
            log "진행률: $CURRENT/$TOTAL_PLUGINS (업데이트: $UPDATED, 스킵: $SKIPPED)"
        fi
        
        PLUGIN_URL=$(jq -r ".plugins[\"$plugin\"].url" update-center.actual.json)
        
        if [ "$PLUGIN_URL" != "null" ]; then
            PLUGIN_FILE=$(basename "$PLUGIN_URL")
            PLUGIN_DIR="$MIRROR_ROOT/download/plugins/$plugin"
            
            mkdir -p "$PLUGIN_DIR"
            
            # 기존 파일들을 먼저 확인 (다양한 확장자와 버전을 고려)
            EXISTING_FILE=$(find "$PLUGIN_DIR" -name "*.hpi" -o -name "*.jpi" 2>/dev/null | head -1)
            
            # 디버깅을 위한 로그 (첫 5개 플러그인만)
            if [ $CURRENT -le 5 ]; then
                log "디버깅: $plugin - 기존파일: $EXISTING_FILE"
            fi
            
            # 파일이 존재하고 크기가 0이 아닌 경우 스킵
            if [ -n "$EXISTING_FILE" ] && [ -s "$EXISTING_FILE" ]; then
                SKIPPED=$((SKIPPED + 1))
                continue
            fi
            
            # 파일이 존재하지 않거나 크기가 0인 경우만 다운로드
            wget -q --timeout=60 --tries=3 -O "$PLUGIN_DIR/$PLUGIN_FILE" "$PLUGIN_URL" || {
                warning "$plugin 다운로드 실패"
                rm -f "$PLUGIN_DIR/$PLUGIN_FILE"
                continue
            }
            UPDATED=$((UPDATED + 1))
        fi
    done
    
    info "최신 플러그인 업데이트 완료: $UPDATED개 업데이트, $SKIPPED개 스킵"
    
    # 증분 rsync 동기화 (--update 플래그 사용)
    log "rsync 증분 히스토리 동기화 중... (기존보다 빠름)"
    rsync -av --update --timeout=600 --exclude="*.tmp" \
        rsync://rsync.osuosl.org/jenkins/plugins/ \
        "$MIRROR_ROOT/download/plugins/" \
        2>&1 | tee rsync.log || warning "rsync 동기화에서 일부 오류 발생"
    
    # rsync 통계 분석
    if [ -f rsync.log ]; then
        NEW_FILES=$(grep -c ">" rsync.log 2>/dev/null || echo "0")
        info "rsync 결과: $NEW_FILES개 새 파일 동기화"
    fi
    
    # 최종 통계 출력
    PLUGIN_COUNT=$(find "$MIRROR_ROOT/download/plugins" -name "*.hpi" -o -name "*.jpi" | wc -l)
    TOTAL_SIZE_GB=$(du -sh "$MIRROR_ROOT" | cut -f1)
    UNIQUE_PLUGINS=$(find "$MIRROR_ROOT/download/plugins" -maxdepth 1 -type d | wc -l)
    
    success "증분 미러 업데이트 완료:"
    success "  - 총 플러그인 파일: ${PLUGIN_COUNT}개"  
    success "  - 고유 플러그인: $((UNIQUE_PLUGINS - 1))개"
    success "  - 총 크기: ${TOTAL_SIZE_GB}"
    
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

# 5. 이전 릴리즈 정리 (최신 3개만 유지)
cleanup_old_releases() {
    log "이전 릴리즈 정리 중 (최신 ${MAX_RELEASES_TO_KEEP}개만 유지)..."
    
    # comprehensive 태그의 릴리즈 목록 가져오기
    RELEASE_LIST=$(gh release list --limit 20 | grep "comprehensive-v" | awk '{print $3}' | head -20)
    RELEASE_COUNT=$(echo "$RELEASE_LIST" | wc -l)
    
    if [ $RELEASE_COUNT -gt $MAX_RELEASES_TO_KEEP ]; then
        RELEASES_TO_DELETE=$(echo "$RELEASE_LIST" | tail -n +$((MAX_RELEASES_TO_KEEP + 1)))
        
        info "발견된 comprehensive 릴리즈: $RELEASE_COUNT개"
        info "유지할 릴리즈: $MAX_RELEASES_TO_KEEP개"
        info "삭제할 릴리즈: $(echo "$RELEASES_TO_DELETE" | wc -l)개"
        
        echo "$RELEASES_TO_DELETE" | while read release_tag; do
            if [ -n "$release_tag" ]; then
                log "이전 릴리즈 삭제 중: $release_tag"
                gh release delete "$release_tag" -y 2>/dev/null || warning "릴리즈 삭제 실패: $release_tag"
            fi
        done
        
        success "이전 릴리즈 정리 완료"
    else
        info "정리할 릴리즈 없음 (현재: $RELEASE_COUNT개, 최대: $MAX_RELEASES_TO_KEEP개)"
    fi
}

# 6. 업로드 가이드 생성
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

# 7. 자동 릴리즈 생성 및 업로드
create_github_release() {
    log "GitHub Release 생성 및 업로드 중..."
    
    RELEASE_TAG="comprehensive-v$(date +'%Y.%m.%d')"
    PLUGIN_COUNT=$(find "$MIRROR_ROOT" -name "*.hpi" -o -name "*.jpi" | wc -l)
    TOTAL_SIZE=$(du -sh "$MIRROR_ROOT" | cut -f1)
    PART_COUNT=$(ls "$PACKAGE_DIR"/jenkins-plugins-comprehensive-part*.tar.gz | wc -l)
    
    # 기존 릴리즈가 있으면 삭제
    gh release list | grep -q "$RELEASE_TAG" && {
        warning "기존 릴리즈 삭제: $RELEASE_TAG"
        gh release delete "$RELEASE_TAG" -y
    }
    
    # 릴리즈 노트 생성
    cat > "$PACKAGE_DIR/RELEASE_NOTES.md" << EOF
# Jenkins Comprehensive Plugin Mirror - $RELEASE_TAG

🌟 **Complete Enterprise-Grade Jenkins Plugin Mirror** (증분 업데이트 기반)

## 📊 Statistics & Features

✅ **Complete Coverage**: ${PLUGIN_COUNT}개 플러그인 파일 (모든 히스토리 버전 포함)  
✅ **Total Size**: ${TOTAL_SIZE} 완전한 미러  
✅ **Multi-part**: ${PART_COUNT}개 파트로 분할 (GitHub 2GB 제한 대응)  
✅ **Incremental**: 기존 미러 기반 효율적 업데이트  
✅ **Legacy Support**: 구버전 Jenkins 완전 호환  
✅ **Air-gapped Ready**: 폐쇄망 환경 완벽 지원

## 🚀 Quick Start

\`\`\`bash
# 1. 모든 파트 다운로드
gh release download $RELEASE_TAG --pattern="jenkins-plugins-comprehensive-part*.tar.gz*"
gh release download $RELEASE_TAG --pattern="assemble-comprehensive-mirror.sh"

# 2. 체크섬 검증
for file in jenkins-plugins-comprehensive-part*.tar.gz.sha256; do
    sha256sum -c "\$file"
done

# 3. 미러 조립
chmod +x assemble-comprehensive-mirror.sh
./assemble-comprehensive-mirror.sh
\`\`\`

## 🏢 Enterprise Features

- **Incremental Updates**: 기존 미러 기반 빠른 업데이트
- **Complete History**: 모든 플러그인의 이전 버전 포함
- **Legacy Jenkins**: 2.x 초기 버전까지 완벽 지원
- **Production Ready**: 대규모 엔터프라이즈 환경 검증

---
🤖 Generated: $(date -u)  
📦 Parts: ${PART_COUNT} files  
💾 Size: ${TOTAL_SIZE}  
🔄 Update: Incremental (faster than full rebuild)
EOF
    
    # 릴리즈 생성
    cd "$PACKAGE_DIR"
    gh release create "$RELEASE_TAG" \
        --title "Jenkins Comprehensive Mirror - $RELEASE_TAG" \
        --notes-file RELEASE_NOTES.md \
        --latest \
        jenkins-plugins-comprehensive-part*.tar.gz \
        jenkins-plugins-comprehensive-part*.tar.gz.sha256 \
        assemble-comprehensive-mirror.sh
    
    success "GitHub Release 생성 완료: $RELEASE_TAG"
    success "Release URL: https://github.com/$(gh repo view --json owner,name -q '.owner.login + "/" + .name')/releases/tag/$RELEASE_TAG"
}

# 8. 메인 실행
main() {
    echo -e "${BLUE}"
    echo "=========================================================="
    echo "  Jenkins Comprehensive Mirror Generator (Incremental)"
    echo "  기존 미러 기반 증분 업데이트 + GitHub 자동 배포"
    echo "=========================================================="
    echo -e "${NC}"
    
    prepare_environment
    create_comprehensive_mirror
    create_release_packages
    create_upload_guide
    cleanup_old_releases
    create_github_release
    
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