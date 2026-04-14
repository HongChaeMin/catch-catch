# Deploy

## macOS

### 1. 빌드

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -scheme catch-catch -destination 'platform=macOS' \
  -derivedDataPath .claude/tmp/DerivedData \
  -configuration Release build
```

- DerivedData는 `.claude/tmp/DerivedData` 사용 (`/tmp` 금지)
- `swift build`는 SwiftUI 매크로 이슈로 사용 불가 — 반드시 `xcodebuild`

### 2. 패키징

```bash
# .app 복사
rm -rf build/catch-catch.app
cp -R .claude/tmp/DerivedData/Build/Products/Release/catch-catch.app build/catch-catch.app

# Ad-hoc sign (필수)
codesign --force --sign - build/catch-catch.app

# DMG — RW 템플릿에서 앱만 교체 (배경/아이콘 배치 유지)
hdiutil attach build/dmg_rw.dmg -nobrowse
rm -rf "/Volumes/catch-catch/catch-catch.app"
cp -R build/catch-catch.app "/Volumes/catch-catch/catch-catch.app"
hdiutil detach "/Volumes/catch-catch"
rm -f build/catch-catch.dmg
hdiutil convert build/dmg_rw.dmg -format UDZO -o build/catch-catch.dmg

# ZIP
cd build && rm -f catch-catch.zip && zip -r catch-catch.zip catch-catch.app && cd ..
```

**DMG 주의사항:**
- `build/dmg_rw.dmg`에 배경 이미지/아이콘 레이아웃 저장됨 — 매번 새로 만들지 말고 앱만 교체
- 배경 재설정 필요 시: RW DMG 마운트 → Finder에서 Cmd+J → 배경 그림 설정 → 아이콘 배치
- AppleScript(-1743 에러)는 Finder 자동화 권한 문제 — 수동 Finder 설정이 확실함

### 3. 릴리스

```bash
unset GITHUB_TOKEN && gh release create vX.Y.Z \
  build/catch-catch.dmg build/catch-catch.zip \
  --repo HongChaeMin/catch-catch \
  --title "vX.Y.Z" --notes "릴리즈 노트"
```

`GITHUB_TOKEN` 환경변수가 설정된 경우 `gh`가 다른 계정 토큰을 사용할 수 있으므로 `unset GITHUB_TOKEN` 필수.

### 버전 관리

- `Info.plist`에서 `CFBundleShortVersionString`(표시 버전)과 `CFBundleVersion`(빌드 번호) 업데이트

---

## Windows

태그 push만 하면 GitHub Actions가 자동 빌드 + 릴리스.

### 1. 버전 업데이트

`CatchCatch/CatchCatch.csproj`에서 Version, AssemblyVersion, FileVersion 업데이트.

### 2. 커밋 & 태그 push

```bash
cd catch-catch-windows
git add -A && git commit -m "변경 내용"
git tag vX.Y.Z
unset GITHUB_TOKEN && git push origin main --tags
```

### 자동 빌드 과정

워크플로우: `.github/workflows/release.yml`

1. `v*` 태그 push 감지
2. `windows-latest`에서 .NET 8 SDK 설치
3. `dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true`
4. `catch-catch-windows.zip`으로 압축
5. `softprops/action-gh-release`로 릴리스 자동 생성

---

## Server

이미지: `coals0329/catch-catch-server`

### 빌드 & Push

```bash
cd server
docker build --platform linux/amd64 -t coals0329/catch-catch-server:latest .
docker push coals0329/catch-catch-server:latest
```

- **반드시 `--platform linux/amd64`** — Mac(ARM)에서 빌드하므로 서버(amd64)용 플랫폼 명시 필수
- push 후 서버에서 `docker pull` + 컨테이너 재시작 필요

---

## Git 설정

- 개인 계정 커밋: `HongChaeMin <HongChaeMin@users.noreply.github.com>`
- Mac remote: `git@github-hongchaemin:HongChaeMin/catch-catch.git`
- Windows remote: `git@github-hongchaemin:HongChaeMin/catch-catch-windows.git`
