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
MIRROR_ROOT="/tmp/jenkins-comprehensive-mirror"
PACKAGE_DIR="/tmp/jenkins-release-packages"
MAX_PART_SIZE_GB=1.8  # GitHub 2GB 제한 고려 (1.8GB = 1843MB)
MAX_PART_SIZE_MB=$((MAX_PART_SIZE_GB * 1000))  # MB로 변환
MAX_RELEASES_TO_KEEP=3

log "🚀 Jenkins Comprehensive Mirror GitHub Release 패키징 시작"

# 환경 확인
if [ ! -d "$MIRROR_ROOT" ]; then
    error "미러 디렉토리를 찾을 수 없습니다: $MIRROR_ROOT"
fi

MIRROR_SIZE=$(du -sh "$MIRROR_ROOT" | cut -f1)
info "미러 크기: $MIRROR_SIZE"

# 패키징 디렉토리 준비
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"
cd "$PACKAGE_DIR"

log "GitHub Release용 멀티파트 패키징 중..."

# 플러그인 파일 크기 순으로 정렬하여 효율적 패킹
find "$MIRROR_ROOT/download/plugins" -name "*.hpi" -o -name "*.jpi" | while read filepath; do
    size_mb=$(du -m "$filepath" | cut -f1)
    echo "$size_mb $filepath"
done | sort -nr > /tmp/plugin_sizes.txt

# 멀티파트 패키징
part_num=1
current_size=0
current_part_dir="$PACKAGE_DIR/part${part_num}"

mkdir -p "$current_part_dir/download/plugins"
cp -r "$MIRROR_ROOT/update-center2" "$current_part_dir/"

while read size_mb filepath; do
    # 새 파트가 필요한지 확인
    if [ $((current_size + size_mb)) -gt $MAX_PART_SIZE_MB ] && [ $current_size -gt 0 ]; then
        log "Part $part_num: ${current_size}MB 완료"
        
        part_num=$((part_num + 1))
        current_size=0
        current_part_dir="$PACKAGE_DIR/part${part_num}"
        
        mkdir -p "$current_part_dir/download/plugins"
        cp -r "$MIRROR_ROOT/update-center2" "$current_part_dir/"
    fi
    
    # 플러그인 디렉토리 구조 유지하며 복사
    plugin_name=$(basename $(dirname "$filepath"))
    mkdir -p "$current_part_dir/download/plugins/$plugin_name"
    cp "$filepath" "$current_part_dir/download/plugins/$plugin_name/"
    
    current_size=$((current_size + size_mb))
done < /tmp/plugin_sizes.txt

log "Part $part_num: ${current_size}MB 완료"
PART_COUNT=$part_num

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
        
        # GitHub 2GB 제한 확인
        if [ $compressed_size -gt 2000 ]; then
            warning "파트가 2GB를 초과합니다: $compressed_size MB"
        fi
        
        # 작업 디렉토리 정리
        rm -rf "$part_dir"
    fi
done

# 조립 스크립트 생성
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

# 체크섬 검증 (선택사항)
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

# 모든 파트 압축 해제 및 병합
echo "🔄 파트 병합 중..."
for part_file in jenkins-plugins-comprehensive-part*.tar.gz; do
    echo "압축 해제: $part_file"
    tar -xzf "$part_file" -C "$MIRROR_DIR"
done

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

🌟 **Complete Enterprise-Grade Jenkins Plugin Mirror**

이 릴리즈는 폐쇄망 환경을 위한 **완전한 Jenkins 플러그인 미러**를 제공합니다.

## 📊 릴리즈 정보

✅ **미러 타입**: Comprehensive (완전)  
✅ **총 크기**: ~$MIRROR_SIZE (압축 전)  
✅ **파트 수**: ${PART_COUNT}개 (GitHub 2GB 제한 대응)  
✅ **플러그인 수**: $(find "$MIRROR_ROOT/download/plugins" -name "*.hpi" -o -name "*.jpi" | wc -l)개  
✅ **생성일**: $(date +'%Y-%m-%d %H:%M:%S')  

## 🚀 사용법

### 1. 다운로드
\`\`\`bash
# 모든 파트와 조립 스크립트 다운로드
gh release download $RELEASE_TAG
\`\`\`

### 2. 조립
\`\`\`bash
# 체크섬 검증 (권장)
for file in jenkins-plugins-comprehensive-part*.tar.gz.sha256; do
    sha256sum -c "\$file"
done

# 미러 조립
chmod +x assemble-comprehensive-mirror.sh
./assemble-comprehensive-mirror.sh
\`\`\`

### 3. 배포
Docker 사용:
\`\`\`bash
cd server/docker-image-layered
# docker-compose.yml 수정 후
docker-compose up -d
\`\`\`

수동 배포:
\`\`\`bash
sudo cp -r jenkins-comprehensive-mirror /var/www/
# Nginx 설정
\`\`\`

## 🔧 Jenkins 설정

1. **Manage Jenkins** → **Manage Plugins** → **Advanced**
2. **Update Site URL**: \`http://your-server/jenkins-comprehensive-mirror/update-center2/update-center.json\`
3. **Submit** 클릭 후 Jenkins 재시작

## 💡 특징

- **폐쇄망 지원**: 인터넷 연결 없이 플러그인 설치
- **레거시 호환**: 구버전 Jenkins와 플러그인 지원  
- **기업용**: 보안이 중요한 환경에 최적화
- **고가용성**: 로컬 플러그인 저장소로 안정성 확보

---

🤖 Generated with enhanced incremental mirroring  
📅 Next update: Check releases for monthly updates  
🔄 Incremental update: Only new/changed plugins downloaded
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
    --title "Jenkins Comprehensive Mirror - $RELEASE_TAG" \
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
else
    info "정리할 릴리즈 없음 (현재: $RELEASE_COUNT개, 최대: $MAX_RELEASES_TO_KEEP개)"
fi

# 정리
rm -f /tmp/plugin_sizes.txt

success "모든 작업 완료!"
info "패키지 디렉토리: $PACKAGE_DIR"
info "총 파트 수: $PART_COUNT"

log "🎉 Jenkins Comprehensive Mirror GitHub Release 완료!"