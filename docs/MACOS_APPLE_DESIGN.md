# Dejavu macOS Apple-native design

이 문서는 macOS 제품의 UI 원칙을 고정한다. Windows 구현은 데이터 의미와 안정성 요구의 참고 자료일 뿐, macOS 화면의 시각 구조나 상호작용 템플릿이 아니다.

## 원칙

1. 시스템이 제공하는 `NSStatusItem`, `NSMenu`, SwiftUI Settings, WidgetKit, 표준 창과 컨트롤을 우선한다.
2. Windows와 공유하는 것은 provider 상태, 퍼센트 clamp, `--%`, reset freshness, atomic persistence, 개인정보 경계와 취소 semantics다.
3. Windows의 카드, 간격, 창 크기, 테마와 always-visible 동작을 macOS에 그대로 복제하지 않는다.
4. 시스템 서체, semantic color, material, Dynamic Type와 접근성 설정을 존중한다. 공급자 색상만으로 상태를 전달하지 않는다.
5. 기본 경험은 즉시 사용할 수 있어야 한다. 비필수 설정과 Claude 연결은 사용자가 해당 기능을 선택할 때 요청한다.
6. provider 식별에는 Anthropic의 Claude Spark와 OpenAI Blossom을 공통 템플릿 아이콘으로 사용한다. 메뉴 막대·플로팅 오버레이·small 위젯처럼 밀도가 높은 표면은 아이콘만 사용하고, 상세·설정·온보딩·medium 위젯처럼 설명이 필요한 표면은 동일 아이콘과 이름을 함께 사용한다. 아이콘은 semantic foreground color를 따르며 상태를 색상만으로 전달하지 않는다.

근거: [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials/).

## 표면별 역할

### 메뉴 막대

- `NSStatusItem.menu`와 표준 `NSMenu`를 사용한다.
- 일반 클릭으로 메뉴를 연다. 좌클릭과 우클릭에 서로 다른 핵심 동작을 배정하지 않는다.
- title 기본값은 `5h 38% · Codex 47%`다. Claude의 `5시간`, `주간`, `Fable`과 Codex 단일 퍼센트를 각각 독립적으로 켜고 끌 수 있다. Fable 값이 아직 없으면 `Fable --%`를 표시한다.
- 사용량 색상은 Windows와 같은 경계(70% 이상 warning, 90% 이상 danger)를 사용하되 macOS semantic orange/red로 렌더링한다. 브랜드 아이콘은 template color를 유지하고 숫자와 진행 막대만 같은 임계치 색으로 바꾼다.
- 메뉴에는 짧은 현재 상태, 상세 보기, 위젯 표시, 새로고침, 설정과 종료만 둔다.
- 메뉴를 동적으로 바꿀 때 `menuNeedsUpdate(_:)`를 사용한다. `menuWillOpen(_:)`에서 메뉴 구조를 변경하지 않는다.

근거: [`NSStatusItem.menu`](https://developer.apple.com/documentation/appkit/nsstatusitem/menu), [Menus](https://developer.apple.com/design/human-interface-guidelines/menus).

### 시스템 위젯

- WidgetKit extension으로 macOS 데스크탑과 알림 센터를 지원한다.
- `systemSmall`은 Claude 5시간/주간과 Codex 단일 퍼센트를 간결하게 표시한다. `systemMedium`은 같은 값에 진행률을 제공하고 공간이 허용되면 Claude Fable을 optional 정보로 추가한다. Codex에는 5시간 열이나 빈 공간을 만들지 않는다.
- 위젯은 읽기 전용의 glanceable snapshot만 사용한다. provider process를 위젯 extension에서 시작하지 않는다.
- 앱이 refresh를 완료한 뒤 allow-listed snapshot을 App Group에 원자적으로 저장하고 WidgetKit timeline을 reload한다.
- placeholder와 snapshot에는 합성 계정 정보나 실제 credential을 넣지 않는다. 누락값은 `--%`다.
- 앱 미서명 개발 build에서는 Application Support fallback으로 컴파일·preview할 수 있지만, 실제 데스크탑/알림 센터 배치는 서명된 App Group build로 검증한다.

근거: [WidgetKit](https://developer.apple.com/documentation/widgetkit), [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension), [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/).

### 플로팅 위젯

- 선택 기능이며 메뉴 막대-only 사용을 완전히 지원한다.
- 표시 중일 때만 nonactivating `NSPanel`로 동작한다. 앱 포커스를 훔치지 않는다.
- 표준 material, semantic color와 system typography를 사용한다. Windows 테마를 재현하지 않는다.
- Claude Fable 확장 접근이 켜졌거나 Fable 값이 존재하면 Claude 영역을 세 번째 metric slot으로 확장한다. 로딩·누락 중에는 `Fable --%`를 표시하고, 비활성 상태에서는 빈 slot을 남기지 않는다.
- 사용자가 끄면 panel만 숨기고 status item, refresh와 시스템 위젯은 유지한다.

### 상세

- provider별 그룹, 표준 `ProgressView`, reset 날짜와 상태를 읽기 쉬운 단일 창에 표시한다.
- Codex reset credit은 상세에만 둔다.
- 새로고침은 표준 toolbar command로 제공하고 오류는 복구 행동과 함께 간결하게 표시한다.

### 설정

- 앱 메뉴의 `Settings…`와 `Command+,`로 연다.
- 안정적인 pane navigation, 표준 `Form`, `Toggle`, `Picker`, `GroupBox`를 사용한다.
- 최소화·확대 버튼은 비활성화하고 최근 pane을 복구한다.
- provider 연결, 메뉴 막대, 위젯과 개인정보처럼 사용자가 이해하는 작업 단위로 묶는다.

근거: [Settings](https://developer.apple.com/design/human-interface-guidelines/settings).

### 온보딩

- 짧고 건너뛸 수 있어야 하며 기본 UI 사용을 막지 않는다.
- 먼저 메뉴 막대와 실제 Codex 자동 감지를 경험하게 하고, Claude status-line 변경은 별도 Connect 행동에서 설명한다.
- 기본 자격증명 비접근, Fable 확장 접근의 별도 동의, 로컬 snapshot 경계를 명확히 설명하고 긴 기능 소개는 설정 도움말로 미룬다.

근거: [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding), [Launching](https://developer.apple.com/design/human-interface-guidelines/launching).

## 실제 데이터 경계

- Codex: 제한 후보에서 찾은 로컬 executable의 공식 `codex app-server` stdio JSONL만 사용한다. Dejavu가 만든 child만 종료한다.
- Claude 기본 경로: 공식 status-line JSON의 `rate_limits`만 bridge가 추출한다. token, transcript, cwd와 session id는 모델링하거나 저장하지 않는다.
- Claude Fable 확장 경로: 기본값은 꺼짐이다. 사용자가 명시적으로 켜고 macOS가 허용한 경우에만 Claude Code Keychain item을 읽기 전용으로 요청하고 token을 메모리에서만 사용한다. 문서화되지 않은 usage endpoint의 Fable allow-list만 파싱하며 UI/DOM/Chrome storage를 scrape하지 않는다.
- Claude 설정 변경은 Settings의 명시적 Connect/Disconnect로만 수행한다. 기존 status line을 보존하고 chaining하며 user edit 충돌 시 자동 덮어쓰지 않는다.
- 메뉴 막대, 플로팅 오버레이와 WidgetKit 위젯은 하나의 `ApplicationState`에서 파생한 동일한 clamped 값을 사용한다.

근거: [Claude Code status line](https://code.claude.com/docs/en/statusline), [Codex App Server](https://developers.openai.com/codex/app-server).

## 검증 게이트

- 일반 클릭, 키보드 status menu focus와 VoiceOver로 메뉴가 열린다.
- Settings pane, 상세 창과 온보딩이 한국어/영어 및 light/dark에서 잘리지 않는다.
- 시스템 위젯은 small/medium, placeholder/real/missing/stale 상태를 검증한다.
- 위젯 off로 재시작할 때 플로팅 panel flash가 없다.
- 실제 Codex child와 Claude helper는 종료 후 orphan 0개다.
- 실제 provider fixture와 저장 파일에 credential, prompt, transcript와 cwd가 없다.
