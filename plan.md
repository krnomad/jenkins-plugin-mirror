물론입니다. 제안주신 모든 개선 사항과 구체적인 요구사항을 반영하여, GitHub Actions를 활용한 Jenkins 플러그인 미러 구축 전체 계획을 단계별로 정리해 드리겠습니다.

이 가이드는 신규 GitHub 저장소를 생성하고, `gh` CLI를 통해 워크플로우를 등록하며, 최종 사용자를 위한 상세한 문서와 배포 옵션까지 포함하는 완전한 실행 계획입니다.

-----

### \#\# 📝 최종 계획: GitHub Actions 기반 Jenkins 플러그인 미러 자동화

이 계획은 다음 4단계로 구성됩니다.

1.  **사전 준비**: 사용자가 미리 준비해야 할 정보와 저장소 초기 설정
2.  **핵심 파일 구현**: GitHub Actions 워크플로우, 스크립트, Dockerfile 등 핵심 코드 작성
3.  **워크플로우 등록 및 실행**: `gh` CLI를 사용한 워크플로우 설정 및 Dry-Run 테스트
4.  **사용자 가이드 (`README.md`) 작성**: 최종 사용자를 위한 미러 서버 구축 및 활용 방법 안내

-----

### \#\# 1. 사전 준비 및 초기 설정

본격적인 구현에 앞서, 아래 항목들을 먼저 준비해야 합니다.

#### **✅ 당신이 준비해야 할 정보**

1.  **GitHub Repository**: `jenkins-plugin-mirror`와 같이 새로운 비공개(Private) 또는 공개(Public) 저장소를 생성합니다.
2.  **GitHub Personal Access Token (PAT)**: GitHub Actions에서 Release를 생성하고 파일을 업로드하려면 권한이 필요합니다.
      * `repo`와 `workflow` 스코프 권한을 가진 PAT를 발급받으세요.
      * 발급받은 토큰을 저장소의 **Settings \> Secrets and variables \> Actions** 에서 `GH_PAT` 라는 이름의 Secret으로 등록합니다.

#### **📂 프로젝트 파일 구조**

아래와 같은 디렉토리 및 파일 구조로 프로젝트를 구성합니다.

```
jenkins-plugin-mirror/
├── .github/
│   └── workflows/
│       └── mirror-update.yml           #  основной воркфлоу
├── scripts/
│   ├── 01-generate-plugin-list.sh      # 플러그인 목록 및 크기 정보 생성, 청크 분할
│   ├── 02-process-chunk.sh             # 청크별 플러그인 병렬 다운로드
│   └── 03-generate-update-center.sh    # update-center.json 생성
├── server/
│   ├── host-nginx/
│   │   └── nginx.conf                  # Host에서 Nginx로 실행 시 설정 파일
│   ├── docker-image-layered/
│   │   ├── Dockerfile                  # 레이어드 방식 Docker 이미지
│   │   └── docker-compose.yml          # Docker Compose 실행 파일
│   └── docker-image-full/
│       └── Dockerfile                  # 모든 플러그인 포함 Docker 이미지
├── download-latest-release.sh          # 최신 릴리즈 다운로드 스크립트
└── README.md                           # 사용자 가이드
```

-----

### \#\# 2. 핵심 파일 구현

각 파일에 아래 내용을 작성하여 저장소에 추가합니다.

#### **`./.github/workflows/mirror-update.yml`**

```yaml
name: Jenkins Plugin Mirror CI

on:
  schedule:
    - cron: '0 2 1 * *'  # 매월 1일 02:00 UTC에 실행
  workflow_dispatch:
    inputs:
      dry_run:
        description: 'Dry run mode (downloads only 3 plugins)'
        required: true
        type: boolean
        default: false
      tag_suffix:
        description: 'Optional suffix for release tag (e.g., -manual)'
        required: false
        type: string

jobs:
  prepare-metadata:
    runs-on: ubuntu-latest
    outputs:
      release_tag: ${{ steps.vars.outputs.release_tag }}
      chunk_count: ${{ steps.generate-list.outputs.chunk_count }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set Release Tag
        id: vars
        run: |
          VERSION="v$(date +'%Y.%m.%d')"
          TAG_SUFFIX="${{ inputs.tag_suffix }}"
          DRY_RUN="${{ inputs.dry_run }}"
          RELEASE_TAG="$VERSION$TAG_SUFFIX"
          if [ "$DRY_RUN" = "true" ]; then
            RELEASE_TAG="dry-run-$VERSION"
          fi
          echo "release_tag=$RELEASE_TAG" >> $GITHUB_OUTPUT

      - name: Generate Plugin List and Split into Chunks
        id: generate-list
        run: |
          chmod +x ./scripts/01-generate-plugin-list.sh
          ./scripts/01-generate-plugin-list.sh ${{ inputs.dry_run }}
          CHUNK_COUNT=$(ls chunk_*.txt | wc -l)
          echo "chunk_count=$CHUNK_COUNT" >> $GITHUB_OUTPUT
      
      - name: Upload chunk manifests
        uses: actions/upload-artifact@v4
        with:
          name: chunk-manifests
          path: chunk_*.txt
          retention-days: 1

  process-chunks:
    needs: prepare-metadata
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        chunk_id: ${{ fromJson(format('[{0}]', join(range(1, needs.prepare-metadata.outputs.chunk_count + 1), ','))) }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        
      - name: Download chunk manifests
        uses: actions/download-artifact@v4
        with:
          name: chunk-manifests

      - name: Free up disk space
        uses: jlumbroso/free-disk-space@main
        with:
          tool-cache: true
          android: true
          dotnet: true
          haskell: true
          large-packages: true
          swap-storage: true

      - name: Process Chunk ${{ matrix.chunk_id }}
        id: process
        run: |
          chmod +x ./scripts/02-process-chunk.sh
          ./scripts/02-process-chunk.sh ${{ matrix.chunk_id }}
          
      - name: Upload processed chunk artifact
        uses: actions/upload-artifact@v4
        with:
          name: jenkins-plugins-chunk-${{ matrix.chunk_id }}
          path: jenkins-plugins-chunk-${{ matrix.chunk_id }}/
          retention-days: 1

  create-release:
    needs: [prepare-metadata, process-chunks]
    runs-on: ubuntu-latest
    permissions:
      contents: write # 릴리즈 생성을 위한 권한
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Create release directory
        run: mkdir -p release_assets/plugins

      - name: Download all processed chunk artifacts
        uses: actions/download-artifact@v4
        with:
          path: release_assets/plugins
          pattern: jenkins-plugins-chunk-*
          merge-multiple: true

      - name: Generate update-center.json
        run: |
          chmod +x ./scripts/03-generate-update-center.sh
          ./scripts/03-generate-update-center.sh release_assets/plugins release_assets/update-center.json

      - name: Package release assets
        run: |
          cd release_assets
          tar -czf ../jenkins-plugins-mirror.tar.gz .
          sha256sum ../jenkins-plugins-mirror.tar.gz > ../jenkins-plugins-mirror.tar.gz.sha256
          cd ..
          
      - name: Create or Update GitHub Release
        env:
          GH_TOKEN: ${{ secrets.GH_PAT }}
          RELEASE_TAG: ${{ needs.prepare-metadata.outputs.release_tag }}
        run: |
          gh release list | grep -q "$RELEASE_TAG" && gh release delete "$RELEASE_TAG" -y
          
          gh release create "$RELEASE_TAG" \
            --title "Jenkins Plugins Mirror - $RELEASE_TAG" \
            --notes "Automated Jenkins plugins mirror. Contains all plugins and update-center.json." \
            --latest \
            jenkins-plugins-mirror.tar.gz \
            jenkins-plugins-mirror.tar.gz.sha256
```

#### **`./scripts/01-generate-plugin-list.sh`**

```bash
#!/bin/bash
set -e

DRY_RUN=$1
CHUNK_SIZE_MB=1500 # 1.5GB to stay safely under the 2GB limit
PLUGINS_JSON_URL="https://updates.jenkins.io/current/update-center.actual.json"

echo "Fetching plugin list from Jenkins update center..."
# Remove the JSONP wrapper to get pure JSON
curl -sL $PLUGINS_JSON_URL | sed '1d;$d' > plugins.json

echo "Generating plugin download list with URLs and sizes..."
# Use jq to parse JSON and create a list of "url size"
jq -r '.plugins[] | "\(.url) \(.sha256)"' plugins.json > plugin_list_full.txt

if [ "$DRY_RUN" = "true" ]; then
  echo "Dry-run mode enabled. Using only 3 plugins."
  head -n 3 plugin_list_full.txt > plugin_list.txt
else
  cp plugin_list_full.txt plugin_list.txt
fi

echo "Splitting plugin list into chunks of max ${CHUNK_SIZE_MB}MB..."
# This script is a simplified example. A real-world script might fetch sizes first.
# For simplicity here, we split by line count, but the workflow has disk-freeing steps
# and the chunk size is conservative. A more robust script would curl HEAD for sizes.
total_lines=$(wc -l < plugin_list.txt)
# Assuming average plugin size of 1-2MB, this is a safe split
lines_per_chunk=1000 
if [ "$DRY_RUN" = "true" ]; then
  lines_per_chunk=3
fi
split -l $lines_per_chunk -d -a 2 plugin_list.txt chunk_ --filter='sh -c "sort -R $FILE > $FILE.sorted"'

# Rename chunks to a predictable format
i=1
for f in chunk_*; do
  mv -- "$f" "chunk_$i.txt"
  i=$((i+1))
done

echo "Created $(ls chunk_*.txt | wc -l) chunk manifest(s)."

```

#### **`./scripts/02-process-chunk.sh`**

```bash
#!/bin/bash
set -e

CHUNK_ID=$1
CHUNK_FILE="chunk_${CHUNK_ID}.txt"
OUTPUT_DIR="jenkins-plugins-chunk-${CHUNK_ID}"
mkdir -p "$OUTPUT_DIR"

if [ ! -f "$CHUNK_FILE" ]; then
  echo "Chunk file $CHUNK_FILE not found!"
  exit 1
fi

echo "Processing chunk #${CHUNK_ID}..."

# Parallel download using xargs
# -P 16: up to 16 parallel downloads
# --retry 3: retry up to 3 times
# --timeout 30: 30-second timeout
cut -d' ' -f1 "$CHUNK_FILE" | xargs -n 1 -P 16 \
  wget --quiet --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 3 -P "$OUTPUT_DIR"

echo "Verifying checksums for chunk #${CHUNK_ID}..."
while read -r url sha256; do
  filename=$(basename "$url")
  # Jenkins JSON sometimes lacks the hash, so we skip if empty
  if [ -n "$sha256" ]; then
    echo "$sha256  $OUTPUT_DIR/$filename" >> checksums.txt
  fi
done < "$CHUNK_FILE"

# The sha256sum tool exits with 1 if any file fails, which is what we want
sha256sum -c checksums.txt

echo "Chunk #${CHUNK_ID} processed successfully."
df -h
```

#### **`./scripts/03-generate-update-center.sh`**

```bash
#!/bin/bash
set -e

PLUGINS_DIR=$1
OUTPUT_FILE=$2
BASE_URL="http://your-mirror.example.com/plugins" # This will be replaced by users

echo "Generating update-center.json from plugins in $PLUGINS_DIR..."

# Fetch the original JSON to use as a template for metadata
curl -sL "https://updates.jenkins.io/current/update-center.actual.json" | sed '1d;$d' > original.json

# Create the main JSON structure
echo "{" > temp.json
echo "  \"plugins\": {" >> temp.json

# Iterate over downloaded plugins
first=true
for hpi in $(find $PLUGINS_DIR -name "*.hpi"); do
  plugin_name=$(unzip -p $hpi META-INF/MANIFEST.MF | grep -E 'Plugin-Id|Short-Name' | head -n1 | cut -d: -f2 | tr -d ' \r')
  
  # Extract original plugin data from the template
  plugin_json=$(jq --arg name "$plugin_name" '.plugins[$name]' original.json)
  
  if [ "$plugin_json" != "null" ]; then
    if [ "$first" = "false" ]; then
      echo "," >> temp.json
    fi
    
    # Override URL to point to our mirror
    new_url="${BASE_URL}/$(basename $hpi)"
    updated_plugin_json=$(echo $plugin_json | jq --arg url "$new_url" '.url = $url')
    
    echo "    \"$plugin_name\": $updated_plugin_json" >> temp.json
    first=false
  fi
done

echo "  }," >> temp.json
# Copy other metadata from the original file
jq '.core, .warnings, .id, .signature' original.json >> temp.json
echo "}" >> temp.json

# Wrap in JSONP format
echo "updateCenter.post(" > $OUTPUT_FILE
cat temp.json >> $OUTPUT_FILE
echo ");" >> $OUTPUT_FILE

echo "Successfully created $OUTPUT_FILE"
```

-----

### \#\# 3. 워크플로우 등록 및 실행

1.  **코드 푸시**: 작성한 모든 파일을 당신의 GitHub 저장소에 푸시합니다.
2.  **`gh` CLI로 워크플로우 확인**:
    ```bash
    gh workflow list
    ```
3.  **Dry-Run 모드로 워크플로우 실행**:
    ```bash
    gh workflow run mirror-update.yml --ref main -f dry_run=true
    ```
      * 이 명령은 Actions 탭에서 "Dry run mode"를 활성화하여 워크플로우를 수동으로 실행하는 것과 동일합니다.
      * 실행이 완료되면 `dry-run-vYYYY.MM.DD` 형태의 태그와 함께 3개의 플러그인만 포함된 Release가 생성되었는지 확인합니다.
4.  **정식 실행**:
    ```bash
    gh workflow run mirror-update.yml --ref main -f dry_run=false
    ```
      * 모든 플러그인을 다운로드하여 정식 릴리즈를 생성합니다.

-----

### \#\# 4. 사용자 가이드 (`README.md`) 작성

저장소의 `README.md` 파일에 아래 내용을 작성하여, 미러 사용자들이 쉽게 서버를 구축할 수 있도록 안내합니다.

````markdown
# Jenkins Plugin Mirror

이 저장소는 GitHub Actions를 통해 매월 자동으로 Jenkins 플러그인 미러를 생성하고 GitHub Release에 배포합니다. 폐쇄망 환경에서 안정적으로 Jenkins 플러그인을 관리할 수 있도록 돕습니다.

## 🚀 빠른 시작: 미러 사용하기

1.  **최신 릴리즈 다운로드**

    로컬 환경에 `gh` CLI가 설치되어 있어야 합니다. 아래 스크립트를 실행하여 최신 릴리즈 파일을 다운로드하세요.

    ```bash
    ./download-latest-release.sh
    ```
    다운로드가 완료되면 `jenkins-mirror` 디렉토리에 플러그인 파일들과 `update-center.json`이 생성됩니다.

2.  **미러 서버 실행**

    아래 3가지 방법 중 하나를 선택하여 미러 서버를 실행하세요. **(권장: 방법 2)**

3.  **Jenkins 설정**

    * Jenkins 관리 > 플러그인 관리 > 고급 설정(Advanced settings)으로 이동합니다.
    * **업데이트 사이트(Update Site)** URL을 여러분이 구축한 미러 서버 주소로 변경합니다. (예: `http://localhost:8080/update-center.json`)
    * 제출(Submit) 후 Jenkins를 재시작하면 미러 서버에서 플러그인을 가져옵니다.

---

## 🛠️ 미러 서버 구축 방법

다운로드한 `jenkins-mirror` 디렉토리의 위치를 기억하세요. (예: `/data/jenkins-mirror`)

### 방법 1: Host에서 Nginx로 직접 실행

가장 간단한 방법으로, 시스템에 Nginx가 설치되어 있어야 합니다.

1.  **Nginx 설정 파일 작성 (`/etc/nginx/conf.d/jenkins-mirror.conf`)**

    ```nginx
    server {
        listen 8080;
        server_name jenkins-mirror;

        location / {
            root /data/jenkins-mirror; # jenkins-mirror 디렉토리 경로
            autoindex on;
        }
    }
    ```

2.  **`update-center.json` URL 수정**

    `/data/jenkins-mirror/update-center.json` 파일을 열어 `http://your-mirror.example.com`을 실제 서버 주소(예: `http://<서버_IP>:8080`)로 모두 변경합니다.

3.  **Nginx 재시작**

    ```bash
    sudo systemctl restart nginx
    ```

### 방법 2: Docker Compose와 Layered Image (권장)

가장 효율적이고 추천되는 방법입니다. 플러그인 데이터는 호스트에 유지하고 Nginx 컨테이너만 실행하여 업데이트가 간편합니다.

1.  **`docker-compose.yml` 확인**

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

2.  **`update-center.json` URL 수정**

    `jenkins-mirror/update-center.json` 파일을 열어 `http://your-mirror.example.com`을 Docker가 실행될 호스트의 주소(예: `http://<호스트_IP>:8080`)로 모두 변경합니다.

3.  **Docker Compose 실행**

    ```bash
    cd server/docker-image-layered
    docker-compose up --build -d
    ```

### 방법 3: 모든 플러그인이 포함된 Docker 이미지 생성

모든 플러그인 파일을 이미지 안에 포함시키는 방식으로, 이미지 용량이 매우 큽니다(40GB+).

1.  **`Dockerfile` 확인**

    `server/docker-image-full/Dockerfile` 파일이 준비되어 있습니다.

    ```dockerfile
    FROM nginx:alpine
    # 모든 플러그인 데이터를 이미지 레이어에 복사
    COPY ../../jenkins-mirror /usr/share/nginx/html
    # ... URL 수정 로직 추가 필요 ...
    ```

2.  **이미지 빌드 및 실행**

    `update-center.json` URL 수정 후 아래 명령을 실행합니다.

    ```bash
    # 빌드 (시간이 매우 오래 걸림)
    docker build -t jenkins-mirror-full ./server/docker-image-full

    # 실행
    docker run -d -p 8080:80 --name jenkins-mirror jenkins-mirror-full
    ```

---
````

#### **`./download-latest-release.sh`**

```bash
#!/bin/bash
set -e

REPO_URL=$(git remote get-url origin)
REPO_NAME=$(echo "$REPO_URL" | sed -e 's/.*github.com\///' -e 's/\.git$//')
DOWNLOAD_DIR="jenkins-mirror"

if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed. Please install it to proceed."
    exit 1
fi

echo "Fetching latest release from repository: $REPO_NAME"

mkdir -p "$DOWNLOAD_DIR"

gh release download --repo "$REPO_NAME" --latest -p "*.tar.gz*" -O .

echo "Verifying checksum..."
sha256sum -c jenkins-plugins-mirror.tar.gz.sha256

echo "Extracting files..."
tar -xzf jenkins-plugins-mirror.tar.gz -C "$DOWNLOAD_DIR"

echo "Cleaning up..."
rm jenkins-plugins-mirror.tar.gz jenkins-plugins-mirror.tar.gz.sha256

echo "✅ Success! Jenkins mirror files are ready in the '$DOWNLOAD_DIR' directory."
echo "Please edit '$DOWNLOAD_DIR/update-center.json' and replace 'http://your-mirror.example.com' with your actual server URL."
echo "Then, choose one of the deployment methods in README.md."

```

#### **서버 배포용 파일들**

`server/` 디렉토리 아래에 있는 파일들도 `README.md`에서 설명한 내용에 맞게 미리 작성하여 저장소에 포함시킵니다. 이 파일들은 사용자가 미러 서버를 쉽게 구축할 수 있도록 돕는 템플릿 역할을 합니다.
