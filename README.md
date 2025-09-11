# Jenkins Plugin Mirror

이 저장소는 GitHub Actions를 통해 매월 자동으로 Jenkins 플러그인 미러를 생성하고 GitHub Release에 배포합니다. 폐쇄망 환경에서 안정적으로 Jenkins 플러그인을 관리할 수 있도록 돕습니다.

## 🎯 미러 타입별 특징

### 📦 **Essential-Only** (기본값, 권장)
- **크기**: ~5-10GB (원본 28GB에서 80% 감소)
- **플러그인**: ~2,000개 (필터링된 필수 플러그인)
- **특징**: 플러그인당 최신 3개 버전, 200MB 이하 파일만
- **실행시간**: ~30-45분
- **적합**: 대부분의 실무 환경

### 🧪 **Dry-Run** 
- **크기**: ~10MB 
- **플러그인**: 5개 (테스트용)
- **특징**: 빠른 테스트 및 검증용
- **실행시간**: ~2-3분
- **적합**: 워크플로우 테스트

### 🌐 **Comprehensive** (폐쇄망 전용)
- **크기**: ~20-30GB (역사적 버전 포함)
- **플러그인**: ~3,000개 (최대한 완전한 미러)
- **특징**: 플러그인당 최대 10개 버전, 1GB 이하 파일, rsync 기반 히스토리 포함
- **실행시간**: ~2-4시간
- **적합**: 레거시 Jenkins 환경 지원이 필요한 폐쇄망

### 🗂️ **Full-Filtered**
- **크기**: ~15-20GB 
- **플러그인**: ~2,500개 (완전한 필터링)
- **특징**: 플러그인당 최대 5개 버전, 500MB 이하 파일만
- **실행시간**: ~60-90분  
- **적합**: 완전한 미러가 필요한 경우

## 🚀 빠른 시작: 미러 사용하기

### 1. 최신 릴리즈 다운로드

로컬 환경에 `gh` CLI가 설치되어 있어야 합니다. 

#### 🚀 자동 다운로드 (권장)

```bash
chmod +x download-latest-release.sh
./download-latest-release.sh
```

이 스크립트는 **멀티파트 릴리즈를 자동으로 감지**하고 처리합니다:
- **멀티파트 릴리즈**: 자동으로 모든 part 파일을 다운로드하고 조립
- **단일 파일 릴리즈**: 기존 방식으로 다운로드 및 압축 해제

#### 📦 수동 다운로드 (멀티파트)

5GB+ 릴리즈의 경우 GitHub의 2GB 제한으로 인해 여러 파트로 분할됩니다:

```bash
# 모든 파트 다운로드
gh release download --pattern="jenkins-plugins-mirror-part*.tar.gz*"
gh release download --pattern="assemble-mirror.sh"

# 체크섬 검증
for file in jenkins-plugins-mirror-part*.tar.gz.sha256; do
  sha256sum -c "$file"
done

# 조립
chmod +x assemble-mirror.sh
./assemble-mirror.sh
```

완료되면 `jenkins-mirror` 디렉토리에 플러그인 파일들과 `update-center.json`이 생성됩니다.

### 2. 미러 서버 실행

아래 3가지 방법 중 하나를 선택하여 미러 서버를 실행하세요. **(권장: 방법 2)**

### 3. Jenkins 설정

* Jenkins 관리 > 플러그인 관리 > 고급 설정(Advanced settings)으로 이동합니다.
* **업데이트 사이트(Update Site)** URL을 여러분이 구축한 미러 서버 주소로 변경합니다. (예: `http://localhost:8080/update-center.json`)
* 제출(Submit) 후 Jenkins를 재시작하면 미러 서버에서 플러그인을 가져옵니다.

---

## 🛠️ 미러 서버 구축 방법

다운로드한 `jenkins-mirror` 디렉토리의 위치를 기억하세요. (예: `/data/jenkins-mirror`)

### 방법 1: Host에서 Nginx로 직접 실행

가장 간단한 방법으로, 시스템에 Nginx가 설치되어 있어야 합니다.

1. **Nginx 설정 파일 작성 (`/etc/nginx/conf.d/jenkins-mirror.conf`)**

   ```nginx
   server {
       listen 8080;
       server_name jenkins-mirror;

       location / {
           root /data/jenkins-mirror; # jenkins-mirror 디렉토리 경로
           autoindex on;
       }
       
       # 큰 파일에 대한 클라이언트 최대 업로드 크기
       client_max_body_size 100M;
       
       # 정적 파일 캐싱 설정
       location ~* \.(hpi|jar)$ {
           expires 1d;
           add_header Cache-Control "public, immutable";
       }
       
       location ~* \.(json)$ {
           expires 1h;
           add_header Cache-Control "public";
       }
   }
   ```

2. **`update-center.json` URL 수정**

   `/data/jenkins-mirror/update-center.json` 파일을 열어 `http://your-mirror.example.com`을 실제 서버 주소(예: `http://<서버_IP>:8080`)로 모두 변경합니다.

3. **Nginx 재시작**

   ```bash
   sudo systemctl restart nginx
   ```

### 방법 2: Docker Compose와 Layered Image (권장)

가장 효율적이고 추천되는 방법입니다. 플러그인 데이터는 호스트에 유지하고 Nginx 컨테이너만 실행하여 업데이트가 간편합니다.

1. **`docker-compose.yml` 확인**

   `server/docker-image-layered/docker-compose.yml` 파일이 이미 준비되어 있습니다.

   ```yaml
   version: '3.8'
   services:
     nginx:
       build: .
       ports:
         - "8080:80"
       volumes:
         - ../../jenkins-mirror:/usr/share/nginx/html
       environment:
         - NGINX_HOST=localhost
         - NGINX_PORT=8080
   ```

2. **환경 변수 설정**

   실제 서버 주소에 맞게 환경 변수를 수정하거나, Docker Compose 실행 시 자동으로 URL이 업데이트됩니다.

3. **Docker Compose 실행**

   ```bash
   cd server/docker-image-layered
   docker-compose up --build -d
   ```

### 방법 3: 모든 플러그인이 포함된 Docker 이미지 생성

모든 플러그인 파일을 이미지 안에 포함시키는 방식으로, 이미지 용량이 매우 큽니다(40GB+).

1. **이미지 빌드 및 실행**

   `jenkins-mirror` 디렉토리가 준비된 후 아래 명령을 실행합니다.

   ```bash
   # 빌드 (시간이 매우 오래 걸림)
   cd server/docker-image-full
   docker build --build-arg SERVER_URL=http://your-server:8080 -t jenkins-mirror-full .

   # 실행
   docker run -d -p 8080:80 --name jenkins-mirror jenkins-mirror-full
   ```

---

## 📋 프로젝트 구조

```
jenkins-plugin-mirror/
├── .github/
│   └── workflows/
│       └── mirror-update.yml           # GitHub Actions 워크플로우
├── scripts/
│   ├── 01-generate-plugin-list.sh      # 플러그인 목록 및 크기 정보 생성, 청크 분할
│   ├── 02-process-chunk.sh             # 청크별 플러그인 병렬 다운로드
│   └── 03-generate-update-center.sh    # update-center.json 생성
├── server/
│   ├── host-nginx/
│   │   └── nginx.conf                  # Host에서 Nginx로 실행 시 설정 파일
│   ├── docker-image-layered/
│   │   ├── Dockerfile                  # 레이어드 방식 Docker 이미지
│   │   ├── docker-compose.yml          # Docker Compose 실행 파일
│   │   ├── nginx.conf                  # Nginx 설정
│   │   ├── update-urls.sh              # URL 업데이트 스크립트
│   │   └── entrypoint.sh               # 컨테이너 진입점
│   └── docker-image-full/
│       ├── Dockerfile                  # 모든 플러그인 포함 Docker 이미지
│       ├── nginx.conf                  # Nginx 설정
│       └── update-urls.sh              # URL 업데이트 스크립트
├── download-latest-release.sh          # 최신 릴리즈 다운로드 스크립트
├── plan.md                             # 프로젝트 구현 계획
└── README.md                           # 사용자 가이드
```

---

## ⚙️ 설정 및 배포

### GitHub Actions 설정

1. **Personal Access Token 생성**
   - GitHub에서 Settings > Developer settings > Personal access tokens > Tokens (classic)
   - `repo`와 `workflow` 권한이 있는 토큰 생성
   
2. **Repository Secret 등록**
   - Repository Settings > Secrets and variables > Actions
   - `GH_PAT` 이름으로 생성한 토큰 추가

### 워크플로우 실행

#### 🆕 **최적화된 워크플로우 (권장)**

1. **테스트 실행** (5개 플러그인, ~2분)
   ```bash
   gh workflow run mirror-optimized.yml --ref main -f mirror_type=dry-run
   ```

2. **실용적 미러** (기본값, ~2,000개 플러그인, ~40분)
   ```bash
   gh workflow run mirror-optimized.yml --ref main -f mirror_type=essential-only
   ```

3. **완전한 미러** (~2,500개 플러그인, ~90분)
   ```bash
   gh workflow run mirror-optimized.yml --ref main -f mirror_type=full-filtered
   ```

4. **태그 지정 옵션**
   ```bash
   gh workflow run mirror-optimized.yml --ref main -f mirror_type=essential-only -f tag_suffix=-custom
   ```

#### 🔄 **기존 워크플로우 (레거시)**

1. **Dry Run 테스트**
   ```bash
   gh workflow run mirror-update.yml --ref main -f dry_run=true
   ```

2. **정식 실행** (⚠️ 28GB, 3시간+, 권장하지 않음)
   ```bash
   gh workflow run mirror-update.yml --ref main -f dry_run=false
   ```

### 🌐 Comprehensive Mirror 사용 고려사항

**Comprehensive** 모드는 폐쇄망 환경에서 레거시 Jenkins 버전 지원이 필요한 경우에만 사용하세요:

**장점:**
- 🔄 최대 10개의 이전 버전 지원 (레거시 호환성)
- 📚 rsync 기반 히스토리 플러그인 포함
- 🏢 완전한 폐쇄망 환경 지원

**단점:**
- ⏰ 2-4시간 빌드 시간 (GitHub Actions 6시간 제한 근접)
- 💾 20-30GB 큰 다운로드 크기 
- 🔀 10-15개 멀티파트 릴리즈 (복잡한 다운로드)

**권장 사용법:**
```bash
# Comprehensive 미러 생성 (신중히 사용)
gh workflow run mirror-optimized.yml --ref main -f mirror_type=comprehensive
```

> **💡 팁**: `essential-only`가 대부분의 사용 사례에 적합합니다. 원본 28GB에서 80% 감소된 5-10GB로 실용적이면서도 포괄적인 플러그인 컬렉션을 제공합니다.

---

## 🔧 고급 설정

### 캐싱 최적화

Nginx 설정에서 캐싱을 통해 성능을 향상시킬 수 있습니다:

```nginx
# HPI 파일은 1일 캐시
location ~* \.(hpi|jar)$ {
    expires 1d;
    add_header Cache-Control "public, immutable";
}

# JSON 파일은 1시간 캐시
location ~* \.(json)$ {
    expires 1h;
    add_header Cache-Control "public";
}
```

### 로드 밸런싱

여러 미러 서버를 운영하는 경우 Nginx upstream을 사용할 수 있습니다:

```nginx
upstream jenkins_mirrors {
    server mirror1:8080;
    server mirror2:8080;
    server mirror3:8080;
}

server {
    listen 80;
    location / {
        proxy_pass http://jenkins_mirrors;
    }
}
```

---

## 🐛 문제 해결

### 일반적인 문제들

1. **디스크 공간 부족**
   - GitHub Actions에서 `jlumbroso/free-disk-space` 액션을 사용하여 공간 확보
   - 청크 크기를 줄여서 처리 (`CHUNK_SIZE_MB` 조정)

2. **다운로드 실패**
   - 네트워크 재시도 로직이 스크립트에 포함됨
   - 개별 청크별로 처리되므로 일부 실패해도 다른 청크는 계속 진행

3. **체크섬 검증 실패**
   - Jenkins update center에서 일부 플러그인의 체크섬이 누락될 수 있음
   - 스크립트에서 체크섬이 있는 경우만 검증

### 로그 확인

```bash
# Docker 컨테이너 로그 확인
docker logs jenkins-mirror

# GitHub Actions 로그는 Actions 탭에서 확인
```

---

## 🤝 기여하기

1. Fork this repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다. 자세한 내용은 `LICENSE` 파일을 참조하세요.

---

## 📞 지원

문제가 발생하거나 질문이 있으시면 GitHub Issues를 통해 문의해 주세요.