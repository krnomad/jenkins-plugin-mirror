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

- **0-download-latest-release.sh**: GitHub Release에서 미러 파트 파일들을 다운로드
- **1-assemble-comprehensive-mirror.sh**: 다운로드된 파트들을 조립하여 완전한 미러 생성
- **2-local-comprehensive-mirror.sh**: 기존 미러를 증분 업데이트 (온라인 환경 전용)

### 🖥️ 미러 서버 배포 방법

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

#### 🎯 **원클릭 실행 (모든 과정 자동화)**

```bash
# 1. 저장소 클론 (최초 1회만)
git clone https://github.com/krnomad/jenkins-plugin-mirror.git
cd jenkins-plugin-mirror

# 2. Comprehensive 미러 생성 + 자동 GitHub Release
./scripts/local-comprehensive-mirror.sh
```

#### ✨ **스크립트가 자동으로 수행하는 작업:**

1. **🔍 환경 검사**:
   - 기존 미러 발견 시 `/var/www/jenkins-mirror` 활용
   - 디스크 공간 및 필수 도구 확인

2. **⚡ 증분 업데이트**:
   - 기존 플러그인: 스킵 (빠른 실행)  
   - 새로운/업데이트된 플러그인: 다운로드
   - rsync 증분 동기화 (`--update` 플래그)

3. **📦 자동 패키징**:
   - GitHub 2GB 제한 맞춤 멀티파트 분할
   - SHA-256 체크섬 자동 생성
   - 조립 스크립트 자동 생성

4. **🚀 GitHub Release 자동 생성**:
   - 릴리즈 태그: `comprehensive-v2025.09.11` 형식
   - 모든 파트 파일 자동 업로드
   - 상세한 릴리즈 노트 자동 생성

5. **🧹 자동 정리**:
   - 이전 릴리즈 자동 삭제 (최신 3개만 유지)
   - 임시 파일 정리

#### ⏱️ **실행 시간 예상**

| 상황 | 예상 시간 | 설명 |
|------|----------|------|
| **최초 실행** | 4-6시간 | 전체 rsync 동기화 필요 |
| **증분 업데이트** | 15-30분 | 기존 미러 기반 빠른 업데이트 |
| **패키징** | 5-10분 | 압축 및 체크섬 생성 |
| **업로드** | 10-30분 | GitHub Release 생성 (파트 수에 따라) |

#### 📊 **실행 결과 (자동 통계)**

```
✅ 증분 미러 업데이트 완료:
  - 총 플러그인 파일: 3,851개
  - 고유 플러그인: 2,134개
  - 총 크기: 28GB

📦 패키징 완료: 15개 파트
🚀 GitHub Release 생성 완료: comprehensive-v2025.09.11
🔗 Release URL: https://github.com/user/repo/releases/tag/comprehensive-v2025.09.11
```


### 🎯 **언제 사용해야 하나요?**

#### ✅ Comprehensive 미러가 필요한 경우:
- **레거시 Jenkins** 환경 (2.x 초기 버전 등)
- **완전한 폐쇄망** 환경
- **플러그인 호환성** 문제 해결 필요
- **기업 컴플라이언스** 요구사항 (모든 버전 보관)

#### ⚠️ Essential 미러로 충분한 경우:
- **최신 Jenkins** LTS 사용
- **표준 플러그인**만 필요
- **빠른 다운로드** 선호
- **디스크 공간** 제약

### 🔄 **정기 업데이트**

```bash
# 월간 업데이트 스케줄
# 1. 로컬에서 새 미러 생성
./scripts/local-comprehensive-mirror.sh

# 2. GitHub Release 업데이트  
gh release create comprehensive-v$(date +'%Y.%m.%d') [...]

# 3. 구 릴리즈 정리 (선택사항)
gh release delete comprehensive-v2025.08.11 -y
```

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

---

## 👨‍💻 Release Maintainer 가이드

이 섹션은 Jenkins Plugin Mirror의 릴리즈를 생성하고 관리하는 maintainer를 위한 가이드입니다.

### 🔧 Maintainer 환경 요구사항

- **로컬 환경**: 최소 35GB 여유 공간
- **GitHub CLI**: 인증 설정 완료
- **필수 도구**: `jq`, `rsync`, `wget`, `curl`, `git`

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
./scripts/local-comprehensive-mirror.sh
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
# 이전 미러 정리
rm -rf /tmp/jenkins-comprehensive-mirror
rm -rf /tmp/jenkins-release-packages-split
```

---

## 📞 지원

문제가 발생하거나 질문이 있으시면 GitHub Issues를 통해 문의해 주세요.
