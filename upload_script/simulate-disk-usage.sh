#!/bin/bash

# 용량 시뮬레이션 스크립트
echo "🧮 Jenkins Plugin Mirror 분할 압축 용량 시뮬레이션"
echo "=================================================="

# 입력 파라미터
ORIGINAL_SIZE_GB=${1:-42}  # 기본값 42GB
COMPRESSION_RATIO=${2:-30} # 기본 압축률 30%

echo "📊 입력 조건:"
echo "  - 원본 미러 크기: ${ORIGINAL_SIZE_GB}GB"
echo "  - 예상 압축률: ${COMPRESSION_RATIO}%"
echo ""

# 계산
ORIGINAL_SIZE_MB=$((ORIGINAL_SIZE_GB * 1000))
COMPRESSED_SIZE_MB=$((ORIGINAL_SIZE_MB * COMPRESSION_RATIO / 100))
OVERHEAD_MB=500  # 임시 파일 및 여유공간

echo "💾 용량 시뮬레이션 결과:"
echo "=================================================="

echo ""
echo "🔴 기존 방식 (split-and-upload.sh):"
echo "  1. 원본 미러:           ${ORIGINAL_SIZE_GB}GB"
echo "  2. 전체 TAR 파일:       ${ORIGINAL_SIZE_GB}GB (임시)"
echo "  3. 분할된 TAR 파일들:   ${ORIGINAL_SIZE_GB}GB (임시)" 
echo "  4. 압축된 분할 파일들:  $((COMPRESSED_SIZE_MB / 1000))GB"
echo "  ────────────────────────────────────────"
echo "  💥 최대 필요 용량:      $((ORIGINAL_SIZE_GB * 3 + COMPRESSED_SIZE_MB / 1000))GB"
echo ""

echo "🟢 개선된 방식 (split-and-upload-optimized.sh):"
echo "  1. 원본 미러:           ${ORIGINAL_SIZE_GB}GB"
echo "  2. 스트리밍 처리:"
echo "     - 임시 청크:         1.7GB (최대 1개)"
echo "     - 진행중인 압축:     0.5GB (평균)"
echo "  3. 압축된 분할 파일들:  $((COMPRESSED_SIZE_MB / 1000))GB"
echo "  4. 여유 공간:           0.5GB"
echo "  ────────────────────────────────────────"
echo "  💚 최대 필요 용량:      $((ORIGINAL_SIZE_GB + COMPRESSED_SIZE_MB / 1000 + 3))GB"
echo ""

echo "📈 개선 효과:"
OLD_TOTAL=$((ORIGINAL_SIZE_GB * 3 + COMPRESSED_SIZE_MB / 1000))
NEW_TOTAL=$((ORIGINAL_SIZE_GB + COMPRESSED_SIZE_MB / 1000 + 3))
SAVINGS=$((OLD_TOTAL - NEW_TOTAL))
SAVINGS_PERCENT=$(( (OLD_TOTAL - NEW_TOTAL) * 100 / OLD_TOTAL ))

echo "  💾 절약된 용량:        ${SAVINGS}GB"
echo "  📊 절약률:             ${SAVINGS_PERCENT}%"
echo "  🎯 효율성 개선:        $(( OLD_TOTAL * 100 / NEW_TOTAL ))배 → 1배"
echo ""

# 다양한 시나리오 테스트
echo "📋 다양한 시나리오별 필요 용량:"
echo "=================================================="
printf "%-12s %-15s %-15s %-10s\n" "원본크기" "기존방식" "개선방식" "절약률"
echo "────────────────────────────────────────────────────"

for size in 20 30 42 50 60; do
    old_need=$((size * 3 + size * COMPRESSION_RATIO / 100 / 1000))
    new_need=$((size + size * COMPRESSION_RATIO / 100 / 1000 + 3))
    saving_pct=$(( (old_need - new_need) * 100 / old_need ))
    printf "%-12s %-15s %-15s %-10s\n" "${size}GB" "${old_need}GB" "${new_need}GB" "${saving_pct}%"
done

echo ""
echo "🔧 실제 테스트 명령어:"
echo "  # 현재 디스크 공간 확인"
echo "  df -h /tmp"
echo ""
echo "  # 최적화된 스크립트 실행"
echo "  ./upload_script/split-and-upload-optimized.sh /path/to/mirror"
echo ""
echo "💡 권장사항:"
echo "  - 42GB 미러의 경우 최소 ${NEW_TOTAL}GB 여유 공간 확보"
echo "  - /tmp 디렉토리에 충분한 공간이 있는지 확인"
echo "  - SSD 사용시 더 빠른 처리 가능"