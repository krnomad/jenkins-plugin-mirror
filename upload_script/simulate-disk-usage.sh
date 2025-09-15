#!/bin/bash

# Disk Usage Simulation for Jenkins Mirror Upload Scripts
# Usage: ./simulate-disk-usage.sh <mirror_size_gb> <compression_ratio_percent>

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
info() { echo -e "${PURPLE}💡 $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Parameters
MIRROR_SIZE_GB=${1:-42}
COMPRESSION_RATIO=${2:-30}

log "📊 Jenkins Mirror 디스크 사용량 시뮬레이션"
info "미러 크기: ${MIRROR_SIZE_GB}GB, 압축률: ${COMPRESSION_RATIO}%"

# Calculations
MIRROR_SIZE_MB=$((MIRROR_SIZE_GB * 1024))
COMPRESSED_SIZE_MB=$((MIRROR_SIZE_MB * COMPRESSION_RATIO / 100))
COMPRESSED_SIZE_GB=$((COMPRESSED_SIZE_MB / 1024))

echo
echo "════════════════════════════════════════════════════════════════"
echo "📈 방식별 디스크 사용량 비교"
echo "════════════════════════════════════════════════════════════════"

# Method 1: Original approach
TEMP_TAR_SIZE_MB=$MIRROR_SIZE_MB
TOTAL_ORIGINAL_MB=$((MIRROR_SIZE_MB + TEMP_TAR_SIZE_MB + COMPRESSED_SIZE_MB))
TOTAL_ORIGINAL_GB=$((TOTAL_ORIGINAL_MB / 1024))

echo
echo "🔴 기존 방식 (split-and-upload.sh):"
echo "   원본 미러:           ${MIRROR_SIZE_GB}GB"
echo "   임시 TAR 파일:       ${MIRROR_SIZE_GB}GB"
echo "   압축된 파트들:       ${COMPRESSED_SIZE_GB}GB"
echo "   ─────────────────────────────────"
echo "   총 필요 공간:        ${TOTAL_ORIGINAL_GB}GB"

# Method 2: Optimized approach
TEMP_BUFFER_MB=500  # Small buffer for temp files during processing
TOTAL_OPTIMIZED_MB=$((MIRROR_SIZE_MB + COMPRESSED_SIZE_MB + TEMP_BUFFER_MB))
TOTAL_OPTIMIZED_GB=$((TOTAL_OPTIMIZED_MB / 1024))

echo
echo "🟡 최적화 방식 (split-and-upload-optimized.sh):"
echo "   원본 미러:           ${MIRROR_SIZE_GB}GB"
echo "   압축된 파트들:       ${COMPRESSED_SIZE_GB}GB"
echo "   임시 버퍼:           1GB"
echo "   ─────────────────────────────────"
echo "   총 필요 공간:        ${TOTAL_OPTIMIZED_GB}GB"

# Method 3: True streaming approach  
STREAMING_BUFFER_MB=200  # Minimal buffer for named pipes
TOTAL_STREAMING_MB=$((MIRROR_SIZE_MB + COMPRESSED_SIZE_MB + STREAMING_BUFFER_MB))
TOTAL_STREAMING_GB=$((TOTAL_STREAMING_MB / 1024))

echo
echo "🟢 스트리밍 방식 (split-and-upload-streaming.sh):"
echo "   원본 미러:           ${MIRROR_SIZE_GB}GB"
echo "   압축된 파트들:       ${COMPRESSED_SIZE_GB}GB"
echo "   스트리밍 버퍼:       <1GB"
echo "   ─────────────────────────────────"
echo "   총 필요 공간:        ${TOTAL_STREAMING_GB}GB"

# Method 4: Fixed TAR-only approach (no compression)
TOTAL_TAR_ONLY_MB=$((MIRROR_SIZE_MB + MIRROR_SIZE_MB + 100))  # 원본 + TAR분할 + 최소버퍼
TOTAL_TAR_ONLY_GB=$((TOTAL_TAR_ONLY_MB / 1024))

echo
echo "🔵 수정된 방식 (split-and-upload-fixed.sh):"
echo "   원본 미러:           ${MIRROR_SIZE_GB}GB"  
echo "   TAR 분할 파트들:     ${MIRROR_SIZE_GB}GB (압축 없음)"
echo "   처리 버퍼:           <1GB"
echo "   ─────────────────────────────────"
echo "   총 필요 공간:        ${TOTAL_TAR_ONLY_GB}GB"

echo
echo "════════════════════════════════════════════════════════════════"
echo "💾 공간 효율성 분석"
echo "════════════════════════════════════════════════════════════════"

SAVINGS_OPTIMIZED=$((TOTAL_ORIGINAL_GB - TOTAL_OPTIMIZED_GB))
SAVINGS_OPTIMIZED_PCT=$(( (TOTAL_ORIGINAL_GB - TOTAL_OPTIMIZED_GB) * 100 / TOTAL_ORIGINAL_GB ))

SAVINGS_STREAMING=$((TOTAL_ORIGINAL_GB - TOTAL_STREAMING_GB))
SAVINGS_STREAMING_PCT=$(( (TOTAL_ORIGINAL_GB - TOTAL_STREAMING_GB) * 100 / TOTAL_ORIGINAL_GB ))

SAVINGS_TAR_ONLY=$((TOTAL_ORIGINAL_GB - TOTAL_TAR_ONLY_GB))
SAVINGS_TAR_ONLY_PCT=$(( (TOTAL_ORIGINAL_GB - TOTAL_TAR_ONLY_GB) * 100 / TOTAL_ORIGINAL_GB ))

echo
success "최적화 방식 절약: ${SAVINGS_OPTIMIZED}GB (${SAVINGS_OPTIMIZED_PCT}% 절약)"
success "스트리밍 방식 절약: ${SAVINGS_STREAMING}GB (${SAVINGS_STREAMING_PCT}% 절약)"
success "수정된 방식 절약: ${SAVINGS_TAR_ONLY}GB (${SAVINGS_TAR_ONLY_PCT}% 절약)"

echo
echo "════════════════════════════════════════════════════════════════"
echo "🚀 권장사항"
echo "════════════════════════════════════════════════════════════════"

if [ $TOTAL_TAR_ONLY_GB -lt 90 ]; then
    success "수정된 방식 권장: 압축 없음으로 용량 증가 방지, Jenkins 플러그인에 최적화"
elif [ $TOTAL_STREAMING_GB -lt 60 ]; then
    success "스트리밍 방식 권장: 일반적인 파일에 적합"
elif [ $TOTAL_OPTIMIZED_GB -lt 80 ]; then
    warning "최적화 방식 권장: 스트리밍이 불안정한 환경에서 사용"
else
    warning "충분한 디스크 공간 확보 필요: ${TOTAL_TAR_ONLY_GB}GB+"
fi

echo
info "Jenkins 플러그인: 수정된 방식 권장 (이미 압축된 파일)"
info "일반 파일: 스트리밍 방식 권장 (압축 효과 있음)"
info "메모리 사용량: 수정된 > 스트리밍 > 최적화 > 기존 순으로 효율적"
info "안정성: 모든 방식에서 체크섬 검증 및 오류 처리 지원"

echo
echo "🔧 실행 명령어:"
echo "   # Jenkins 플러그인 (권장):"
echo "   ./upload_script/split-and-upload-fixed.sh /path/to/mirror"
echo "   # 일반 파일:"
echo "   ./upload_script/split-and-upload-streaming.sh /path/to/mirror"