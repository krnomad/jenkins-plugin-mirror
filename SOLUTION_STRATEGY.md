# Jenkins Plugin Mirror - 28GB 문제 해결 전략

## 🎯 3단계 해결 방안

### Phase 1: 스마트 필터링 (즉시 구현)

#### 📋 필터링 전략:
1. **파일 크기 제한**: 200MB 초과 파일 제외
2. **버전 제한**: 플러그인당 최대 3개 버전만 보관
3. **청크 크기 최적화**: 800MB로 축소

#### 📊 예상 효과:
- **28GB → 약 8-12GB** (60% 감소)
- **3,851개 → 약 1,500-2,000개** 플러그인
- **19개 → 약 10-15개** 청크

### Phase 2: 다중 미러 옵션

#### 🏷️ 미러 타입별 전략:

1. **`dry-run`**: 테스트용 (5개 플러그인)
   - 실행 시간: ~2-3분
   - 크기: ~10MB

2. **`essential-only`**: 실용적 미러 (기본값)
   - 200MB 미만, 최신 3버전만
   - 실행 시간: ~30-45분  
   - 크기: ~8-12GB

3. **`full-filtered`**: 완전한 미러
   - 크기/버전 필터링만 적용
   - 실행 시간: ~60-90분
   - 크기: ~15-20GB

### Phase 3: 성능 최적화

#### ⚡ 워크플로우 최적화:
1. **선택적 디스크 정리**: 필요한 청크에서만 실행
2. **청크 존재 검사**: 빈 청크 스킵
3. **병렬 처리**: 최대 15개 청크 동시 처리
4. **최적화된 아티팩트**: 빈 파일/폴더 자동 제거

## 🔧 구현된 개선사항

### 새로운 스크립트:
- `01-generate-plugin-list-smart.sh`: Python 기반 스마트 필터링
- `.github/workflows/mirror-optimized.yml`: 최적화된 워크플로우

### 주요 기능:
1. **버전 파싱**: semantic versioning 지원
2. **크기 기반 청킹**: 실제 파일 크기 고려
3. **통계 리포팅**: 릴리즈별 상세 정보
4. **유연한 구성**: 3가지 미러 타입 선택

## 📈 예상 성능 개선

| 미러 타입 | 크기 | 플러그인 수 | 실행시간 | GitHub 적합성 |
|-----------|------|-------------|----------|---------------|
| dry-run | ~10MB | 5개 | ~2분 | ✅ 완벽 |
| essential-only | ~10GB | ~1,500개 | ~40분 | ✅ 권장 |
| full-filtered | ~18GB | ~2,500개 | ~90분 | ⚠️ 도전적 |
| 원본 (28GB) | 28GB | 3,851개 | ~3시간+ | ❌ 불가능 |

## 🎪 사용법

### 1. 기본 실행 (권장):
```bash
gh workflow run mirror-optimized.yml --ref main -f mirror_type=essential-only
```

### 2. 테스트 실행:
```bash
gh workflow run mirror-optimized.yml --ref main -f mirror_type=dry-run
```

### 3. 완전한 미러 (신중하게):
```bash
gh workflow run mirror-optimized.yml --ref main -f mirror_type=full-filtered
```

## 🚀 마이그레이션 가이드

1. **기존 워크플로우 백업**
2. **새 워크플로우 테스트** (`dry-run`)
3. **실용적 미러 배포** (`essential-only`)
4. **필요시 전체 미러** (`full-filtered`)

이 전략으로 GitHub Actions 제한 내에서 **실용적인 Jenkins Plugin Mirror**를 구축할 수 있습니다!