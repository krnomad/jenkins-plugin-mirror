# Jenkins Comprehensive Plugin Mirror - comprehensive-v2025.09.13

🌟 **Complete Enterprise-Grade Jenkins Plugin Mirror**

이 릴리즈는 폐쇄망 환경을 위한 **완전한 Jenkins 플러그인 미러**를 제공합니다.

## 📊 릴리즈 정보

✅ **미러 타입**: Comprehensive (완전)  
✅ **총 크기**: ~32G (압축 전)  
✅ **파트 수**: 20개 (GitHub 2GB 제한 대응)  
✅ **플러그인 수**: 5598개  
✅ **생성일**: 2025-09-13 15:22:18  

## 🚀 사용법

### 1. 다운로드
```bash
# 모든 파트와 조립 스크립트 다운로드
gh release download comprehensive-v2025.09.13
```

### 2. 조립
```bash
# 체크섬 검증 (권장)
for file in jenkins-plugins-comprehensive-part*.tar.gz.sha256; do
    sha256sum -c "$file"
done

# 미러 조립
chmod +x assemble-comprehensive-mirror.sh
./assemble-comprehensive-mirror.sh
```

### 3. 배포
Docker 사용:
```bash
cd server/docker-image-layered
# docker-compose.yml 수정 후
docker-compose up -d
```

수동 배포:
```bash
sudo cp -r jenkins-comprehensive-mirror /var/www/
# Nginx 설정
```

## 🔧 Jenkins 설정

1. **Manage Jenkins** → **Manage Plugins** → **Advanced**
2. **Update Site URL**: `http://your-server/jenkins-comprehensive-mirror/update-center2/update-center.json`
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
