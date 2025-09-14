# Jenkins Plugin Mirror

이 저장소는 Jenkins 플러그인 미러 시스템을 제공합니다. 폐쇄망 환경에서 안정적으로 Jenkins 플러그인을 관리하고, 정기적인 업데이트를 지원합니다.

## 📋 사용자별 워크플로우

### 👤 일반 사용자 (미러 서버 구축)

대부분의 사용자가 해당하는 시나리오입니다.

#### 🌐 **온라인 환경 (권장)**
인터넷 연결이 가능한 환경에서 미러 서버를 구축하고 운영하는 경우:

**1단계: 최초 미러 구축**
```bash
# 미러 다운로드
./0-download-latest-release.sh

# 미러 조립
./1-assemble-comprehensive-mirror.sh
```

**2단계: 미러 서버 배포**
```bash
# Docker를 사용한 배포 (권장)
cd server/docker-image-layered
docker-compose up -d
```

**3단계: 정기 업데이트 (월 1회 권장)**
```bash
# 증분 업데이트 실행
./2-local-comprehensive-mirror.sh
```

#### 🔒 **폐쇄망 환경**
인터넷 연결이 제한된 환경에서 미러를 구축하는 경우:

**최초 구축 및 모든 업데이트:**
```bash
# 1. 인터넷 가능한 환경에서 다운로드
./0-download-latest-release.sh
./1-assemble-comprehensive-mirror.sh

# 2. 생성된 jenkins-comprehensive-mirror 디렉토리를 폐쇄망으로 이전

# 3. 폐쇄망에서 미러 서버 배포
cd server/docker-image-layered
docker-compose up -d
```

**업데이트 시:**
- 증분 업데이트 불가 (인터넷 연결 필요)
- 새 릴리즈가 있을 때마다 1-3단계 반복
- 월 1회 또는 분기 1회 권장

### 🔧 Jenkins 설정 (공통)

미러 서버 구축 후 Jenkins에서 다음과 같이 설정:

1. **Manage Jenkins** → **Manage Plugins** → **Advanced**
2. **Update Site URL**: `http://your-mirror-server/jenkins-comprehensive-mirror/update-center2/update-center.json`
3. **Submit** 클릭 후 Jenkins 재시작

## 🎯 미러 정보

### 🌐 **Comprehensive Mirror**
- **크기**: ~13GB (압축 전), 20개 파트로 분할
- **플러그인**: 3,000+개 (최대한 완전한 미러)
- **특징**: 다양한 버전 지원, 레거시 호환성
- **업데이트**: 월 1회 자동 릴리즈

## 🚀 상세 가이드

### 📦 스크립트 설명

- **0-download-latest-release.sh**: GitHub Release에서 미러 파트 파일들을 다운로드 (최대 50개 파트 지원)
- **1-assemble-comprehensive-mirror.sh**: 다운로드된 파트들을 조립하여 완전한 미러 생성
- **2-local-comprehensive-mirror.sh**: 기존 미러를 증분 업데이트 (온라인 환경 전용, 자동 릴리즈 생성)

### 🖥️ 미러 서버 배포 방법

#### 방법 1: Docker Compose (권장)
```bash
cd server/docker-image-layered
docker-compose up -d
```

#### 방법 2: Host Nginx
```bash
# 미러 디렉토리를 웹 서버 루트로 복사
sudo cp -r jenkins-comprehensive-mirror /var/www/
# Nginx 설정 파일 참조: server/host-nginx/
```

#### 방법 3: Full Docker Image
```bash
cd server/docker-image-full
docker build -t jenkins-mirror-full .
docker run -d -p 8080:80 jenkins-mirror-full
```

## 📁 프로젝트 구조

```
jenkins-plugin-mirror/
├── 0-download-latest-release.sh          # 사용자: 미러 다운로드 스크립트
├── 1-assemble-comprehensive-mirror.sh    # 사용자: 미러 조립 스크립트  
├── 2-local-comprehensive-mirror.sh       # Maintainer: 증분 업데이트 & 릴리즈 생성
├── server/                               # 미러 서버 배포 설정
│   ├── docker-image-layered/            # Docker Compose 방식 (권장)
│   │   ├── docker-compose.yml
│   │   └── Dockerfile
│   ├── docker-image-full/               # 전체 포함 Docker 이미지
│   │   └── Dockerfile
│   └── host-nginx/                      # Host Nginx 설정
│       └── nginx.conf
├── upload_script/                       # Maintainer 전용 업로드 스크립트
│   ├── split-and-upload.sh                # 기존 방식 (100GB+ 필요)
│   ├── split-and-upload-optimized.sh      # 최적화 방식 (60GB 필요)
│   └── simulate-disk-usage.sh             # 용량 시뮬레이션
└── README.md                            # 이 문서
```

## 🔧 문제 해결

### 일반적인 문제들

1. **체크섬 검증 실패**
   - 원인: 네트워크 문제로 인한 파일 다운로드 불완전
   - 해결: 다운로드 스크립트 재실행

2. **조립 스크립트 오류**
   - 원인: 일부 파트 파일 누락
   - 해결: 모든 파트가 다운로드되었는지 확인

3. **디스크 공간 부족**
   - 미러 크기: ~13GB (압축 해제 후)
   - 최소 필요 공간: 20GB 권장

### 로그 확인
```bash
# Docker 컨테이너 로그
docker logs jenkins-mirror

# 스크립트 실행 로그
./0-download-latest-release.sh 2>&1 | tee download.log
```

## 🤝 기여하기

1. Fork this repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)  
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.

---

## 👨‍💻 Release Maintainer 가이드

이 섹션은 Jenkins Plugin Mirror의 릴리즈를 생성하고 관리하는 maintainer를 위한 가이드입니다.

### 🔧 Maintainer 환경 요구사항

- **로컬 환경**: 최소 60GB 여유 공간 (최적화 스크립트 사용시)
- **GitHub CLI**: 인증 설정 완료
- **필수 도구**: `jq`, `rsync`, `wget`, `curl`, `git`
- **권장**: SSD 스토리지 (빠른 압축 처리)

### 🚀 릴리즈 생성 워크플로우

#### 1. 기존 미러 활용 (권장)
```bash
# 기존 미러가 /var/www/jenkins-mirror에 있는 경우
# 증분 업데이트로 빠르게 새 릴리즈 생성

./2-local-comprehensive-mirror.sh
```

#### 2. 전체 미러 생성 (최초 또는 기존 미러 없는 경우)
```bash
# 전체 다운로드 (4-6시간 소요)
git clone https://github.com/krnomad/jenkins-plugin-mirror.git
cd jenkins-plugin-mirror
./2-local-comprehensive-mirror.sh
```

### 📦 자동화된 릴리즈 프로세스

`2-local-comprehensive-mirror.sh` 스크립트는 다음 과정을 자동으로 수행합니다:

1. **🔍 환경 검사**: 기존 미러 확인, 디스크 공간 검증
2. **⚡ 증분 업데이트**: rsync를 통한 효율적인 동기화
3. **📦 자동 패키징**: GitHub 2GB 제한 맞춤 멀티파트 분할
4. **🚀 GitHub Release**: 자동 태깅, 업로드, 릴리즈 노트 생성
5. **🧹 정리**: 이전 릴리즈 삭제, 임시 파일 정리

### ⏱️ 실행 시간 가이드

| 상황 | 예상 시간 | 설명 |
|------|----------|------|
| **증분 업데이트** | 15-30분 | 기존 미러 기반 빠른 업데이트 |
| **전체 생성** | 4-6시간 | 전체 rsync 동기화 |
| **패키징** | 5-10분 | 압축 및 체크섬 생성 |
| **업로드** | 10-30분 | GitHub Release 생성 |

### 🔄 정기 업데이트 일정

```bash
# 월간 업데이트 예시
# 매월 둘째 주 토요일 실행 권장
0 2 * * 6 [ $(date +\%U) -eq $(date -d "$(date +\%Y-\%m-01) + 1 week" +\%U) ] && cd /path/to/jenkins-plugin-mirror && ./2-local-comprehensive-mirror.sh
```

### 🛠️ 문제 해결

**릴리즈 실패 시:**
```bash
# 이전 릴리즈 수동 삭제
gh release delete comprehensive-v$(date +'%Y.%m.%d') -y

# 다시 실행
./2-local-comprehensive-mirror.sh
```

**디스크 공간 부족:**
```bash
# 용량 시뮬레이션 (사전 확인)
./upload_script/simulate-disk-usage.sh 42 30

# 최적화된 업로드 스크립트 사용 (권장)
./upload_script/split-and-upload-optimized.sh

# 이전 미러 정리
rm -rf /tmp/jenkins-comprehensive-mirror
rm -rf /tmp/jenkins-release-packages-split
```

### 💾 업로드 스크립트 비교

| 방식 | 스크립트 | 필요 용량 | 처리 방식 | 권장도 |
|------|----------|-----------|-----------|---------|
| **기존** | `split-and-upload.sh` | ~138GB | 전체 TAR 생성 후 분할 | ❌ |
| **최적화** | `split-and-upload-optimized.sh` | ~60GB | 스트리밍 분할 압축 | ✅ |

**최적화된 스크립트의 장점:**
- **58% 디스크 공간 절약**: 138GB → 60GB
- **메모리 효율적**: 스트리밍 처리로 RAM 사용량 최소화  
- **병렬 압축**: 백그라운드 압축으로 처리 시간 단축
- **안전성**: 단계별 검증 및 자동 정리

---

## 📞 지원

문제가 발생하거나 질문이 있으시면 GitHub Issues를 통해 문의해 주세요.