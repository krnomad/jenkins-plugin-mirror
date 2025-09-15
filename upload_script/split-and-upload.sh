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
MIRROR_ROOT="${1:-/var/www/jenkins-mirror}"
PACKAGE_DIR="/tmp/jenkins-release-packages-fixed"
MAX_PART_SIZE_MB=1700  # 1.7GB to stay under GitHub 2GB limit
MAX_RELEASES_TO_KEEP=3

# Git repository 정보 저장 (GitHub CLI를 위해)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_OWNER="krnomad"
REPO_NAME="jenkins-plugin-mirror"

log "🚀 Jenkins Comprehensive Mirror 수정된 분할 처리 시작"

if [ ! -d "$MIRROR_ROOT" ]; then
    error "미러 디렉토리를 찾을 수 없습니다: $MIRROR_ROOT"
fi

MIRROR_SIZE=$(du -sh "$MIRROR_ROOT" | cut -f1)
MIRROR_SIZE_MB=$(du -sm "$MIRROR_ROOT" | cut -f1)
info "미러 크기: $MIRROR_SIZE (${MIRROR_SIZE_MB}MB)"

# 플러그인 파일 분석
PLUGIN_COUNT=$(find "$MIRROR_ROOT" -name "*.hpi" -o -name "*.jpi" | wc -l)
info "플러그인 파일 개수: ${PLUGIN_COUNT}개"

# 필요한 디스크 공간 계산 (압축 없이)
TOTAL_NEEDED_MB=$((MIRROR_SIZE_MB + MIRROR_SIZE_MB + 500))  # 원본 + 분할본 + 여유공간
info "예상 최대 필요 용량: ${TOTAL_NEEDED_MB}MB (~$((TOTAL_NEEDED_MB / 1000))GB) - 압축 없음"

# 디스크 공간 확인
AVAILABLE_SPACE_KB=$(df /tmp | tail -1 | awk '{print $4}')
AVAILABLE_SPACE_MB=$((AVAILABLE_SPACE_KB / 1024))
if [ $AVAILABLE_SPACE_MB -lt $TOTAL_NEEDED_MB ]; then
    warning "디스크 공간 부족: 사용 가능 ${AVAILABLE_SPACE_MB}MB, 필요 ${TOTAL_NEEDED_MB}MB"
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

# TAR 분할 (압축 없음) - 이미 압축된 플러그인 파일이므로
create_tar_parts() {
    local part_num=1
    local max_size_bytes=$((MAX_PART_SIZE_MB * 1024 * 1024))
    
    log "TAR 분할 처리 시작 (압축 없음)..."
    
    cd "$MIRROR_ROOT"
    
    # tar를 생성하면서 동시에 크기 제한으로 분할
    tar -cf - . | split -b ${MAX_PART_SIZE_MB}M - "$PACKAGE_DIR/jenkins-plugins-comprehensive-part"
    
    cd "$PACKAGE_DIR"
    
    # 분할된 파일들을 적절한 이름으로 변경하고 체크섬 생성
    for temp_part in jenkins-plugins-comprehensive-part*; do
        if [ -f "$temp_part" ]; then
            part_file="jenkins-plugins-comprehensive-part${part_num}.tar"
            log "Part $part_num 처리 중..."
            
            # 파일명 변경
            mv "$temp_part" "$part_file"
            
            # 체크섬 생성
            sha256sum "$part_file" > "${part_file}.sha256" &
            
            size_mb=$(du -m "$part_file" | cut -f1)
            success "Part $part_num 완료 (${size_mb}MB)"
            
            part_num=$((part_num + 1))
        fi
    done
    
    wait  # 모든 체크섬 작업 완료 대기
    echo $((part_num - 1)) > "$PACKAGE_DIR/.part_count"
}

# TAR 분할 실행
create_tar_parts

cd "$PACKAGE_DIR"
PART_COUNT=$(cat .part_count 2>/dev/null || echo "0")
rm -f .part_count

if [ "$PART_COUNT" -eq 0 ]; then
    error "파트 파일 생성 실패"
fi

log "총 ${PART_COUNT}개 파트 생성 완료"

# 실제 분할된 크기 계산 (안전하게)
if ls jenkins-plugins-comprehensive-part*.tar 1> /dev/null 2>&1; then
    TOTAL_PARTS_SIZE_MB=$(du -sm jenkins-plugins-comprehensive-part*.tar | awk '{sum+=$1} END {print sum}')
    info "분할된 총 크기: ${TOTAL_PARTS_SIZE_MB}MB"
    
    # 0으로 나누기 방지
    if [ "$MIRROR_SIZE_MB" -gt 0 ]; then
        OVERHEAD_PCT=$(( (TOTAL_PARTS_SIZE_MB - MIRROR_SIZE_MB) * 100 / MIRROR_SIZE_MB ))
        if [ "$OVERHEAD_PCT" -gt 0 ]; then
            warning "분할 오버헤드: +${OVERHEAD_PCT}%"
        else
            info "분할 효율성: ${OVERHEAD_PCT}% (거의 동일)"
        fi
    else
        warning "원본 크기를 확인할 수 없습니다"
    fi
else
    error "파트 파일을 찾을 수 없습니다"
fi

# 각 파트 크기 검증
log "파트 크기 검증 중..."
for part_file in jenkins-plugins-comprehensive-part*.tar; do
    if [ -f "$part_file" ]; then
        part_size_mb=$(du -m "$part_file" | cut -f1)
        if [ "$part_size_mb" -gt 1800 ]; then  # 1.8GB 제한
            warning "⚠️  $part_file: ${part_size_mb}MB (GitHub 2GB 제한 근접)"
        else
            info "✅ $part_file: ${part_size_mb}MB (OK)"
        fi
    fi
done

# 조립 스크립트 생성 (TAR 파일용)
cat > assemble-comprehensive-mirror.sh << 'EOF'
#!/bin/bash
set -e

echo "🔧 Jenkins Comprehensive Mirror 조립 중..."

# 모든 파트가 있는지 확인
PARTS=(jenkins-plugins-comprehensive-part*.tar)
if [ ${#PARTS[@]} -eq 0 ]; then
    echo "❌ 파트 파일을 찾을 수 없습니다"
    exit 1
fi

echo "📦 발견된 파트: ${#PARTS[@]}개"

# 체크섬 검증
echo "🔍 체크섬 검증 중..."
for file in jenkins-plugins-comprehensive-part*.tar; do
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
# TAR 파일들을 순서대로 결합하여 원본 복원
cat jenkins-plugins-comprehensive-part*.tar | tar -xf - -C "$MIRROR_DIR"

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

🌟 **Complete Enterprise-Grade Jenkins Plugin Mirror** (Fixed TAR Split)

이 릴리즈는 폐쇄망 환경을 위한 **완전한 Jenkins 플러그인 미러**를 제공합니다.

## 📊 릴리즈 정보

✅ **미러 타입**: Comprehensive (완전)  
✅ **원본 크기**: $MIRROR_SIZE
✅ **분할 크기**: ${TOTAL_PARTS_SIZE_MB}MB  
✅ **파트 수**: ${PART_COUNT}개 (GitHub 2GB 제한 대응)  
✅ **처리 방식**: TAR 분할 (압축 없음)
✅ **생성일**: $(date +'%Y-%m-%d %H:%M:%S')  

## 💡 최적화 특징

- **압축 없음**: 이미 압축된 플러그인 파일(.hpi/.jpi)을 다시 압축하지 않음
- **용량 효율**: 불필요한 재압축으로 인한 용량 증가 방지
- **GitHub 호환**: 각 파트가 2GB 제한 준수
- **안정성**: 체크섬 검증 및 단계별 검증

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
./assemble-comprehensive-mirror.sh
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

---

🤖 Generated with fixed TAR splitting (no re-compression)  
📅 Next update: Check releases for monthly updates  
🔄 Space efficiency: No compression overhead for pre-compressed plugins
EOF

log "GitHub Release 생성 및 업로드 중..."

# GitHub CLI를 위해 repository 정보를 명시적으로 지정
export GH_REPO="${REPO_OWNER}/${REPO_NAME}"

# 이전 동일한 태그의 릴리즈 삭제
gh release list --repo "$GH_REPO" | grep -q "$RELEASE_TAG" && {
    warning "기존 릴리즈 삭제: $RELEASE_TAG"
    gh release delete "$RELEASE_TAG" -y --repo "$GH_REPO"
}

# GitHub Release 생성
log "릴리즈 생성: $RELEASE_TAG"
gh release create "$RELEASE_TAG" \
    --repo "$GH_REPO" \
    --title "Jenkins Comprehensive Mirror - $RELEASE_TAG (Fixed TAR Split)" \
    --notes-file RELEASE_NOTES.md \
    --latest

# 파일 업로드
log "파일 업로드 중..."
gh release upload "$RELEASE_TAG" \
    --repo "$GH_REPO" \
    jenkins-plugins-comprehensive-part*.tar \
    jenkins-plugins-comprehensive-part*.tar.sha256 \
    assemble-comprehensive-mirror.sh

success "GitHub Release 생성 완료!"
success "Release URL: https://github.com/${GH_REPO}/releases/tag/$RELEASE_TAG"

# 이전 릴리즈 정리
log "이전 릴리즈 정리 중 (최신 ${MAX_RELEASES_TO_KEEP}개만 유지)..."
RELEASE_LIST=$(gh release list --repo "$GH_REPO" --limit 20 | grep "comprehensive-v" | cut -f3 | head -20)
RELEASE_COUNT=$(echo "$RELEASE_LIST" | wc -l)

if [ $RELEASE_COUNT -gt $MAX_RELEASES_TO_KEEP ]; then
    RELEASES_TO_DELETE=$(echo "$RELEASE_LIST" | tail -n +$((MAX_RELEASES_TO_KEEP + 1)))
    info "발견된 comprehensive 릴리즈: $RELEASE_COUNT개"
    info "유지할 릴리즈: $MAX_RELEASES_TO_KEEP개"  
    info "삭제할 릴리즈: $(echo "$RELEASES_TO_DELETE" | wc -l)개"
    
    echo "$RELEASES_TO_DELETE" | while read release_tag; do
        if [ -n "$release_tag" ]; then
            log "이전 릴리즈 삭제 중: $release_tag"
            gh release delete "$release_tag" -y --repo "$GH_REPO" 2>/dev/null || warning "릴리즈 삭제 실패: $release_tag"
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
info "공간 효율성: $(( FINAL_PACKAGE_SIZE_MB / 1000 ))GB 사용 (압축 없음으로 용량 증가 방지)"

log "🎉 Jenkins Comprehensive Mirror GitHub Release 완료 (수정됨)!"