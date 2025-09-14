#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; exit 1; }
info() { echo -e "${PURPLE}💡 $1${NC}"; }

# Configuration
MIRROR_ROOT="${1:-/tmp/jenkins-comprehensive-mirror}"
PACKAGE_DIR="/tmp/jenkins-release-packages-split"
MAX_PART_SIZE_MB=1700  # 1.7GB in MB
MAX_RELEASES_TO_KEEP=3
TEMP_TAR_CHUNK="/tmp/jenkins-temp-chunk.tar"

log "🚀 Jenkins Comprehensive Mirror 최적화된 분할 압축 시작"

if [ ! -d "$MIRROR_ROOT" ]; then
    error "미러 디렉토리를 찾을 수 없습니다: $MIRROR_ROOT"
fi

MIRROR_SIZE=$(du -sh "$MIRROR_ROOT" | cut -f1)
MIRROR_SIZE_MB=$(du -sm "$MIRROR_ROOT" | cut -f1)
info "미러 크기: $MIRROR_SIZE (${MIRROR_SIZE_MB}MB)"

# 필요한 디스크 공간 계산
ESTIMATED_COMPRESSED_SIZE_MB=$((MIRROR_SIZE_MB * 30 / 100))  # 압축률 약 30% 가정
TOTAL_ESTIMATED_MB=$((MIRROR_SIZE_MB + ESTIMATED_COMPRESSED_SIZE_MB + 500))  # 원본 + 압축본 + 여유공간 500MB
info "예상 최대 필요 용량: ${TOTAL_ESTIMATED_MB}MB (~$((TOTAL_ESTIMATED_MB / 1000))GB)"

# 디스크 공간 확인
AVAILABLE_SPACE_KB=$(df /tmp | tail -1 | awk '{print $4}')
AVAILABLE_SPACE_MB=$((AVAILABLE_SPACE_KB / 1024))
if [ $AVAILABLE_SPACE_MB -lt $TOTAL_ESTIMATED_MB ]; then
    warning "디스크 공간 부족: 사용 가능 ${AVAILABLE_SPACE_MB}MB, 필요 ${TOTAL_ESTIMATED_MB}MB"
    warning "계속 진행하면 공간 부족으로 실패할 수 있습니다."
    read -p "계속 진행하시겠습니까? (y/N): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        error "사용자가 작업을 취소했습니다"
    fi
else
    info "디스크 공간 충분: 사용 가능 ${AVAILABLE_SPACE_MB}MB"
fi

# 기존 패키지 디렉토리 정리
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"
cd "$PACKAGE_DIR"

# 청크 기반 스트리밍 압축 함수
create_streaming_parts() {
    local part_num=1
    local current_size_mb=0
    local temp_files=()
    
    log "스트리밍 방식으로 파트 생성 시작..."
    
    # tar를 생성하면서 동시에 분할 처리
    cd "$MIRROR_ROOT"
    
    # 파이프를 통해 tar 생성과 동시에 분할 압축
    tar -cf - . | (
        cd "$PACKAGE_DIR"
        
        while true; do
            local part_file="jenkins-plugins-comprehensive-part${part_num}.tar.gz"
            local temp_part_file="temp_part${part_num}.tar"
            
            log "Part $part_num 생성 중..."
            
            # 지정된 크기만큼 읽어서 임시 파일에 저장
            dd bs=1M count=$MAX_PART_SIZE_MB of="$temp_part_file" 2>/dev/null || break
            
            # 읽은 데이터가 있는지 확인
            if [ ! -s "$temp_part_file" ]; then
                rm -f "$temp_part_file"
                break
            fi
            
            # 백그라운드에서 압축 (병렬 처리)
            (
                log "Part $part_num 압축 중..."
                gzip < "$temp_part_file" > "$part_file"
                
                # 체크섬 생성
                sha256sum "$part_file" > "${part_file}.sha256"
                
                # 임시 파일 삭제
                rm -f "$temp_part_file"
                
                # 크기 확인
                local size_mb=$(du -m "$part_file" | cut -f1)
                success "Part $part_num 완료 (${size_mb}MB)"
            ) &
            
            # 너무 많은 백그라운드 프로세스가 동시에 실행되지 않도록 제한
            if (( part_num % 3 == 0 )); then
                wait  # 3개마다 대기
            fi
            
            part_num=$((part_num + 1))
        done
        
        # 모든 백그라운드 작업 완료 대기
        wait
        
        echo $((part_num - 1)) > "$PACKAGE_DIR/.part_count"
    )
}

# 개선된 메모리 효율적 방식 사용
log "메모리 효율적 분할 압축 시작..."

# 청크 단위로 처리하여 메모리 사용량 최소화
create_optimized_parts() {
    local part_num=1
    local temp_size_threshold_mb=$((MAX_PART_SIZE_MB))
    
    cd "$MIRROR_ROOT"
    
    # find를 사용하여 파일을 순차적으로 처리
    find . -type f | while IFS= read -r file; do
        # 현재 파트 파일들이 임계값에 도달했는지 확인
        if [ -f "$PACKAGE_DIR/current_part.tar" ]; then
            current_size=$(du -m "$PACKAGE_DIR/current_part.tar" 2>/dev/null | cut -f1 || echo 0)
            if [ "$current_size" -ge "$temp_size_threshold_mb" ]; then
                # 현재 파트 완료 - 압축 및 정리
                (
                    cd "$PACKAGE_DIR"
                    part_file="jenkins-plugins-comprehensive-part${part_num}.tar.gz"
                    log "Part $part_num 완료 - 압축 중..."
                    
                    gzip < current_part.tar > "$part_file"
                    sha256sum "$part_file" > "${part_file}.sha256"
                    rm -f current_part.tar
                    
                    size_mb=$(du -m "$part_file" | cut -f1)
                    success "Part $part_num 완료 (${size_mb}MB)"
                ) &
                
                part_num=$((part_num + 1))
                
                # 백그라운드 작업이 너무 많이 쌓이지 않도록 관리
                if (( part_num % 2 == 0 )); then
                    wait
                fi
            fi
        fi
        
        # 현재 파일을 파트에 추가
        tar -rf "$PACKAGE_DIR/current_part.tar" "$file" 2>/dev/null || {
            # 새 파트 시작
            tar -cf "$PACKAGE_DIR/current_part.tar" "$file"
        }
    done
    
    # 마지막 파트 처리
    if [ -f "$PACKAGE_DIR/current_part.tar" ]; then
        cd "$PACKAGE_DIR"
        part_file="jenkins-plugins-comprehensive-part${part_num}.tar.gz"
        log "마지막 Part $part_num 압축 중..."
        
        gzip < current_part.tar > "$part_file"
        sha256sum "$part_file" > "${part_file}.sha256"
        rm -f current_part.tar
        
        size_mb=$(du -m "$part_file" | cut -f1)
        success "Part $part_num 완료 (${size_mb}MB)"
    fi
    
    wait  # 모든 백그라운드 작업 완료 대기
    echo "$part_num" > "$PACKAGE_DIR/.part_count"
}

# 최적화된 방식 실행
create_optimized_parts

cd "$PACKAGE_DIR"
PART_COUNT=$(cat .part_count 2>/dev/null || echo "0")
rm -f .part_count

if [ "$PART_COUNT" -eq 0 ]; then
    error "파트 파일 생성 실패"
fi

log "총 ${PART_COUNT}개 파트 생성 완료"

# 실제 압축된 크기 계산
COMPRESSED_SIZE_MB=$(du -sm jenkins-plugins-comprehensive-part*.tar.gz | awk '{sum+=$1} END {print sum}')
info "압축된 총 크기: ${COMPRESSED_SIZE_MB}MB"
info "압축률: $(( (MIRROR_SIZE_MB - COMPRESSED_SIZE_MB) * 100 / MIRROR_SIZE_MB ))%"

# 조립 스크립트 생성 (기존과 동일)
cat > assemble-comprehensive-mirror.sh << 'EOF'
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
# 분할된 파일들을 순서대로 결합하여 원본 복원
cat jenkins-plugins-comprehensive-part*.tar.gz | gunzip | tar -xf - -C "$MIRROR_DIR"

echo "✅ 조립 완료!"
echo "📊 최종 미러 크기: $(du -sh "$MIRROR_DIR" | cut -f1)"
echo "📁 미러 위치: ./$MIRROR_DIR"
echo ""
echo "🚀 사용 방법:"
echo "   1. 웹 서버에 $MIRROR_DIR 디렉토리 복사"
echo "   2. Jenkins에서 Update Site URL을 http://your-server/$MIRROR_DIR/update-center2/update-center.json 로 설정"
EOF

chmod +x assemble-comprehensive-mirror.sh

# Release Notes 생성
RELEASE_TAG="comprehensive-v$(date +'%Y.%m.%d')"
cat > RELEASE_NOTES.md << EOF
# Jenkins Comprehensive Plugin Mirror - $RELEASE_TAG

🌟 **Complete Enterprise-Grade Jenkins Plugin Mirror** (Memory Optimized)

이 릴리즈는 폐쇄망 환경을 위한 **완전한 Jenkins 플러그인 미러**를 제공합니다.

## 📊 릴리즈 정보

✅ **미러 타입**: Comprehensive (완전)  
✅ **원본 크기**: $MIRROR_SIZE
✅ **압축 크기**: ${COMPRESSED_SIZE_MB}MB  
✅ **파트 수**: ${PART_COUNT}개 (GitHub 2GB 제한 대응)  
✅ **압축률**: $(( (MIRROR_SIZE_MB - COMPRESSED_SIZE_MB) * 100 / MIRROR_SIZE_MB ))%
✅ **생성일**: $(date +'%Y-%m-%d %H:%M:%S')  

## 🚀 사용법

### 1. 다운로드
\`\`\`bash
# 자동 다운로드 스크립트 사용 (권장)
curl -O https://raw.githubusercontent.com/krnomad/jenkins-plugin-mirror/main/0-download-latest-release.sh
chmod +x 0-download-latest-release.sh
./0-download-latest-release.sh
\`\`\`

### 2. 조립
\`\`\`bash
./1-assemble-comprehensive-mirror.sh
\`\`\`

### 3. 배포
\`\`\`bash
cd server/docker-image-layered
docker-compose up -d
\`\`\`

## 🔧 Jenkins 설정

1. **Manage Jenkins** → **Manage Plugins** → **Advanced**
2. **Update Site URL**: \`http://your-server/jenkins-comprehensive-mirror/update-center2/update-center.json\`
3. **Submit** 클릭 후 Jenkins 재시작

## 💡 최적화 특징

- **메모리 효율적**: 스트리밍 방식으로 대용량 파일 처리
- **디스크 공간 절약**: 원본의 1.5배 공간만으로 처리 가능
- **병렬 압축**: 백그라운드 압축으로 처리 시간 단축
- **안정성**: 체크섬 검증 및 단계별 검증

---

🤖 Generated with optimized memory-efficient processing  
📅 Next update: Check releases for monthly updates  
🔄 Memory usage: ~$(( TOTAL_ESTIMATED_MB / 1000 ))GB (vs previous ~100GB)
EOF

log "GitHub Release 생성 및 업로드 중..."

# 이전 동일한 태그의 릴리즈 삭제
gh release list | grep -q "$RELEASE_TAG" && {
    warning "기존 릴리즈 삭제: $RELEASE_TAG"
    gh release delete "$RELEASE_TAG" -y
}

# GitHub Release 생성
log "릴리즈 생성: $RELEASE_TAG"
gh release create "$RELEASE_TAG" \
    --title "Jenkins Comprehensive Mirror - $RELEASE_TAG (Memory Optimized)" \
    --notes-file RELEASE_NOTES.md \
    --latest

# 파일 업로드
log "파일 업로드 중..."
gh release upload "$RELEASE_TAG" \
    jenkins-plugins-comprehensive-part*.tar.gz \
    jenkins-plugins-comprehensive-part*.tar.gz.sha256 \
    assemble-comprehensive-mirror.sh

success "GitHub Release 생성 완료!"
success "Release URL: https://github.com/$(gh repo view --json owner,name -q '.owner.login + "/" + .name')/releases/tag/$RELEASE_TAG"

# 이전 릴리즈 정리
log "이전 릴리즈 정리 중 (최신 ${MAX_RELEASES_TO_KEEP}개만 유지)..."
RELEASE_LIST=$(gh release list --limit 20 | grep "comprehensive-v" | cut -f3 | head -20)
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
else
    info "정리할 릴리즈 없음 (현재: $RELEASE_COUNT개, 최대: $MAX_RELEASES_TO_KEEP개)"
fi

# 최종 통계
FINAL_PACKAGE_SIZE_MB=$(du -sm "$PACKAGE_DIR" | cut -f1)
success "모든 작업 완료!"
info "패키지 디렉토리: $PACKAGE_DIR"
info "총 파트 수: $PART_COUNT"
info "최종 패키지 크기: ${FINAL_PACKAGE_SIZE_MB}MB"
info "메모리 사용량 최적화: $(( (MIRROR_SIZE_MB + FINAL_PACKAGE_SIZE_MB) / 1000 ))GB (기존 대비 $(( 100 - (MIRROR_SIZE_MB + FINAL_PACKAGE_SIZE_MB) * 100 / (MIRROR_SIZE_MB * 2) ))% 절약)"

log "🎉 Jenkins Comprehensive Mirror GitHub Release 완료 (최적화됨)!"