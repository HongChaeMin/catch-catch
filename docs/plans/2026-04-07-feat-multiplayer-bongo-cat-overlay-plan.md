---
title: Multiplayer Bongo Cat Overlay App (catch-catch)
type: feat
status: active
date: 2026-04-07
---

# Multiplayer Bongo Cat Overlay App (catch-catch)

## Overview

타자 치거나 클릭할 때 고양이가 손을 흔드는 macOS 오버레이 앱. 룸 코드로 접속하면 같은 방의 다른 유저 고양이들도 내 화면에 오버레이로 보인다. mimo 프로젝트의 멀티모니터 오버레이 패턴을 재사용한다.

## Problem Statement

Bongo Cat처럼 타이핑할 때 고양이가 반응하는 앱을 만들되, 혼자가 아닌 여러 명이 함께 보며 쓸 수 있게 한다. 팀원들의 고양이가 내 화면에 동시에 떠 있으면서 각자 타이핑할 때마다 움직인다.

## Proposed Solution

두 컴포넌트로 구성:
1. **macOS 앱** (Swift/SwiftUI) — 항상 위에 떠있는 투명 오버레이. 전역 키보드/마우스 이벤트 감지 → 고양이 손 up/down 애니메이션. WebSocket으로 룸에 연결해 다른 유저 고양이도 표시.
2. **Node.js WebSocket 서버** — 룸 코드 생성/관리. 이벤트 릴레이. 클라우드 배포(Railway/Render).

---

## Technical Approach

### Architecture

```
[macOS App]
  ├── MenuBarExtra (설정, 룸 코드)
  ├── OverlayWindowController (mimo 패턴)
  │     └── NSWindow(borderless, .statusBar, ignoresMouseEvents, clear)
  │           └── NSHostingView → CatOverlayView (SwiftUI Canvas)
  ├── GlobalEventMonitor (keyDown/Up, mouseDown/Up)
  ├── CatStateManager (로컬 고양이 상태)
  └── WebSocketClient (URLSessionWebSocketTask)

[Node.js Server]
  ├── WebSocket Server (ws 라이브러리)
  ├── RoomManager (룸 코드 → 연결된 클라이언트 목록)
  └── 이벤트 릴레이 (join, state, leave)
```

### WebSocket 메시지 프로토콜

```jsonc
// Client → Server
{ "type": "join", "roomCode": "ABC123", "userId": "uuid-v4", "name": "채민" }
{ "type": "state", "x": 0.3, "y": 0.8, "active": true }   // 정규화 좌표 + 애니메이션 상태
{ "type": "leave" }

// Server → Client
{ "type": "joined", "users": [{ "userId": "...", "name": "...", "x": 0.3, "y": 0.8, "active": false }] }
{ "type": "user_joined", "userId": "...", "name": "..." }
{ "type": "user_left", "userId": "..." }
{ "type": "state", "userId": "...", "x": 0.3, "y": 0.8, "active": true }
{ "type": "error", "message": "Room not found" }
```

> **좌표 정규화**: 위치는 0.0~1.0 비율로 전송. 각 클라이언트가 자기 화면 크기에 맞게 역변환. 다른 해상도/모니터 크기 대응.

### 고양이 드래그 처리

오버레이 창은 `ignoresMouseEvents = true`라 직접 드래그 불가. **"고양이 이동 모드"** 를 메뉴바에 추가:
- 이동 모드 ON → `ignoresMouseEvents = false` → NSEvent 글로벌 마우스 드래그로 위치 업데이트
- 이동 모드 OFF → `ignoresMouseEvents = true` (기본값 복원)

### 고양이 스프라이트

| 파일 | 상태 |
|------|------|
| `image.png` | 손 올림 (타이핑 중) |
| `image (1).png` | 손 내림 (대기) |

keyDown / leftMouseDown → `active = true` → `image.png` 표시  
keyUp / leftMouseUp → `active = false` → `image (1).png` 표시  
디바운스: 마지막 이벤트 후 150ms 뒤에 idle로 복귀 (키 연속 입력 시 깜빡임 방지)

---

## Implementation Phases

### Phase 1: Xcode 프로젝트 + 오버레이 셸

**목표:** 고양이 이미지가 모든 모니터에 항상 위에 떠있는 상태

- [x] Xcode 프로젝트 생성 (`catch-catch`, macOS, SwiftUI, Bundle ID: `com.team.catch-catch`)
- [x] Info.plist: `NSInputMonitoringUsageDescription` 추가 (Input Monitoring 권한)
- [x] mimo의 `ScreenWindowController` + `MultiScreenDrawingController` 패턴 이식
  - `mimoApp.swift` 참조: borderless, `.statusBar`, `ignoresMouseEvents = true`, `canJoinAllSpaces`
- [x] `CatOverlayView.swift`: 고양이 이미지 표시 (위치 + active 상태 기반 이미지 선택)
- [x] 메뉴바 앱 구조: `MenuBarExtra` + `NSApp.setActivationPolicy(.accessory)`
- [x] Assets에 `cat_idle.png` / `cat_active.png` 추가 (image.png, image(1).png 이름 변경)

**파일 구조:**
```
catch-catch/
  catch-catchApp.swift          — @main, MenuBarExtra, OverlayController
  Managers/
    GlobalEventMonitor.swift    — NSEvent 글로벌 키/마우스 모니터
    WebSocketClient.swift       — URLSessionWebSocketTask 래퍼
  Models/
    CatState.swift              — ObservableObject: position, active, userId, name
    RoomState.swift             — 룸 내 유저 목록
  Views/
    CatOverlayView.swift        — Canvas 기반 고양이 렌더링
    MenuBarContentView.swift    — 메뉴바 팝오버 UI
  Assets.xcassets/
    cat_idle.imageset/
    cat_active.imageset/
server/
  index.js                      — Node.js WebSocket 서버
  package.json
```

**검증:** 고양이가 모든 모니터에 화면 우하단에 표시됨

---

### Phase 2: 고양이 애니메이션 + 드래그

**목표:** 타이핑/클릭 시 고양이 손 움직임, 위치 드래그 가능

- [x] `GlobalEventMonitor.swift`: NSEvent 글로벌 모니터 구현
- [x] `CatState.swift`: `@Published var isActive: Bool` + 150ms 디바운스 타이머
- [x] `CatOverlayView.swift`: `isActive` 기반으로 `cat_active` / `cat_idle` 이미지 전환
- [x] 이동 모드 토글 (메뉴바 버튼)
- [x] 위치 UserDefaults 저장 (앱 재시작 시 복원)

**검증:** 타이핑하면 고양이 손 올라감, 드래그로 위치 이동됨

---

### Phase 3: WebSocket 릴레이 서버

**목표:** 룸 코드로 클라이언트를 연결하는 Node.js 서버

- [x] `server/package.json`: `ws` 패키지
- [x] `server/index.js`: 룸 생성/조인, 릴레이, 빈 룸 삭제, PORT 환경변수
- [ ] Railway / Render 배포 설정 (`Procfile` 또는 `railway.json`)

**검증:** `wscat -c wss://server-url` 로 두 클라이언트 연결 → 메시지 릴레이 확인

---

### Phase 4: 멀티플레이어 클라이언트

**목표:** 룸에 접속해 다른 유저 고양이를 오버레이에 표시

- [x] `WebSocketClient.swift`: `URLSessionWebSocketTask` 기반, 재연결 로직 포함
- [x] `RoomState.swift`: `@Published var peers: [PeerCat]`
- [x] `MenuBarContentView.swift`: 룸 코드 UI (생성/참가/복사/참가자 목록)
- [x] `CatOverlayView.swift`: 로컬 + 피어 고양이 렌더링, 이름 레이블
- [x] 100ms 스로틀 state 전송

**검증:** 두 맥에서 같은 룸 코드 입력 → 서로의 고양이가 각자 화면에 보임

---

## Alternative Approaches Considered

| 방법 | 기각 이유 |
|------|----------|
| P2P (호스트 앱) | NAT 방화벽 문제, 다른 네트워크에서 연결 불가 |
| Multipeer Connectivity | 같은 로컬 네트워크만 지원 |
| 계정/로그인 방식 | 오버엔지니어링, 간단한 룸 코드로 충분 |
| Electron 앱 | 성능/메모리 불리, Swift가 macOS 오버레이에 최적 |

---

## System-Wide Impact

### Interaction Graph

```
keyDown → GlobalEventMonitor → CatState.isActive = true
        → WebSocketClient.send(state) → Server → broadcast → peers
        → CatOverlayView re-render (이미지 전환)
```

### Error & Failure Propagation

- WebSocket 연결 끊김: 로컬 고양이는 계속 동작, 피어 고양이는 freeze → 재연결 후 복원
- 서버 다운: 로컬 애니메이션은 영향 없음. 재연결 시도 후 메뉴바에 연결 상태 표시
- Input Monitoring 권한 거부: GlobalEventMonitor 초기화 시 감지 → 메뉴바에 경고 표시

### State Lifecycle Risks

- 앱 종료 시 WebSocket `leave` 메시지 전송 (`applicationWillTerminate` 또는 `NSApplicationWillTerminate` 알림)
- 위치 정규화: 메인 스크린 기준 0.0~1.0 → 수신측 스크린에 재매핑 (다른 해상도 안전)

---

## Acceptance Criteria

### Functional
- [ ] 타이핑/클릭 시 고양이 손이 올라갔다 내려옴 (150ms 디바운스)
- [ ] 고양이 위치를 드래그로 이동 가능, 앱 재시작 후 위치 유지
- [ ] 모든 연결된 모니터에 고양이 표시
- [ ] 룸 코드 입력으로 다른 유저와 연결
- [ ] 같은 룸 내 다른 유저 고양이가 내 화면에 표시됨
- [ ] 다른 유저 고양이 위에 이름 레이블 표시
- [ ] 유저 퇴장 시 해당 고양이 즉시 사라짐

### Non-Functional
- [ ] 오버레이 창이 다른 앱 클릭을 막지 않음 (`ignoresMouseEvents = true`)
- [ ] Dock/Cmd+Tab에 앱 아이콘 없음
- [ ] state 전송 100ms 스로틀 (초당 최대 10회)
- [ ] Input Monitoring 권한 없을 때 앱 크래시 없이 안내 표시

### Quality Gates
- [ ] GlobalEventMonitor: keyDown/keyUp/mouseDown/mouseUp 이벤트 테스트
- [ ] WebSocketClient: connect, send, receive, reconnect 테스트
- [ ] RoomState: user_joined, user_left, state 업데이트 테스트
- [ ] 좌표 정규화/역변환 수치 테스트

---

## Dependencies & Prerequisites

| 항목 | 비고 |
|------|------|
| mimo 소스 참조 | `mimoApp.swift`, `MouseRecorder.swift`, `DrawingView.swift` |
| Input Monitoring 권한 | 앱 첫 실행 시 시스템 권한 요청 |
| Node.js 18+ | 서버 실행 환경 |
| `ws` npm 패키지 | WebSocket 서버 |
| Railway / Render 계정 | 서버 배포 |
| 고양이 이미지 에셋 | `image.png` (손 올림), `image (1).png` (손 내림) |

---

## Sources & References

### Internal References
- 오버레이 창 패턴: `mimo/mimoApp.swift` — `ScreenWindowController`, `MultiScreenDrawingController`
- 글로벌 이벤트 모니터: `mimo/Managers/MouseRecorder.swift`
- Canvas 렌더링: `mimo/Views/DrawingView.swift`
- 고양이 에셋: `catch-catch/image.png`, `catch-catch/image (1).png`

### External References
- [URLSessionWebSocketTask (Apple Docs)](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask)
- [ws npm package](https://github.com/websockets/ws)
- [NSEvent.addGlobalMonitorForEvents (Apple Docs)](https://developer.apple.com/documentation/appkit/nsevent/1535472-addglobalmonitorforevents)
- [MenuBarExtra (Apple Docs)](https://developer.apple.com/documentation/swiftui/menubarextra)
