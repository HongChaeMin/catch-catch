# catch-catch

화면 위에 살아있는 고양이를 올려놓는 데스크톱 앱. 같은 방에 접속하면 친구의 고양이도 내 화면에 나타난다.

## Features

- **Bongo Cat Overlay** - 키보드/마우스 입력에 반응하는 고양이가 화면 위에 상주
- **멀티플레이어** - 방 코드로 접속하면 친구들의 고양이가 내 화면에 표시
- **채팅** - 고양이 클릭으로 말풍선 채팅
- **파워 모드** - 연속 타이핑 시 콤보 카운터 + 파티클 이펙트 (30/60/100/150 단계)
- **테마** - 회색, 흰색, 삼색 고양이 선택
- **위치 동기화** - ON/OFF 선택, OFF 시 다른 사람 고양이 드래그 가능

## Download

| Platform | Download |
|----------|----------|
| macOS | [Releases](https://github.com/HongChaeMin/catch-catch/releases) |
| Windows | [Releases](https://github.com/HongChaeMin/catch-catch-windows/releases) |

## Tech Stack

- **macOS** - Swift, SwiftUI, AppKit
- **Windows** - C#, WPF, .NET 8
- **Server** - Node.js, WebSocket

## How to Use

1. 앱 실행 (macOS: 메뉴바 아이콘, Windows: 시스템 트레이)
2. 방 코드 입력 또는 새 방 생성
3. 친구에게 코드 공유
4. 같이 코딩하면서 고양이 구경

## Build

### macOS

```bash
xcodegen generate
xcodebuild -scheme catch-catch -destination 'platform=macOS' -configuration Release build
```

### Windows

```bash
dotnet publish -c Release -r win-x64 --self-contained
```

### Server

```bash
cd server
npm install
node index.js
```

## Deploy

### macOS

```bash
# 1. 빌드
xcodegen generate
xcodebuild -scheme catch-catch -destination 'platform=macOS' \
  -derivedDataPath .claude/tmp/DerivedData -configuration Release build

# 2. 패키징
rm -rf build/catch-catch.app
cp -R .claude/tmp/DerivedData/Build/Products/Release/catch-catch.app build/catch-catch.app
codesign --force --sign - build/catch-catch.app

# 3. DMG (RW 템플릿에서 앱만 교체)
hdiutil attach build/dmg_rw.dmg -nobrowse
rm -rf "/Volumes/catch-catch/catch-catch.app"
cp -R build/catch-catch.app "/Volumes/catch-catch/catch-catch.app"
hdiutil detach "/Volumes/catch-catch"
rm -f build/catch-catch.dmg
hdiutil convert build/dmg_rw.dmg -format UDZO -o build/catch-catch.dmg

# 4. ZIP
cd build && rm -f catch-catch.zip && zip -r catch-catch.zip catch-catch.app && cd ..

# 5. 릴리스
unset GITHUB_TOKEN && gh release create vX.Y.Z \
  build/catch-catch.dmg build/catch-catch.zip \
  --title "vX.Y.Z" --notes "릴리즈 노트"
```

### Windows

태그 push만 하면 GitHub Actions가 자동 빌드 + 릴리스:

```bash
# csproj 버전 업데이트 후 커밋
git tag vX.Y.Z
git push origin main --tags
```

워크플로우(`.github/workflows/release.yml`)가 `v*` 태그에 반응하여 `dotnet publish` → zip → 릴리스 생성.

### Server

```bash
cd server
docker buildx build --platform linux/amd64 -t coals0329/catch-catch-server:latest --push .
# 서버에서 docker pull + 컨테이너 재시작
```
