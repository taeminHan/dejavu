# Dejavu macOS 네이티브 구현 계획서

- 상태: 승인된 기술 방향으로 구현 진행 중
- 최초 작성: 2026-08-10
- 최종 갱신: 2026-08-13
- 대상 저장소: `taeminHan/dejavu`
- 기준 앱: 현재 Windows 11 WPF 버전 0.9.0
- 목표: 기존 Windows 앱을 보존하면서 SwiftUI와 AppKit으로 독립적인 macOS 공개 베타를 만든다.

## 0. 승인 경계

이 문서는 승인된 구현 방향과 아직 검증이 필요한 배포 경계를 함께 기록한다. Phase 0/1 기반 구현과 실제 provider 연결은 진행하되, 릴리스 작업은 별도 승인 경계를 유지한다.

다음 기술 방향은 확정된 것으로 본다.

- 언어: Swift 6
- UI: SwiftUI 중심, macOS 고유 창 수명주기에는 AppKit 사용
- 첫 지원 범위: macOS 14 이상, Apple Silicon
- 저장소: 현재 `dejavu` 저장소 안에 별도 `macos/` 트리 추가
- Windows 앱: 기존 WPF 구조와 설정 경로를 그대로 유지

Phase 0과 Phase 1 착수 및 Apple-native UI, 메뉴 막대 기본 동작, 선택형 플로팅 오버레이, WidgetKit 시스템 위젯과 실제 provider 연동 방향은 승인되었다. 커밋, 푸시, 태그, 서명, 공증, 배포와 GitHub Release 생성은 각각 별도 명시적 요청이 있기 전에는 수행하지 않는다.

## 1. 요약 결론

기존 계획의 `Avalonia + AppKit + 공통 .NET 코어` 방향을 폐기하고 완전한 macOS 네이티브 앱으로 전환한다.

1. 현재 루트의 WPF 앱은 이동하거나 대규모 리팩터링하지 않는다.
2. macOS 앱은 `macos/` 아래의 Xcode 앱 타깃, 로컬 Swift 패키지와 서명 가능한 보조 실행 파일로 구성한다.
3. 화면은 SwiftUI로 만들고 메뉴 막대, 플로팅 패널, 화면 좌표, 앱 활성화와 로그인 항목은 AppKit 및 ServiceManagement로 구현한다.
4. Windows와 macOS 구현은 소스 코드를 공유하지 않는다. 대신 민감정보가 제거된 JSON fixture, 상태 의미, 설정 스키마 문서와 레이아웃 불변조건을 공통 계약으로 공유한다.
5. Claude의 기본 원본은 사용자가 명시적으로 연결한 Claude Code 공식 status line이다. Fable은 공식 status line에 없으므로 사용자가 설정에서 별도로 켠 경우에만 Claude Code Keychain item을 읽기 전용으로 요청하고, 문서화되지 않은 usage endpoint를 격리된 확장 provider에서 사용한다.
6. Codex는 자격증명을 직접 읽지 않고 로컬 `codex app-server`의 공식 stdio JSONL 프로토콜을 사용한다.
7. 첫 베타는 Modern 테마, Apple Silicon, 직접 배포, Sparkle 2 업데이트로 제한한다.
8. 공개 베타까지 예상 기간은 단일 개발자 기준 약 8~12주다. Phase 0 실기기 검증 결과에 따라 범위와 일정은 다시 승인받는다.

네이티브 구현은 macOS UX와 수명주기 제어에는 가장 적합하다. 반면 C# 파서를 직접 재사용할 수 없으므로 플랫폼 간 의미가 어긋날 위험이 있다. 이 위험은 동일 fixture에 대한 양쪽 파서 테스트와 문서화된 상태 계약으로 통제한다.

## 2. 기존 계획에서 바뀌는 결정

| 항목 | 이전 제안 | 갱신 결정 |
|---|---|---|
| UI | Avalonia + 일부 AppKit | SwiftUI + AppKit 완전 네이티브 |
| 도메인 계층 | 공통 `.NET` 프로젝트 | 로컬 Swift 패키지 `DejavuKit` |
| Windows 구조 | 공통 코어 추출을 위해 재배치 | 현재 WPF 구조를 그대로 유지 |
| 코드 공유 | 상태·파서·설정 C# 공유 | fixture·JSON schema·상태 계약 공유 |
| 메뉴 막대 | Avalonia TrayIcon 후보 | AppKit `NSStatusItem` |
| 위젯 | Avalonia Window + AppKit bridge | 선택형 SwiftUI/AppKit 플로팅 오버레이 + WidgetKit 시스템 위젯 |
| 시작 시 실행 | AppKit bridge | `SMAppService.mainApp` |
| 업데이트 | Velopack 우선 | Sparkle 2 + 별도 macOS appcast |
| 패키지 | Velopack PKG/ZIP 검증 후 결정 | Developer ID로 서명·공증한 DMG, 업데이트용 ZIP |
| 테스트 | .NET 공통 테스트 | XCTest/Swift Testing + 실제 `NSHostingView` 레이아웃 probe |

## 3. 제품 범위

### 3.1 첫 공개 베타에 포함

- macOS 메뉴 막대 아이콘과 요약 메뉴
- 사용자가 표시 여부를 정할 수 있는 작은 플로팅 사용량 위젯(메뉴 막대-only 모드 지원)
- WidgetKit 기반 데스크탑 및 알림 센터 시스템 위젯(`systemSmall`, `systemMedium`)
- Claude만, Codex만, 둘 다, 둘 다 없음과 자동 감지 상태
- Claude의 5시간·주간 사용량과 Codex의 단일 주간 기반 사용량
- 사용자가 명시적으로 확장 접근을 켠 경우 Claude Fable 주간 사용량
- 제공되는 경우 각 사용량의 초기화 시각
- Codex 플랜과 초기화권 개수·만료 시각을 상세 화면에서만 표시
- 상세 보기, 설정, 첫 실행 온보딩
- Small, Compact, Comfortable 밀도
- 한 줄 및 두 줄 배치
- 진행률 표시 켜기/끄기
- 시스템/밝게/어둡게 외관과 Modern 테마
- 위젯 배경 투명도, 임계값 색상과 기본 색상 설정
- 자동 감지/Claude와 Codex/Claude만/Codex만 서비스 정책
- 60~300초 새로고침 간격
- 상단 오른쪽, 화면 오른쪽 아래, 사용자 지정 위치
- 로그인 시 실행
- 한국어와 영어, VoiceOver와 키보드 접근
- 로컬 진단 상태와 자격증명 없는 제한 로그
- Sparkle 2를 통한 수동 및 자동 업데이트
- 앱 안에서 Dejavu 데이터와 Claude bridge만 안전하게 초기화

### 3.2 첫 공개 베타에서 제외

- Intel Mac과 Universal 2 패키지
- Mac App Store 및 App Sandbox 배포
- Modern 이외의 다섯 Windows 테마
- Fable 이외의 임의 모델별 주간 한도
- Claude Keychain 또는 비공개 endpoint의 자동·무동의 접근
- Claude 앱 UI, 웹 DOM, 접근성 트리, Chrome 저장소와 대화 데이터 scraping
- 검증되지 않은 Claude Desktop history 자동 감지
- Codex 초기화권 소비 기능
- Windows와 macOS의 픽셀 단위 동일 디자인
- Windows 설정 파일의 자동 가져오기
- 원격 서버, 계정 동기화, 텔레메트리와 대화 내용 수집

## 4. 현재 Windows 기준 구현에서 보존할 계약

macOS 코드는 새로 작성하지만 다음 동작 의미는 Windows 기준 구현과 같아야 한다.

| 현재 책임 | macOS 보존 계약 |
|---|---|
| `ApplicationState.cs` | 공급자별 상태와 마지막 정상 snapshot을 하나의 불변 앱 상태로 결합 |
| `DesktopApplicationController.cs` | 새로고침 직렬화, 강제 새로고침 취소, 독립 공급자 오류, 명시적 종료 |
| `TraySettings.cs` | enum/수치 검증, 손상 파일 보존, 원자적 저장, 서비스 표시 정책 |
| `CodexUsageClient.cs` | app-server 격리, 공식 로그인, Dejavu가 만든 자식만 종료 |
| `ClaudeUsageClient.cs` | 퍼센트/초기화 의미만 참고하고 Windows 자격증명 방식은 이식하지 않음 |
| `ClaudeDesktopUsageReader.cs` | 읽기 전용 snapshot, 파일 핸들 조기 해제와 최신성 판단 원칙 |
| `WidgetLayoutCalculator.cs` | 크기와 공급자 간격을 하나의 순수 계산기에서 결정 |
| `UsageWidgetWindow*` | 사용자 위치 보존, 오른쪽 anchor, 클릭/드래그 분리, 항상 위 |
| `UsageDetailsWindow*` | reset credit은 상세 화면 전용 |
| `AppDiagnostics.cs` | 토큰·헤더·대화·브라우저 내용 없는 상태 기록 |

특히 다음 불변조건을 변경하지 않는다.

- 숨은 공급자는 열, 여백, 배지와 높이를 남기지 않는다.
- 공급자가 0개 또는 1개이면 두 줄 선택은 한 줄과 완전히 같은 구조와 크기다.
- 두 공급자 두 줄 배치에서는 Codex가 위, Claude가 아래다.
- 표시 퍼센트와 진행률 geometry는 같은 0~100 clamp 값을 쓴다.
- 값이 없으면 `--%`이며 이전 퍼센트와 길이 0인 bar를 조합하지 않는다.
- 로딩/오프라인 중 마지막 정상 snapshot을 유지할 수 있지만 상태를 함께 표시한다.
- reset credit은 위젯에 텍스트, 배지, 여백이나 예약 높이를 만들지 않는다.
- 사용자 지정 위치는 크기 변경 전 top-left를 보존하고 화면 밖으로 나갈 때만 보정한다.
- 기본 오른쪽 위치는 크기가 바뀌어도 선택한 화면의 오른쪽 여백을 유지한다.
- 보조 창을 닫아도 메뉴 막대 앱과 위젯은 종료되지 않는다.
- 명시적인 종료만 refresh 작업과 Dejavu 자식 프로세스를 정리하고 앱을 끝낸다.

## 5. 권장 저장소와 Xcode 구조

```text
dejavu/
  # 현재 Windows 파일은 위치와 동작을 유지
  ClaudeUsageTray.csproj
  *.xaml
  *.cs

  contracts/
    usage/
      README.md
      claude-status-snapshot.schema.json
      codex-rate-limits.schema.json
      fixtures/                  # 민감정보 제거 fixture만 저장

  macos/
    DejavuMac.xcodeproj
    Config/
      Debug.xcconfig
      Release.xcconfig
      DejavuMac.entitlements

    DejavuMac/
      App/
        DejavuApp.swift
        AppDelegate.swift
        AppCoordinator.swift
        AppModel.swift
      Features/
        MenuBar/
        Widget/
        Details/
        Settings/
        Onboarding/
        Updates/
      Platform/
        Windowing/
        Displays/
        LaunchAtLogin/
        ExternalLauncher/
      Resources/
        Assets.xcassets
        Localizable.xcstrings

    DejavuClaudeBridge/          # 서명 가능한 Swift CLI helper 타깃
      main.swift

    DejavuUsageWidget/           # macOS 데스크탑/알림 센터 WidgetKit extension
      DejavuUsageWidgetBundle.swift
      UsageTimelineProvider.swift
      UsageWidgetView.swift

    Packages/
      DejavuKit/
        Package.swift
        Sources/
          DejavuDomain/
          DejavuApplication/
          DejavuProviders/
          DejavuPersistence/
          DejavuWidgetShared/
        Tests/
          DejavuDomainTests/
          DejavuProviderTests/
          DejavuPersistenceTests/

    DejavuMacTests/
    DejavuMacUITests/
    Scripts/
      build-release.sh
      verify-app.sh
      generate-appcast.sh
```

`DejavuKit`은 Foundation만 의존하는 로컬 Swift 패키지다. AppKit과 SwiftUI 타입을 도메인 모델에 넣지 않는다. 앱 타깃은 `DejavuKit`을 사용하고, Claude helper는 bridge snapshot 형식만 공유한다. 외부 런타임 의존성은 업데이트를 위한 Sparkle 2 하나로 제한한다.

Xcode 프로젝트 파일과 Swift Package lock은 재현 가능한 빌드를 위해 저장소에 포함한다. 사용자별 Xcode 데이터, DerivedData, 서명 인증서, 공증 자격정보와 실제 provider snapshot은 포함하지 않는다.

## 6. 런타임 아키텍처

### 6.1 주요 타입과 소유권

| Swift 구성요소 | 책임 |
|---|---|
| `AppCoordinator` (`@MainActor`) | 앱 수명주기, 메뉴 막대, 창 controller, 명시적 종료의 composition root |
| `AppModel` (`@MainActor`, Observation) | 모든 SwiftUI 화면이 관찰하는 단일 `ApplicationState`와 설정 상태 |
| `UsageRefreshCoordinator` (`actor`) | refresh 직렬화, coalescing, 강제 취소와 공급자 병렬 실행 |
| `ClaudeStatusSnapshotProvider` (`actor`) | Dejavu bridge snapshot 읽기, 필드별 최신성 판단 |
| `ClaudeStatusBridgeManager` (`actor`) | 사용자 동의형 연결·검증·복구와 helper 갱신 |
| `ClaudeOAuthUsageClient` (`actor`) | 사용자가 켠 경우에만 Keychain credential을 메모리에서 사용해 Fable을 읽고 즉시 폐기 |
| `CodexExecutableLocator` | 제한된 후보에서 실행 가능한 Codex 경로 탐색 |
| `CodexAppServerClient` (`actor`) | 자식 process, JSONL handshake, rate limit과 로그인 |
| `SettingsStore` (`actor`) | 검증, 손상 파일 백업, 원자적 읽기·쓰기 |
| `DiagnosticsStore` (`actor`) | 자격증명 없는 상태와 제한 로그 원자적 기록 |
| `WidgetLayoutCalculator` | AppKit/SwiftUI를 모르는 순수 위젯 geometry 계산 |
| `WidgetPanelController` (`@MainActor`) | `NSPanel`, 위치, display 변경, 클릭과 drag |
| `StatusItemController` (`@MainActor`) | `NSStatusItem`, 요약 메뉴와 사용자 명령 |
| `WidgetSnapshotStore` | App Group의 최소 allow-list snapshot 원자 저장·읽기 |
| `UsageTimelineProvider` | provider를 실행하지 않고 공유 snapshot만 읽는 WidgetKit timeline |
| `UpdateCoordinator` (`@MainActor` + actor state) | Sparkle 수동/자동 확인, 정각 schedule과 중복 억제 |

뷰는 공급자, 파일과 프로세스를 직접 호출하지 않는다. 모든 UI 변화는 `AppModel`을 통해 MainActor에서 일어나고, AppKit 객체는 MainActor 밖으로 전달하지 않는다. Swift 6 strict concurrency 경고를 오류로 취급한다.

### 6.2 상태 모델

공통 의미를 다음 Swift 값으로 다시 정의한다.

```text
UsageStatus
  loading | ready | loginRequired | rateLimited | offline | error | unavailable

UsageLimit
  percent: Double
  resetsAt: Date?

ClaudeUsageSnapshot
  fiveHour | weekly | optional fable | source | capturedAt

CodexUsageSnapshot
  weekly | resetCredits | resetCreditsExpireAt | planType

ApplicationState
  combinedStatus
  claudeStatus/message/snapshot
  codexStatus/message/snapshot
  updatedAt/retryAt
```

저장용 enum은 숫자 ordinal이 아니라 안정적인 영문 문자열로 encode한다. UI에 전달하기 전에 `displayPercent`를 한 번만 clamp하고 텍스트와 progress가 같은 값을 사용한다.

### 6.3 새로고침과 취소

`UsageRefreshCoordinator`는 Windows 안정성 계약을 Swift structured concurrency로 옮긴다.

1. 주기 refresh가 이미 실행 중이면 새 작업을 만들지 않고 현재 작업을 공유한다.
2. 사용자 강제 refresh는 현재 작업을 취소하고 실제 종료를 기다린 뒤 새 작업을 시작한다.
3. Claude 파일 읽기와 Codex app-server 요청은 `async let` 또는 throwing task group으로 동시에 실행한다.
4. 각 공급자의 cancellation은 상태 오류로 변환하지 않고 다시 throw한다.
5. 한 공급자 실패가 다른 공급자의 정상 snapshot을 지우지 않는다.
6. loading/offline/error 중 이전 정상 값은 유지할 수 있다.
7. 종료 시 coordinator가 owned task를 취소하고 자식 process가 끝난 뒤 창과 앱을 정리한다.
8. 취소된 작업과 종료 후 continuation은 `AppModel`을 갱신하지 않는다.

## 7. macOS 네이티브 UI 설계

### 7.1 앱과 메뉴 막대 수명주기

- `NSStatusItem`과 표준 `NSMenu`를 사용한다. 동적 퍼센트 title, 명시적인 앱 수명주기와 숨김 정책을 제어하기 위해 `MenuBarExtra`를 기본 선택으로 사용하지 않는다.
- 메뉴에는 최신 Claude/Codex 요약, `상세 보기`, `새로고침`, `설정…`, `업데이트 확인…`, `종료`를 둔다.
- 상태 항목의 기본 title은 `5h 38% · Codex 47%`처럼 Claude 5시간과 Codex의 단일 주간 기반 사용량을 한 줄로 표시한다. Claude는 설정에서 `5시간`, `주간`, `숨김`을 선택하고 Codex는 단일 퍼센트의 표시 여부만 선택한다. Codex에는 `5h` 또는 `7d` 접미사를 붙이지 않는다. 표시 중인 값이 없으면 `--%`를 사용하고, 숨겨진 공급자는 title 공간을 남기지 않는다. 둘 다 숨기면 Dejavu 아이콘만 남겨 메뉴 막대 진입점을 유지한다.
- 상태 항목 title은 refresh로 `ApplicationState`가 바뀐 직후 갱신하며, 표시 문자열과 VoiceOver accessibility value는 항상 같다.
- 상태 항목은 위젯 표시 여부와 관계없이 앱의 영구 진입점으로 남는다. 설정에서 위젯을 끄면 플로팅 패널만 즉시 숨기고, 다시 켜면 마지막 위치를 유지한 채 표시한다. 저장된 꺼짐 상태로 시작할 때 패널을 먼저 띄웠다가 숨기는 flash가 없어야 한다.
- 상태 항목은 Apple의 표준 `NSStatusItem.menu` 동작을 사용해 일반 클릭으로 요약·명령 메뉴를 연다. 별도의 좌·우 클릭 분기를 만들지 않으며 상세 보기는 메뉴의 명시적인 항목으로 연다. 퍼센트 title이나 위젯을 숨겨도 상태 항목 아이콘은 남아 설정 진입점을 잃지 않는다.
- 상태 항목이 숨겨졌을 때 새 update가 있으면 같은 version당 한 번만 update decision window를 fallback으로 연다.
- `LSUIElement` 또는 `.accessory` activation policy를 사용해 평상시 Dock 아이콘을 숨긴다.
- 설정·상세 창을 열 때 정상 포커스, VoiceOver와 `Command+,`가 보장되는지 Phase 0에서 검증한다. accessory policy로 충족되지 않으면 보조 창이 열린 동안만 `.regular`로 전환하는 fallback을 사용한다.
- LaunchServices의 기본 재사용 동작에 더해 사용자별 Application Support lock과 distributed activation 신호를 둔다. 직접 binary를 두 번 실행해도 두 번째 process는 첫 process의 설정을 열고 종료한다.
- 다른 macOS 사용자 세션까지 막는 전역 single-instance 설정은 사용하지 않는다.
- 보조 창의 닫기 버튼은 창만 숨기고 앱을 종료하지 않는다. `Command+Q`와 메뉴의 `종료`만 앱을 끝낸다.

### 7.2 플로팅 오버레이

플로팅 오버레이는 SwiftUI content를 `NSHostingView`로 감싼 borderless `NSPanel`이다. macOS에서는 선택 기능이며, 메뉴 막대-only 모드에서도 refresh·상세·설정·종료가 모두 가능해야 한다. 이 기능은 사용자가 macOS 위젯 갤러리에서 배치하는 WidgetKit 시스템 위젯과 별개다.

- panel level은 일반 창보다 높은 `.floating`을 사용한다.
- 패널은 기본적으로 앱을 활성화하거나 키보드 포커스를 빼앗지 않는다.
- `canJoinAllSpaces`, 전체 화면 보조 창, Stage Manager 관련 collection behavior 조합은 Phase 0 실제 기기에서 확정한다.
- lock screen, secure input, 화면 보호기와 다른 앱의 의도적인 topmost 창보다 앞에 보이는 것은 보장하지 않는다.
- 클릭은 상세 보기를 열고, 시스템 drag threshold를 넘은 이동은 창만 옮긴다.
- 배경 material/색상의 alpha만 바꾸며 텍스트, 아이콘, border와 progress 자체 opacity는 1.0을 유지한다.
- Retina와 fractional scale에서 텍스트가 흐려지지 않도록 정수 pixel boundary와 실제 backing scale을 고려한다.

위치는 AppKit의 bottom-left 좌표를 그대로 저장하지 않는다. 선택한 display 식별자, visible frame 기준 top-left와 placement mode를 논리 point로 저장한다.

- Custom: resize 전 top-left 유지 후 visible frame으로 clamp
- TopRight: resize 후 오른쪽 margin과 위쪽 margin 재계산
- ScreenRightBottom: resize 후 오른쪽·아래쪽 margin 재계산
- display 분리: 기존 display가 없으면 가장 가까운 visible screen으로 이동 후 clamp
- display/해상도/배율 변경: 현재 placement 규칙으로 한 번만 재배치

### 7.3 WidgetKit 시스템 위젯

- `DejavuUsageWidget` extension은 macOS 14 이상의 데스크탑과 알림 센터에서 `systemSmall`, `systemMedium`을 지원한다.
- 위젯의 배치·크기·제거는 macOS와 사용자가 소유한다. 앱이 프로그래밍으로 데스크탑에 위젯을 놓거나 제거한다고 표현하지 않는다.
- extension에서는 Claude helper, Keychain, 네트워크 또는 Codex app-server를 실행하지 않는다.
- 메인 앱이 성공적으로 refresh한 뒤 credential·account·prompt·path가 없는 `WidgetUsageSnapshot`만 App Group에 원자적으로 저장하고 timeline reload를 요청한다.
- WidgetKit의 시스템 margin, container background, semantic color와 privacy redaction을 사용하며 플로팅 오버레이의 고정 geometry를 재사용하지 않는다.
- snapshot이 없거나 손상·만료됐으면 이전 퍼센트를 재사용하지 않고 `--%`와 앱을 열어 갱신하라는 안내를 표시한다.
- 정확한 60초 갱신을 약속하지 않는다. 앱 refresh 직후의 reload 요청과 WidgetKit budget을 존중하는 fallback timeline을 함께 사용한다.
- 실제 위젯 갤러리 표시와 App Group 공유는 같은 Team/App Group entitlement로 서명한 설치 build에서 검증한다. unsigned build 성공은 compile 검증일 뿐이다.

### 7.4 플로팅 오버레이 레이아웃 계산

`WidgetLayoutCalculator` 입력은 다음 값 전체를 포함한다.

```text
density
requestedLayout
showClaude
showCodex
showProgress
appearance
contentSizeCategory/accessibilityTextScale
```

출력은 panel width/height, effective layout, provider gap, metric gap과 progress footprint를 소유한다. view나 controller에 크기 공식을 중복하지 않는다.

Windows DIP 수치를 그대로 복사하지 않고 macOS의 SF Pro와 SwiftUI intrinsic size에 맞춘다. 그러나 서비스 숨김, 0/1 공급자 layout 동등성, 두 줄 순서, progress footprint 제거와 한국어 무잘림 계약은 그대로 유지한다.

Small 밀도의 intrinsic 기준은 기존과 같은 48pt metric cell과 30pt ring이다. 두 공급자 한 줄일 때만 provider 사이 8pt를 사용하고 Codex-only에는 선행 provider gap을 두지 않는다. 실제 font fitting으로 이 수치를 늘려야 할 때는 calculator, probe와 이 문서를 함께 변경한다.

### 7.5 상세, 설정과 온보딩

- 상세 창: Claude의 5시간/주간 값과 Codex의 단일 주간 기반 값 및 reset 시각을 표시한다. Codex reset credit과 만료는 이 창에만 둔다. SwiftUI를 호스팅한 transient `NSPanel`로 구현해 위젯 또는 status item에 가깝게 배치하고 visible frame 안으로 clamp한다.
- 설정 창: 일반, 공급자, 위젯, 업데이트, 개인정보/진단 탭으로 나눈다.
- 첫 실행: 로컬 전용 데이터 처리, Codex 자동 감지 결과와 Claude bridge 연결 선택을 설명한다.
- Claude bridge는 자동으로 설치하지 않는다. 사용자가 설명을 읽고 `Claude 연결`을 누른 뒤에만 설정을 변경한다.
- Fable은 확장 접근을 켠 경우 상세 화면에서 독립적인 optional limit으로 표시한다. 메뉴 막대와 작은 시스템 위젯의 기본 두 지표 공간을 강제로 바꾸지 않는다.
- Codex 실행 파일이 없으면 공식 설치 안내를 표시한다.
- `로그인 시 실행`은 `SMAppService.mainApp.status`를 그대로 반영하고 승인이 필요하면 시스템 로그인 항목 화면을 연다.
- 한국어/영어 문구는 String Catalog에서 관리한다. 날짜·시간·숫자는 현재 locale과 time zone을 사용한다.
- 모든 icon-only control, percentage와 progress에 VoiceOver label/value를 제공한다. Reduce Motion, Increase Contrast와 Reduce Transparency도 확인한다.

## 8. Claude 연동

### 8.1 허용된 데이터 원본과 동의 경계

macOS의 Claude Code 자격증명은 암호화된 Keychain에 저장된다. 기본 provider는 Keychain item, OAuth token, authorization header와 비공개 usage endpoint에 접근하지 않는다.

Mac v1의 Claude 원본은 공식 status line JSON의 다음 필드뿐이다.

```text
rate_limits.five_hour.used_percentage
rate_limits.five_hour.resets_at
rate_limits.seven_day.used_percentage
rate_limits.seven_day.resets_at
bridge capture timestamp
```

공식 동작상 `rate_limits`는 Claude.ai Pro/Max 사용자가 세션에서 첫 API 응답을 받은 뒤에만 나타날 수 있고 두 window가 각각 없을 수도 있다. status line은 신뢰한 workspace에서만 실행되며 Claude 활동이 없으면 값이 갱신되지 않는다. UI와 온보딩에서 이를 제한사항으로 명시한다.

공식 status line에는 Fable 모델별 한도가 없다. 사용자가 Settings의 `Fable 사용량 활성화`를 직접 켠 경우에만 다음 격리 경계를 적용한다.

- macOS Keychain의 Claude Code credential item을 시스템 승인 아래 읽기 전용으로 요청한다.
- access token은 요청 메모리에서만 사용하고 설정, snapshot, Widget App Group, diagnostics와 로그에 저장하지 않는다.
- 문서화되지 않은 Claude usage endpoint 응답에서 Fable로 명시된 model-scoped weekly limit만 allow-list 파싱한다.
- 권한 거부, 로그인 만료, endpoint/schema 변경은 Fable을 unavailable로 처리하고 가능한 경우 공식 status-line 5시간/주간 값으로 fallback한다.
- 이 기능은 변경 가능성이 있음을 설정과 릴리스 노트에 표시하며 기본값은 꺼짐이다.
- Claude 앱 UI, DOM, 접근성 트리, Chrome storage, browser session과 대화는 대체 원본으로 사용하지 않는다.

Claude Desktop의 `~/Library/Application Support/Claude/plan-usage-history.json` fallback은 Phase 0 실측에서 파일, schema와 최신성 의미가 Windows와 같다고 확인될 때만 별도 승인 후 추가한다. 확인 전에는 파일 존재만으로 설치나 사용 가능 상태를 추론하지 않는다.

### 8.2 status line bridge

`DejavuClaudeBridge`는 작고 서명된 Swift command-line helper다.

연결 흐름:

1. 사용자 동의 후 `~/.claude/settings.json`의 user-level `statusLine`과 관련 옵션을 읽는다.
2. managed/project 설정, `disableAllHooks`, 잘못된 JSON과 쓰기 권한을 사전 점검한다.
3. 기존 status line이 있으면 전체 객체와 원래 command를 Dejavu bridge metadata에 보존한다.
4. 앱 bundle 안의 서명된 helper를 `~/Library/Application Support/dejavu/bin/`에 원자적으로 설치한다.
5. user settings의 command만 stable helper 경로로 바꾸고 padding/refresh 옵션은 보존한다.
6. helper는 stdin 원본을 메모리에서 한 번 읽고 필요한 네 필드만 snapshot에 원자적으로 쓴다.
7. 기존 command가 있으면 동일한 stdin, cwd와 environment로 실행하고 stdout/stderr/exit 의미를 전달한다.
8. 입력 원본, cwd, repository, session id, transcript path, prompt와 대화는 디스크나 로그에 남기지 않는다.

해제와 초기화:

- 현재 `statusLine`이 Dejavu가 기록한 managed 값과 정확히 같을 때만 원래 객체를 복구한다.
- 연결 후 사용자가 status line을 수정했다면 덮어쓰지 않고 충돌 상태와 수동 복구 방법을 보여준다.
- backup 없이 임의 값을 삭제하지 않는다.
- helper와 bridge snapshot은 Dejavu 데이터 초기화 때만 제거한다.
- 앱 업데이트 시 helper를 sibling temporary file로 교체하며 실패하면 기존 정상 helper를 유지한다.
- Claude 전체 설정 파일도 sibling temporary file과 atomic replace로 저장하고 원본 permission을 유지한다.

### 8.3 snapshot 최신성

단순히 0%로 fallback하지 않는다.

- 각 window 값은 해당 `resets_at`을 지나면 새 snapshot이 올 때까지 `--%`로 바꾼다.
- reset 시각이 없는 값은 보수적인 TTL 후 unavailable로 바꾼다.
- 시스템 시각이 capture 시각보다 비정상적으로 과거이면 snapshot을 거부한다.
- 첫 유효 입력 전에는 `확인 전` 또는 `Claude에서 첫 응답 후 표시` 상태를 사용한다.
- 동시에 여러 Claude 세션이 helper를 호출해도 atomic replace와 capture ordering으로 부분 JSON과 오래된 역전 기록을 막는다.

## 9. Codex 연동

### 9.1 실행 파일 탐색

다음 순서로 제한된 후보만 검사한다.

1. 유효한 `CODEX_CLI_PATH`
2. `~/.local/bin/codex`
3. Apple Silicon Homebrew와 일반 `/usr/local` 후보
4. npm, nvm, Volta, asdf/fnm의 제한된 설치 후보
5. GUI 앱에서 받은 `PATH`의 직접 `codex` 후보
6. Phase 0에서 실측한 Codex Desktop `.app` bundle 후보

모든 후보는 파일 존재, 실행 권한, symlink 해석과 실제 `app-server` 시작 smoke test로 검증한다. home directory 전체를 재귀 검색하지 않는다. Desktop bundle 내부의 단일 버전 경로를 영구 하드코딩하지 않는다.

### 9.2 app-server protocol

2026-08-12 현재 공식 계약에 맞춰 다음 stable surface만 사용한다.

1. 명시적인 Codex executable을 `Process`로 `app-server` 인자와 함께 실행한다.
2. 기본 stdio newline-delimited JSON transport를 사용한다. experimental WebSocket은 사용하지 않는다.
3. 한 connection당 `initialize`를 한 번 보내고 성공 응답을 확인한 뒤 `initialized` notification을 보낸다.
4. `clientInfo`에 `dejavu`, 표시명과 앱 버전을 제공한다.
5. `account/rateLimits/read`를 요청한다.
6. `rateLimitsByLimitId["codex"]`가 있으면 그 bucket만 우선한다.
7. multi-bucket이 없을 때만 backward-compatible `rateLimits`를 사용한다.
8. 선택한 Codex bucket에서는 주간 window만 제품 snapshot으로 정규화한다. primary 5시간 window는 app-server transport 호환을 위해 파싱할 수 있지만 UI·저장·Widget snapshot으로 내보내지 않는다.
9. 관련 없는 `codex_other` bucket을 시간 길이만으로 섞지 않는다.
10. `rateLimitResetCredits.availableCount`가 authoritative count이며 상세 row는 보조 정보로만 사용한다.

stdout JSONL reader는 최대 line 크기, request id, EOF, malformed JSON과 timeout을 검사한다. stderr는 pipe deadlock이 없도록 계속 drain하되 credential이나 원문을 로그에 쓰지 않고 종료 코드와 분류된 오류만 남긴다.

### 9.3 로그인과 process 수명주기

- 로그인은 사용자 action으로만 `account/login/start`의 `type=chatgpt`를 호출한다.
- 반환된 `authUrl`만 `NSWorkspace`로 열고 `account/login/completed`를 기다린다.
- browser callback이 불안정한 환경을 위해 공식 `chatgptDeviceCode` flow의 fallback 여부를 Phase 0에서 결정한다.
- rate-limit 읽기는 15초, 로그인은 5분의 상한을 두고 사용자 취소를 지원한다.
- refresh마다 짧게 app-server를 시작하고 종료하는 방식을 v1 기본으로 한다. persistent process는 실측 필요가 확인될 때만 도입한다.
- 정상 종료는 stdin close와 graceful terminate를 먼저 시도하고 제한 시간 뒤 Dejavu가 만든 PID만 강제 종료한다.
- `pkill`, process name 검색과 Codex Desktop 종료는 절대 사용하지 않는다.
- 앱 종료와 task cancellation 테스트에서 orphan process가 0개인지 확인한다.

## 10. 로컬 저장과 개인정보

모든 macOS 데이터는 다음 경로 아래에 둔다.

```text
~/Library/Application Support/dejavu/
  settings.json
  status.json
  diagnostics.log
  claude-status.json
  claude-bridge.json
  bin/dejavu-claude-bridge
  settings.corrupt-YYYYMMDD-HHMMSS.json
```

시스템 위젯에는 별도로 App Group container의 최소 allow-list snapshot을 사용한다. Widget extension은 위 Application Support 파일이나 provider credential에 접근하지 않는다.

| 데이터 | 정책 |
|---|---|
| `settings.json` | 안정적인 string enum, 수치 clamp, sibling temp 후 atomic replace |
| 손상 설정 | 이름을 바꾸어 보존하고 normalized default로 계속 시작 |
| `status.json` | provider 상태, 퍼센트, reset, 시간, geometry와 source availability만 저장 |
| `diagnostics.log` | 256 KiB 상한과 `diagnostics.previous.log` rotation, 분류된 오류만 저장 |
| Claude snapshot | 공식 status-line의 네 usage 필드와 capture/schema version만 저장 |
| bridge metadata | 원래 statusLine 복구에 필요한 값과 managed 값 hash만 저장 |
| Widget snapshot | provider 상태, Claude 5시간/주간/Fable optional 퍼센트, Codex 단일 퍼센트와 갱신 시각만 App Group에 저장 |
| provider credential | 기본 provider는 읽지 않음. Fable opt-in 요청은 Keychain에서 메모리로만 읽고 저장·로그하지 않음 |
| prompt/대화/transcript/cwd | 읽은 입력에서 추출하거나 저장하지 않음 |

Application Support directory는 현재 사용자만 접근하도록 만들고 민감할 수 있는 metadata와 snapshot은 `0600`을 유지한다. 로그 API를 사용할 때 동적 값은 기본적으로 private로 표시한다. fixture 작성 도구와 테스트는 token, authorization header, account id, URL query와 대화 형태 문자열이 포함되면 실패해야 한다.

`Dejavu 데이터 초기화`는 다음 순서를 지킨다.

1. 로그인 항목 해제
2. 현재 managed Claude bridge인지 비교 후 안전 복구
3. refresh와 자식 process 종료
4. Dejavu 설정, snapshot, 로그와 helper만 제거

Claude, Codex, Keychain, 브라우저, 셸 설정과 provider 대화는 삭제하지 않는다. 앱을 휴지통으로 옮기는 것만으로 Application Support 데이터가 지워진다고 표현하지 않는다.

## 11. 업데이트, 서명과 배포

### 11.1 업데이트

네이티브 앱에는 Sparkle 2를 Swift Package Manager로 추가한다.

- macOS 전용 appcast와 EdDSA update signature를 사용한다.
- Sparkle 자체 자동 interval 대신 `UpdateCoordinator`가 Windows와 같은 다음 local wall-clock hour를 계산한다.
- 설치된 release build이고 사용자 설정이 켜진 경우에만 시작 후와 정각에 background check를 요청한다.
- startup/hourly/manual 요청은 하나의 in-flight session을 공유한다.
- 자동 current/offline/error 결과는 조용히 처리하고 수동 확인은 결과를 보여준다.
- 같은 version의 자동 알림은 restart 후에도 한 번만 표시한다.
- sleep/resume과 system clock 변경은 overdue check를 최대 한 번 수행한 뒤 다음 정각으로 재정렬한다.
- 자동 확인을 끄면 schedule을 즉시 중지하고 이미 진행 중인 결과의 자동 알림을 억제한다.
- 개발 및 ad-hoc build는 release appcast를 자동 확인하지 않는다.

### 11.2 직접 배포

첫 베타 배포 형식은 다음과 같다.

- 다운로드: 서명·공증·staple된 `Dejavu-macOS-arm64.dmg`
- Sparkle payload: 서명된 `.app`을 담은 EdDSA 서명 ZIP
- 설치 안내: `/Applications`로 drag
- 채널: 별도 macOS arm64 beta appcast

`.pkg`를 사용하지 않으므로 첫 베타에는 Developer ID Installer 인증서가 필요하지 않다. 향후 PKG를 추가할 때만 별도 결정한다.

배포 전제:

- Apple Developer Program
- Developer ID Application 인증서
- Hardened Runtime과 secure timestamp
- app, Sparkle framework/XPC 및 helper를 안쪽부터 올바른 identity로 서명
- `notarytool` 제출, 승인 확인과 ticket staple
- `codesign --verify`, `spctl --assess`와 `stapler validate`
- Sparkle EdDSA private key의 안전한 CI secret 관리

서명과 공증이 성공하기 전에는 GitHub Release asset이나 appcast를 게시하지 않는다. Windows SignPath와 Apple Developer ID는 별도 체계다.

## 12. 구현 단계

### Phase 0 — 네이티브 feasibility와 계약 고정 (3~5일)

작업:

- 실제 Apple Silicon Mac에서 Claude Code/Claude Desktop/Codex CLI/Codex Desktop 조합 확인
- Claude Code status line의 rate-limit 입력, trust, 기존 command chaining과 복구 검증
- 민감정보를 제거한 Claude 및 Codex fixture 생성
- Codex executable 후보와 Desktop bundle, handshake와 login 실측
- `NSStatusItem`, `NSPanel`, Spaces, full-screen과 Stage Manager prototype
- accessory activation에서 설정/상세 포커스와 `Command+,` 확인
- Sparkle unsigned local feed와 DMG/ZIP prototype
- Xcode build/test와 Windows CI 경계를 문서화

현재 개발 Mac에는 Swift 6.3.3, Xcode 26.6과 macOS SDK 26.5가 설치되어 있고 Xcode license 동의도 확인했다. active developer directory는 아직 Command Line Tools이므로 build script와 CI에서는 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`를 명시한다. 사용자가 나중에 `xcode-select`를 전환하더라도 build 결과가 달라지지 않아야 한다. 이 Mac에는 .NET SDK가 없으므로 Windows WPF 회귀 build는 Windows CI 또는 별도 Windows 환경에서 수행한다.

완료 조건:

- Claude bridge와 Codex app-server에서 실제 사용량 fixture를 각각 확보
- 기존 status line 연결·해제 왕복 후 byte/semantic 손실이 없거나 알려진 formatting 변화가 승인됨
- widget prototype이 Retina, Spaces와 전체 화면에서 포커스를 훔치지 않음
- app-server 취소 후 orphan process 0개
- unsigned `.app` build와 단위 테스트 성공
- 기술 검증 결과와 변경된 범위를 사용자에게 다시 승인받음

중단 조건:

- 두 공급자 모두 신뢰할 수 있는 로컬 usage 원본을 확인하지 못함
- Claude 설정을 안전하게 보존·복구할 수 없음
- 과도한 macOS 권한 없이는 핵심 기능 구현이 불가능함
- 위젯을 켠 상태의 플로팅 패널이 일반 작업을 방해하지 않는 수준으로 동작하지 않음

### Phase 1 — Swift 구조와 핵심 계약 (약 1주)

작업:

- `macos/DejavuMac.xcodeproj`와 `DejavuKit` 생성
- 상태 모델, service resolution, layout calculator와 freshness policy 구현
- `SettingsStore`, `DiagnosticsStore`와 atomic file writer 구현
- refresh coordinator와 fake provider 구현
- 공유 fixture/schema와 parser test harness 추가
- 한국어/영어 String Catalog 기본 구조 추가
- macOS build/test GitHub Actions job 초안 추가

완료 조건:

- Swift 6 strict concurrency build warning 0개
- 단위 테스트와 fixture 계약 테스트 성공
- 손상 설정이 보존되고 앱은 default로 계속 시작
- Windows 파일과 기존 설정 경로에 동작 변경 없음
- Windows Release build가 Windows 환경에서 성공

### Phase 2 — 공급자와 bridge (1~2주)

작업:

- Claude helper, user-consent 연결, chaining, 충돌 감지와 복구 구현
- reset-aware Claude snapshot 최신성 구현
- Codex locator, JSONL client, parser와 browser login 구현
- provider 독립 오류 mapping과 이전 정상 snapshot 유지
- 강제 refresh, timeout, 앱 종료와 process cleanup 구현

완료 조건:

- Claude만, Codex만, 둘 다, 둘 다 없음 재현
- loading, ready, partial, login required, rate limited, offline, malformed 재현
- 토큰·대화·cwd가 설정, 로그와 fixture에 없음
- 연결 해제와 데이터 초기화가 provider 데이터를 건드리지 않음
- cancellation과 종료 후 orphan helper/app-server 0개

### Phase 3 — 메뉴 막대와 MVP UI (2~3주)

작업:

- status item과 앱 수명주기
- NSPanel widget과 위치 복구
- 상세, 설정, 온보딩
- 모든 density/layout/service/progress 상태
- Appearance, opacity, color, threshold와 placement 설정
- VoiceOver, keyboard, Reduce Motion/Transparency/Contrast 대응

완료 조건:

- 필수 layout probe와 UI 상태 행렬 성공
- reset credit이 상세에만 존재
- custom/top-right/bottom-right anchor가 모든 size change에서 유지
- 한국어·영어가 Small에서도 잘리지 않음
- 설정과 상세를 닫아도 앱과 메뉴 막대가 계속 실행되고, 위젯 표시 선택이 유지됨
- 두 번째 실행이 첫 앱의 설정을 열고 종료

### Phase 4 — macOS 통합과 제품화 (1~2주)

작업:

- `SMAppService` 로그인 항목
- Sparkle 2와 정각 update coordinator
- Developer ID 서명, Hardened Runtime, DMG/ZIP, 공증과 staple 자동화
- 데이터 초기화와 제거 안내
- README, 개인정보, 보안, 아키텍처와 개발 문서 갱신

완료 조건:

- 깨끗한 Mac에서 우회 경고 없이 drag-install과 첫 실행 성공
- 이전 beta에서 다음 beta로 update하고 설정·위치 유지
- update 실패와 취소 후 기존 app 정상 실행
- 로그인 항목 on/off와 재부팅 후 상태 일치
- data reset 후 Dejavu 항목만 제거

### Phase 5 — 공개 베타 QA (약 1주)

작업:

- 소규모 실제 사용자 beta
- 장시간 refresh, 네트워크 전환, sleep/resume, time change
- Retina/외부 화면/분리/배율/Spaces/full-screen/Stage Manager
- provider update로 경로나 schema가 달라진 경우의 fallback
- Windows 회귀와 문서 최종 대조

완료 조건:

- P0 crash, 데이터 손상, 자격증명 노출과 provider 간섭 0건
- 지원 조합과 알려진 제한이 실제 동작 및 문서와 일치
- 서명·공증·update 검증 완료
- 공개 beta 배포에 대한 별도 사용자 승인

## 13. 검증 전략

### 13.1 자동 테스트

도메인과 공급자:

- Claude status JSON: 전체, 각 window 누락, null, 범위 밖, reset 경과, future clock, malformed
- Codex: exact `codex` bucket, legacy single bucket, unrelated bucket, primary/secondary 누락, reset credit null/empty/details
- handshake: initialize 실패, initialized 순서, request id 섞임, notification 섞임, EOF, oversized line와 timeout
- login: 성공, 사용자 취소, browser 실패, completion error와 timeout
- refresh: coalescing, forced cancellation, provider partial failure, dispose race
- persistence: atomic replace failure, permission error, corrupt backup, enum/number normalization
- bridge: 새 연결, 기존 command chaining, concurrent invocation, user edit conflict, safe restore와 helper update rollback
- scheduler: next local hour, DST/time change, sleep overdue 1회, same-version notification dedupe

레이아웃 probe는 실제 SwiftUI widget을 `NSHostingView`에 올려 다음 84개 core 조합을 측정한다.

```text
7 service states
  forced both / forced Claude / forced Codex
  auto none / auto Claude / auto Codex / auto both
x 3 densities
x 2 requested layouts
x progress on/off
= 84 combinations
```

추가 assertion:

- 0/1 provider의 SingleRow와 TwoRows actual view hierarchy 및 geometry 동등성 30쌍
- both-provider TwoRows의 Codex-above-Claude와 분리 간격 12상태
- auto Claude/Codex/both 상태와 대응 forced 상태 geometry 동등성 36상태
- light/dark, 한국어/영어 대표 snapshot
- text intrinsic size, accessibility frame와 panel bounds overflow 0건
- 표시 숫자와 progress normalized value 일치

### 13.2 build와 정적 검증

```bash
git diff --check
plutil -lint macos/DejavuMac/Info.plist
swift test --package-path macos/Packages/DejavuKit
xcodebuild -project macos/DejavuMac.xcodeproj \
  -scheme DejavuMac -configuration Release -destination 'platform=macOS' build
xcodebuild -project macos/DejavuMac.xcodeproj \
  -scheme DejavuMac -destination 'platform=macOS' test
codesign --verify --deep --strict --verbose=2 Dejavu.app
spctl --assess --type execute --verbose=4 Dejavu.app
xcrun stapler validate Dejavu.app
```

서명 전 build와 서명·공증 build를 별도 job으로 둔다. CI는 secret이 없는 pull request에서도 모든 compile/unit/layout 테스트를 실행할 수 있어야 한다. Windows job은 기존 Release build와 WPF layout probe 504개 조합을 계속 실행한다.

### 13.3 실기기 수동 행렬

| 축 | 필수 케이스 |
|---|---|
| 공급자 | Claude만, Codex만, 둘 다, 둘 다 없음, auto 전환 |
| Claude | bridge 없음, 첫 응답 전, 기존 status line, trust 거부, malformed, reset 경과, Fable off/허용/거부/schema 변경 |
| Codex | CLI, 검증된 Desktop bundle, logged out, missing executable, child crash |
| 데이터 | loading, ready, partial, login required, rate limited, offline, stale |
| 플로팅 오버레이 | off-start no-flash, 모든 density/layout/progress, click/drag, opacity와 appearance |
| 시스템 위젯 | Desktop/Notification Center, small/medium, light/dark, full-color/vibrant, missing/stale/app 종료 |
| 위치 | top-right, bottom-right, custom, display clamp, display 분리/재연결 |
| 화면 | Retina, 외부 화면, scale 변경, Spaces, full-screen, Stage Manager |
| 수명주기 | 첫 실행, 두 번째 실행, 보조 창 닫기, sleep/resume, Command+Q |
| 시작 | login item 승인/거부, 재부팅, system settings 변경 |
| 업데이트 | current, available, offline, cancel, apply/restart, same-version dedupe |
| 접근성 | VoiceOver, keyboard, Reduce Motion, Contrast, Transparency |
| 언어 | 한국어, 영어, 긴 오류와 날짜/time-zone 변화 |

## 14. 주요 리스크와 대응

| 리스크 | 대응 |
|---|---|
| Swift/C# 중복 파서가 달라짐 | 공유 schema와 동일 sanitized fixture를 양쪽 테스트에서 사용 |
| Claude rate limit은 status line과 사용자 활동에 의존 | 명시적 연결, 첫 응답 전 상태, reset-aware stale 처리와 제한 문서화 |
| Fable 원본은 공식 status line에 없고 endpoint가 문서화되지 않음 | 기본 off, 명시적 동의, 별도 parser/client, Keychain token 메모리 전용, status-line fallback과 변경 가능성 공개 |
| 기존 Claude status line 충돌 | exact backup, command chaining, compare-before-restore와 충돌 UI |
| status line이 workspace trust/managed setting으로 차단 | 사전 진단하고 provider 파일을 우회하지 않음 |
| GUI 앱 PATH가 shell과 다름 | 제한된 well-known 후보, override와 진단 표시 |
| Codex multi-bucket 오선택 | exact `rateLimitsByLimitId["codex"]` 우선 및 fixture 회귀 테스트 |
| Codex protocol 변화 | stable method만 사용, request/response 경계 격리, 명확한 unavailable 상태 |
| enterprise client 식별 요구 | `clientInfo`를 명확히 제공하고 enterprise 배포 전 OpenAI 등록 필요 여부 확인 |
| Swift pipe/cancellation race | actor ownership, bounded reader, graceful shutdown과 orphan process test |
| NSPanel이 Spaces/Stage Manager에서 사라지거나 방해 | Phase 0 prototype, native collection behavior와 실제 display QA |
| WidgetKit 갱신이 즉시/정확한 timer가 아님 | app refresh 후 reload 요청, budget 친화 timeline과 stale UI |
| App Group 서명이 누락되어 시스템 위젯이 데이터를 못 읽음 | 동일 Team/Group entitlement와 실제 설치·gallery 검증을 배포 gate로 둠 |
| accessory 앱 창이 focus/keyboard를 잃음 | activation policy spike와 창이 열릴 때만 regular fallback |
| App Sandbox가 provider 접근을 막음 | 첫 배포는 notarized non-sandbox, 최소 권한과 투명한 개인정보 설명 |
| `/Applications` update 권한 | Sparkle installer helper 실기기 검증, 실패 시 기존 버전 보존과 안내 |
| helper가 app update와 불일치 | stable Application Support path와 atomic versioned replacement |
| Apple 서명·공증 또는 Sparkle signature 실패 | publish 전 강제 verify, secret 분리와 clean-Mac 설치 테스트 |
| Windows 회귀를 Mac에서 발견하지 못함 | Windows CI build와 기존 WPF layout probe를 필수 gate로 유지 |

## 15. 착수 및 재승인 지점

### 지금 승인받을 항목

1. Swift 6 + SwiftUI/AppKit 완전 네이티브 구현
2. `macos/` 독립 트리와 기존 Windows 코드 무이동
3. macOS 14+, Apple Silicon, Modern 테마 첫 beta
4. Claude 공식 status line 기본 경로와 사용자 opt-in Fable 확장 경로의 분리
5. Codex 공식 app-server 연동
6. 선택형 플로팅 오버레이와 WidgetKit 시스템 위젯의 병행
7. 직접 DMG 배포와 Sparkle 2 업데이트
8. Phase 0과 Phase 1부터 시작

### Phase 0 뒤 재승인

- 실제 Claude/Codex 경로와 fixture 결과
- status line chaining/복구 방식
- Fable opt-in의 Keychain 승인·거부 및 endpoint 변화 결과
- signed App Group build의 시스템 위젯 gallery/공유 결과
- NSPanel의 Spaces/full-screen 동작
- Codex device-code fallback 포함 여부
- Claude Desktop fallback 포함 여부
- beta 일정과 알려진 제한

### 배포 전 별도 승인

- Apple Developer identity와 CI secret 사용
- 코드 서명, 공증과 appcast 게시
- GitHub tag, Release와 공개 beta 배포

## 16. 공개 베타 완료 정의

다음을 모두 충족해야 macOS 공개 베타라고 표시한다.

- 명시한 Claude/Codex 조합을 실제 Apple Silicon Mac에서 검증
- 메뉴 막대, 선택형 플로팅 오버레이, WidgetKit 시스템 위젯, 상세, 설정, 온보딩과 명시적 종료 정상 동작
- 84개 native layout 조합과 추가 동등성 검증에서 잘림·빈 provider 공간 0건
- reset credit이 상세 창에만 존재
- custom/right-edge 위치가 resize, auto-detection과 display 변경 후 보존
- 토큰, authorization header, prompt, 대화, transcript와 cwd가 저장·로그·fixture에 없음
- Claude bridge 연결/해제와 user-edit 충돌이 데이터 손상 없이 동작
- 앱 종료 후 Dejavu가 만든 child process 0개
- Developer ID, Hardened Runtime, 공증, staple, Gatekeeper 검증 성공
- clean Mac 설치, update, 재시작, data reset과 제거 안내 검증
- Windows Release build와 기존 504개 WPF layout probe 성공
- README, 개인정보, 보안, 아키텍처, 개발·출시 문서와 실제 동작 일치
- 알려진 제한과 provider의 비공개/변경 가능 경계를 release note에 공개

## 17. 공식 참고 자료

- [SwiftUI MenuBarExtra](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra)
- [AppKit NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)
- [AppKit NSPanel](https://developer.apple.com/documentation/appkit/nspanel)
- [WidgetKit](https://developer.apple.com/documentation/widgetkit)
- [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [NSWindow collection behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)
- [ServiceManagement SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple Developer ID](https://developer.apple.com/support/developer-id/)
- [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple hardened runtime](https://developer.apple.com/documentation/security/hardened-runtime)
- [Claude Code authentication](https://code.claude.com/docs/en/authentication)
- [Claude Code status line](https://code.claude.com/docs/en/statusline)
- [Claude Code errors and rate limits](https://code.claude.com/docs/en/errors)
- [Codex App Server](https://developers.openai.com/codex/app-server)
- [Sparkle 2 documentation](https://sparkle-project.org/documentation/)
- [Sparkle update publishing](https://sparkle-project.org/documentation/publishing/)
