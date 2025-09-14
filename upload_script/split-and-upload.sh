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
PACKAGE_DIR="/tmp/jenkins-release-packages-split"
MAX_PART_SIZE_GB=1.7  # GitHub 2GB 제한을 고려하여 1.7GB로 설정
MAX_RELEASES_TO_KEEP=3

log "🚀 Jenkins Comprehensive Mirror 분할 압축 시작"

if [ ! -d "$MIRROR_ROOT" ]; then
    error "미러 디렉토리를 찾을 수 없습니다: $MIRROR_ROOT"
fi

MIRROR_SIZE=$(du -sh "$MIRROR_ROOT" | cut -f1)
info "미러 크기: $MIRROR_SIZE"

# 기존 패키지 디렉토리 정리
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"
cd "$PACKAGE_DIR"

# 먼저 전체 미러를 하나의 tar로 만들고 분할
log "미러 전체를 tar 아카이브로 생성 중..."
cd "$MIRROR_ROOT"
tar -cf "$PACKAGE_DIR/jenkins-comprehensive-mirror.tar" .

cd "$PACKAGE_DIR"
TOTAL_SIZE_MB=$(du -m jenkins-comprehensive-mirror.tar | cut -f1)
PART_SIZE_MB=$((1700))  # 1.7GB in MB
TOTAL_PARTS=$(( (TOTAL_SIZE_MB + PART_SIZE_MB - 1) / PART_SIZE_MB ))

log "전체 크기: ${TOTAL_SIZE_MB}MB"
log "예상 파트 수: $TOTAL_PARTS"

# tar 파일을 여러 부분으로 분할
log "아카이브를 ${TOTAL_PARTS}개 파트로 분할 중..."
split -b ${PART_SIZE_MB}M jenkins-comprehensive-mirror.tar jenkins-plugins-comprehensive-part-

# 분할된 파일들의 이름을 변경하고 압축
part_num=1
for file in jenkins-plugins-comprehensive-part-*; do
    if [ -f "$file" ]; then
        new_name="jenkins-plugins-comprehensive-part${part_num}.tar.gz"
        log "압축 중: $new_name"
        
        # gzip으로 압축
        gzip -c "$file" > "$new_name"
        
        # 체크섬 생성
        sha256sum "$new_name" > "${new_name}.sha256"
        
        # 파일 크기 확인
        size_mb=$(du -m "$new_name" | cut -f1)
        log "완료: part${part_num} (크기: ${size_mb}MB)"
        
        # 원본 분할 파일 삭제
        rm "$file"
        
        part_num=$((part_num + 1))
    fi
done

# 원본 tar 파일 삭제
rm jenkins-comprehensive-mirror.tar
PART_COUNT=$((part_num - 1))

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

success "모든 작업 완료!"
info "패키지 디렉토리: $PACKAGE_DIR"
info "총 파트 수: $PART_COUNT"

log "🎉 Jenkins Comprehensive Mirror GitHub Release 완료!"