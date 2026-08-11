# Dejavu macOS 지원 계획서

- 상태: 제안
- 작성 기준일: 2026-08-10
- 대상 저장소: `taeminHan/dejavu`
- 목표: 기존 Windows 품질을 유지하면서 macOS용 공개 베타를 출시하기 위한 범위와 실행 순서 확정

## 1. 요약 결론

macOS 지원은 가능하다. 다만 현재 WPF 앱을 그대로 변환하거나 Windows UI를 즉시 교체하는 방식은 적합하지 않다.

권장 방향은 다음과 같다.

1. 현재 Windows WPF 앱은 유지한다.
2. 상태 모델, 사용량 응답 파서, Codex `app-server` 프로토콜, 새로고침 정책과 설정 스키마를 공통 .NET 코어로 분리한다.
3. macOS 앱은 Avalonia UI로 새로 만들고, 메뉴 막대·플로팅 패널·로그인 항목처럼 macOS 고유 동작만 AppKit/ServiceManagement와 연동한다.
4. Claude는 Keychain 자격증명을 읽지 않고 공식 status line 입력을 사용하는 사용자 동의형 bridge로 연결한다.
5. 첫 베타는 macOS 14 이상, Apple Silicon, Modern 테마, 웹사이트 직접 배포로 제한한다.
6. Velopack의 macOS 채널을 사용해 GitHub Releases 기반 업데이트 구조를 Windows와 통일한다.
7. Intel Mac, Fable, 전체 테마 이식, Universal 2, Mac App Store는 첫 베타 이후 공식 데이터와 실제 수요를 바탕으로 결정한다.

단일 개발자 기준 공개 베타까지 예상 기간은 **6~9주**다. UI 구현보다 먼저 실제 Mac에서 Claude/Codex 데이터 감지가 가능한지를 검증해야 한다.

## 2. 목표와 제외 범위

### 2.1 목표

- 메뉴 막대에서 실행 상태와 주요 동작을 제공한다.
- Codex는 가능한 설치 경로를 자동 감지하고, Claude는 사용자의 명시적 동의 후 공식 status line bridge로 연결한다.
- 항상 표시 가능한 작은 플로팅 위젯과 상세 사용량 화면을 제공한다.
- Claude만, Codex만, 둘 다, 둘 다 사용할 수 없음 상태를 모두 정상 처리한다.
- Claude와 Codex의 5시간·주간 사용량 및 초기화 시각을 지원 가능한 공식 로컬 데이터 범위 안에서 표시한다.
- Codex 초기화권은 상세 화면에서만 표시한다.
- 설정, 위치, 서비스 선택, 새로고침 간격과 시작 시 실행 여부를 로컬에 저장한다.
- 서명·공증된 설치 파일과 앱 내 업데이트를 제공한다.
- 토큰, 프롬프트와 대화 내용을 Dejavu 설정이나 진단에 저장하지 않는다.

### 2.2 첫 베타 제외 범위

- 기존 WPF 앱을 Avalonia로 전면 교체
- Mac App Store 배포
- Intel Mac 정식 지원
- Universal 2 단일 패키지
- 기존 6개 테마의 완전한 동시 이식
- Claude Fable 사용량 표시
- Claude Keychain 자격증명 직접 접근
- Windows와 macOS의 픽셀 단위 동일 디자인
- 공개되지 않은 Claude/Codex 연동을 공식 API라고 표시하는 것

## 3. 현재 코드의 재사용 가능성

현재 프로젝트는 `net10.0-windows`, WPF, Windows Forms, Registry, Windows 모니터 API와 `win-x64` 배포에 묶여 있다. XAML 창과 Windows 수명주기는 macOS에서 재사용할 수 없지만 데이터 계층은 상당 부분 분리할 수 있다.

| 현재 영역 | 재사용 판단 | 필요한 작업 |
|---|---|---|
| `ApplicationState.cs` | 높음 | UI 독립 공통 코어로 이동 |
| `ClaudeUsageClient.cs` 응답 모델·파서·HTTP 처리 | 제한적 | Windows 기존 경로는 유지하되 Mac은 공식 status line parser 사용 |
| `ClaudeDesktopUsageReader.cs` 캐시·최신성·파싱 | 조건부 | Mac 실기기에서 파일과 스키마가 확인된 경우에만 공통 파서를 재사용 |
| `CodexUsageClient.cs` NDJSON·rate limit 파싱 | 높음 | 실행 파일 탐색과 프로세스 실행 경계를 분리 |
| `TraySettings.cs` 설정 스키마·서비스 정책 | 중간 | 저장 경로와 WPF 색상 검증 분리 |
| `WidgetLayoutCalculator.cs` 배치 규칙 | 중간 | Windows 전용 치수와 테마 의존성 제거 후 macOS 치수 검증 |
| `DesktopApplicationController.cs` 새로고침 정책 | 중간 | UI·트레이·Registry에서 `UsageRefreshCoordinator` 추출 |
| WPF XAML, code-behind, `UsageProgressBar` | 없음 | macOS UI로 새로 구현 |
| Registry 시작프로그램·NotifyIcon·monitor API | 없음 | macOS 전용 서비스로 구현 |
| Windows Velopack 릴리스 스크립트 | 없음 | macOS 별도 빌드·서명·공증 작업 추가 |

Windows 앱의 안정성을 보호하기 위해 공통 코어 추출은 작은 단위로 진행하고, 각 이동마다 기존 Windows Release 빌드와 상태 테스트를 통과해야 한다.

## 4. 권장 프로젝트 구조

같은 저장소 안에서 다음과 같은 멀티프로젝트 구조로 전환한다.

```text
Dejavu.sln
src/
  Dejavu.Core/
    상태 모델
    사용량 snapshot과 파서
    refresh coordinator
    설정 스키마와 서비스 표시 정책

  Dejavu.Providers/
    Windows Claude HTTP client
    Claude Desktop history reader
    Claude status line parser
    Codex app-server client
    플랫폼 경로·프로세스 인터페이스

  Dejavu.Windows/
    현재 WPF 앱
    Windows 경로·Registry·NotifyIcon·모니터 구현
    Windows Velopack 부트스트랩

  Dejavu.Mac/
    Avalonia UI
    AppKit 메뉴 막대·플로팅 패널 연동
    macOS 경로·프로세스·로그인 항목 구현
    macOS Velopack 부트스트랩

tests/
  Dejavu.Core.Tests/
  Dejavu.Providers.Tests/
  Dejavu.Windows.Tests/
  Dejavu.Mac.IntegrationTests/
```

별도 저장소로 분리하지 않는다. 저장소를 나누면 Claude/Codex 응답 파서, 상태 의미와 설정 정책이 플랫폼별로 달라질 가능성이 커진다.

### 4.1 필요한 플랫폼 경계

최소한 다음 인터페이스를 공통 계층에 정의한다.

```text
IClaudeEnvironmentLocator
ICodexExecutableLocator
IClaudeStatusBridge
IExternalAppLauncher
IAppPathProvider
IStartupService
ISystemThemeService
IUpdateService
IAppVersionProvider
IWidgetGeometryStore
IDisplayService
```

뷰는 공급자 클라이언트를 직접 호출하지 않는다. Windows와 동일하게 하나의 refresh coordinator가 독립적으로 두 공급자를 읽고 하나의 `ApplicationState`를 모든 화면에 전달한다.

## 5. 기술 선택

### 5.1 UI: Avalonia + 필요한 AppKit 연동

Avalonia는 macOS의 ARM64와 x64, 창, 메뉴, 시스템 트레이와 접근성을 지원하며 C# 데이터 계층을 그대로 사용할 수 있다. 첫 버전은 Avalonia로 화면을 구성하되 다음 기능은 macOS 네이티브 연동을 허용한다.

- 메뉴 막대 앱 동작
- Dock 아이콘 표시 정책
- 항상 위 플로팅 패널과 Spaces/전체화면 동작
- 로그인 시 실행
- 시스템 테마·모니터·활성화 정책
- 앱 번들 및 종료/재활성화 이벤트

SwiftUI/AppKit 완전 재작성은 macOS UX에는 가장 자연스럽지만 공급자 파서와 상태 관리까지 중복 구현해야 한다. 첫 베타에서는 선택하지 않고, macOS 사용자가 충분히 늘어 독립 제품 운영 가치가 확인되면 재평가한다.

.NET MAUI Mac Catalyst는 일반 창 중심 앱에는 적합하지만, Dejavu의 메뉴 막대 유틸리티·상시 플로팅 위젯·로컬 CLI 연동에는 추가 우회 구현이 많아 1차 선택에서 제외한다.

### 5.2 배포: 웹사이트 직접 배포 + Velopack

첫 버전은 Mac App Store가 아니라 GitHub Releases와 공식 웹사이트에서 배포한다. App Sandbox는 다른 앱의 로컬 파일과 CLI 실행을 제한할 수 있어 현재 데이터 감지 방식과 맞지 않는다.

Velopack을 우선 사용하되, 1단계 기술 검증에서 현재 고정 버전과 macOS 패키징·서명·공증의 호환성을 확인한다. 호환되지 않을 때만 macOS 전용 Sparkle 2를 대안으로 검토한다.

## 6. macOS 제품 UX 계약

### 6.1 메뉴 막대

- macOS의 메뉴 막대 아이콘을 Windows 알림 영역 아이콘에 대응시킨다.
- 클릭하면 최신 Claude/Codex 요약과 `상세 보기`, `새로고침`, `설정`, `종료`를 제공한다.
- 설정창과 상세창이 닫혀도 앱과 위젯은 종료되지 않는다.
- 명시적인 `종료`만 refresh 작업과 자식 `app-server`를 정리한 뒤 프로세스를 끝낸다.
- 메뉴 막대 전용 모드에서는 Dock 아이콘을 숨기되, 설정창·상세창의 정상적인 포커스와 키보드 접근을 보장한다.

### 6.2 플로팅 위젯

- Small, Compact, Comfortable 밀도와 한 줄·두 줄 배치를 유지한다.
- Claude만, Codex만, 둘 다, 자동 감지를 모두 지원하며 숨은 서비스 공간을 남기지 않는다.
- 초기화권은 상세 정보에만 표시하고 위젯에는 뱃지·여백·높이를 예약하지 않는다.
- 좌클릭과 드래그를 시스템 임계값으로 구분한다.
- 사용자 지정 위치는 크기·서비스·배치 변경 후에도 top-left를 유지하고 현재 디스플레이 안으로만 보정한다.
- 기본 오른쪽 배치는 위젯 크기가 변해도 오른쪽 여백을 유지한다.
- Retina 배율, 여러 디스플레이, Spaces, 전체화면 앱, 절전 복귀와 디스플레이 분리 상황을 별도 검증한다.
- 텍스트·아이콘·진행률은 배경 투명도와 함께 흐려지지 않아야 한다.

### 6.3 설정과 온보딩

- 첫 실행에서 Codex 자동 감지 결과, Claude 연결 필요 여부와 로컬 데이터 사용 방식을 설명한다.
- Claude 공식 status line 연결, Desktop fallback과 Windows의 Fable 지원 범위 차이를 분명히 표시한다.
- Codex 실행 파일이 없을 때 공식 설치 안내를 제공한다.
- `로그인 시 실행`은 macOS의 `SMAppService` 상태를 반영하고 승인이 필요하면 시스템 설정의 로그인 항목 화면으로 안내한다.
- macOS 기본 키보드 관례인 `Command+,` 설정 열기와 `Command+Q` 종료를 지원한다.

## 7. 공급자 연동 검증

공급자 데이터 검증은 UI 구현 전 실제 Apple Silicon Mac에서 수행한다. 추정 경로를 제품 코드에 바로 넣지 않는다. Mac v1의 안전한 기준 범위는 **검증된 Codex `app-server` 연동 + Claude 공식 status line 연동 + Fable 제외**다.

### 7.1 Claude

Anthropic 공식 문서에 따르면 macOS의 Claude Code 인증정보는 암호화된 macOS Keychain에 저장된다. 따라서 Windows의 `.credentials.json` 읽기와 비공개 usage endpoint 호출을 Mac에 이식하지 않는다.

Mac v1은 Claude Code의 공식 status line 입력을 사용한다. Claude Code가 명령에 전달하는 JSON 중 다음 값만 Dejavu bridge가 추출한다.

```text
rate_limits.five_hour.used_percentage
rate_limits.five_hour.resets_at
rate_limits.seven_day.used_percentage
rate_limits.seven_day.resets_at
capture timestamp
```

동작 경계:

- 사용자가 명시적으로 연결을 승인해야 한다.
- 기존 status line이 있다면 입력과 출력을 보존하는 wrapper로 연결하고 기존 설정을 덮어쓰지 않는다.
- 작업 디렉터리, 저장소 정보 등 status line 원본 JSON 전체를 저장하지 않는다.
- 필요한 사용량 필드만 Dejavu Application Support 경로에 원자적으로 기록한다.
- 연동 해제 시 Dejavu가 추가한 부분만 복구한다.
- 첫 Claude 응답 전에는 `확인 전` 상태를 표시하고 0%로 오인시키지 않는다.
- 로그인 상태 확인과 시작은 `claude auth status`, `claude auth login` 공식 명령을 우선 사용한다.

Claude Desktop 단독 fallback은 다음 파일이 Mac 실기기에서도 생성되고 Windows와 동일한 스키마인지 확인된 경우에만 제공한다.

```text
~/Library/Application Support/Claude/plan-usage-history.json
```

검증 전에는 Claude Desktop 단독 자동 감지를 제품 기능으로 약속하지 않는다.

공식 status line 입력에는 Fable 같은 모델별 주간 한도가 없다. Keychain 토큰을 읽거나 비공개 endpoint를 호출해 Fable을 복원하지 않으며, Mac v1에서는 `공식 Claude 연동에서 제공되지 않음`으로 안내한다. Windows의 기존 비공개 연동 위험도 별도 제품화 과제로 유지한다.

### 7.2 Codex

검증 항목:

- Homebrew(`/opt/homebrew`, `/usr/local`), npm, nvm, Volta, asdf/fnm 설치의 실제 실행 파일 탐색
- 공식 standalone 기본 경로 `~/.local/bin/codex` 탐색
- GUI 앱의 제한된 `PATH`에서도 네이티브 실행 파일을 찾을 수 있는지
- Codex Desktop `.app` 번들에 실행 가능한 `app-server` 후보가 있는지
- `codex app-server`의 initialize, `account/rateLimits/read`, `account/login/start` 프로토콜이 동일한지
- Dejavu가 시작한 자식 프로세스만 정상 종료하는지
- 브라우저 로그인 후 완료 이벤트와 강제 새로고침이 동작하는지

Mac 공통 파싱을 추출하기 전에 최신 응답의 `rateLimitsByLimitId.codex`를 최우선으로 선택하도록 현재 파서를 보강한다. 시간 길이만으로 여러 rate-limit bucket을 고르면 다른 제품 bucket이 추가될 때 잘못된 값을 표시할 수 있다.

Desktop 번들 내부 경로는 공급자 업데이트에서 바뀔 수 있으므로 단일 하드코딩 대신 후보 탐색과 명시적 환경 변수 override를 유지한다.

## 8. 로컬 저장과 개인정보

macOS 데이터는 `~/Library/Application Support/dejavu` 아래에 저장한다.

| 데이터 | 정책 |
|---|---|
| `settings.json` | 임시 파일 기록 후 원자적 교체 |
| `status.json` | 토큰 없는 상태·퍼센트·시간·위젯 위치만 기록 |
| `crash.log` | 크기 제한과 이전 로그 회전 유지 |
| provider credential | Mac에서는 읽거나 저장하지 않음 |
| Claude status bridge snapshot | 5시간·7일 퍼센트, reset과 캡처 시각만 저장 |
| Claude/Codex 대화 | 읽거나 저장하지 않음 |

설정에는 `Dejavu 데이터 초기화` 동작을 제공한다. 이 동작은 로그인 항목을 해제하고, Dejavu가 추가한 status line bridge를 복구한 뒤, Dejavu의 설정·캐시만 삭제한다. Claude, Codex, Keychain, 브라우저와 사용자의 셸 설정은 삭제하지 않는다.

macOS에서 앱을 휴지통으로 옮기는 것만으로는 `Application Support` 데이터가 자동 삭제되지 않을 수 있다. 따라서 웹사이트와 앱 내부에 `데이터 초기화 후 앱을 휴지통으로 이동`하는 제거 절차를 안내한다. Velopack 제거 helper가 실제 패키지에서 검증되기 전에는 단순 앱 삭제를 `완전 제거`라고 표현하지 않는다.

## 9. 서명·공증·업데이트

### 9.1 배포 전제

- Apple Developer Program 가입
- `Developer ID Application` 인증서
- `.pkg`를 사용할 경우 `Developer ID Installer` 인증서
- Hardened Runtime과 secure timestamp
- 앱 안의 모든 실행 파일, dylib, framework와 updater helper 서명
- `notarytool` 공증 후 ticket staple
- Gatekeeper, `codesign`과 설치·업데이트 검증

SignPath Windows 서명과 Apple Developer ID는 별도 체계다. SignPath 승인 여부와 관계없이 macOS 배포에는 Apple 인증서와 공증이 필요하다.

### 9.2 패키지와 아키텍처

첫 베타는 `osx-arm64` 패키지만 제공한다. 이후 Intel 수요가 확인되면 `osx-x64` 패키지와 별도 업데이트 채널을 추가한다.

```text
osx-arm64-beta
osx-x64-beta   # 후속 단계
```

Universal 2는 앱뿐 아니라 포함된 모든 네이티브 라이브러리와 업데이트 도우미까지 두 아키텍처를 포함해야 하므로 초기 범위에서 제외한다.

설치 위치는 `/Applications`의 표준 UX와 `~/Applications`의 무권한 업데이트 장점을 실제 Velopack 설치·업데이트 테스트 후 결정한다.

### 9.3 GitHub Actions 파이프라인

기존 Windows 태그 릴리스는 유지하고 macOS job을 추가한다.

```text
tag push
  -> Windows build/test/sign/package
  -> macOS runner build/test
  -> Dejavu.app 생성
  -> 내부 바이너리와 app 서명
  -> Velopack pkg/ZIP 생성
  -> Developer ID Installer 서명
  -> notarytool 제출 및 승인 대기
  -> staple
  -> codesign 및 Gatekeeper 검증
  -> SHA-256 체크섬 생성
  -> GitHub Release 및 아키텍처별 update feed 업로드
```

공증과 서명이 성공하기 전에는 Release 업로드를 중단한다. 인증서는 임시 Keychain에만 가져오고 job 종료 시 삭제한다.

필요한 GitHub Secrets:

- Application 인증서 P12와 비밀번호
- Installer 인증서 P12와 비밀번호
- Apple Team ID
- App Store Connect API key 또는 공증 자격정보
- 임시 Keychain 비밀번호

## 10. 단계별 실행 계획

### Phase 0 — 실기기 기술 검증 (3~5일)

작업:

- Apple Silicon Mac 개발·테스트 환경 준비
- Claude Code, Claude Desktop, Codex CLI, Codex Desktop 각각 설치·로그인
- Claude status line 입력과 기존 사용자 status line 공존 검증
- 각 데이터 원본의 실제 경로, 권한, 스키마와 실행 방법 기록
- Avalonia 메뉴 막대와 투명 Topmost 창 prototype
- macOS Velopack unsigned 패키지·업데이트 prototype

완료 조건:

- Claude status bridge와 Codex app-server 각각에서 실제 사용량 fixture를 확보한다.
- 플로팅 창이 Retina와 Spaces 환경에서 표시된다.
- unsigned `.app` 또는 테스트 패키지가 깨끗한 Mac에서 실행된다.
- 확인되지 않은 Desktop 경로와 지원 불가능한 기능을 명시한다.

중단 조건:

- 두 공급자 모두 안정적인 로컬 데이터 원본을 확인하지 못함
- 필요한 파일/프로세스 접근이 과도한 시스템 권한 없이는 불가능함
- 공통 코어를 재사용할 수 없어 플랫폼별 파서 중복이 불가피함

### Phase 1 — 공통 코어 추출 (1~2주)

작업:

- solution과 `Dejavu.Core`, `Dejavu.Providers`, `Dejavu.Windows` 프로젝트 생성
- 상태, 파서, 설정 스키마와 refresh coordinator 이동
- 플랫폼 locator/launcher/storage/update 인터페이스 추가
- 실제 응답에서 민감정보를 제거한 fixture 기반 테스트 추가
- 기존 WPF 구성과 릴리스 결과 유지

완료 조건:

- Windows 기능과 사용자 설정 경로가 바뀌지 않는다.
- Windows Release 빌드와 provider 상태 테스트가 통과한다.
- 공통 프로젝트가 `net10.0` 플랫폼 중립 타깃으로 빌드된다.

### Phase 2 — macOS 공급자 구현 (1주)

작업:

- macOS 경로·실행 파일 locator 구현
- Claude status line bridge, CLI 로그인 상태와 연결 해제 구현
- 검증된 경우에만 Claude Desktop fallback 추가
- Codex CLI/Desktop 후보 탐색과 `app-server` 수명주기 구현
- 브라우저/외부 앱 실행, 설정·진단 경로 구현

완료 조건:

- Claude만, Codex만, 둘 다, 둘 다 없음 상태를 실기기에서 재현한다.
- 로그인·offline·rate limit·expired 상태에서 앱이 종료되지 않는다.
- 토큰과 대화가 로그·설정·fixture에 기록되지 않는다.

### Phase 3 — macOS MVP UI (2~3주)

작업:

- 메뉴 막대, 위젯, 상세 화면, 설정, 온보딩 구현
- Modern 테마와 Small/Compact/Comfortable, 한 줄/두 줄 구현
- 위치 보존, 디스플레이 변경, 클릭/드래그 구분 구현
- 로그인 시 실행과 시스템 설정 안내 구현
- 한국어·영어 리소스 분리

완료 조건:

- 필수 상태 행렬과 위젯 불변조건을 통과한다.
- 메뉴 막대에서 모든 주요 동작에 접근할 수 있다.
- VoiceOver label, 키보드 포커스와 명암 검사를 통과한다.

### Phase 4 — 제품화와 배포 (1~2주)

작업:

- Developer ID 서명, Hardened Runtime, 공증, staple 자동화
- Velopack beta 채널과 업데이트 UI 구현
- 설치·업데이트·앱 내 데이터 초기화·앱 제거·실패 복구 검증
- 웹사이트 Mac 다운로드와 설치 설명 추가
- README, 개인정보, 보안, 아키텍처, 출시 점검표 갱신

완료 조건:

- 깨끗한 Mac에서 경고 우회 없이 설치·실행된다.
- 이전 베타에서 다음 베타로 업데이트하고 설정·위치가 유지된다.
- 앱 내 데이터 초기화 후 Dejavu 데이터와 bridge만 정리되고 공급자 데이터는 유지된다.

### Phase 5 — 공개 베타 QA (1주)

작업:

- 실제 사용자 소규모 베타
- 절전/복귀, 네트워크 전환, 다중 모니터, Spaces와 전체화면 장기 테스트
- provider 경로 변경과 업데이트 실패 대응 점검
- Windows 회귀 테스트

완료 조건:

- P0 크래시·데이터 손상·인증정보 노출 문제가 없다.
- 알려진 제약과 지원 범위가 릴리스 노트에 공개된다.
- 지원 가능한 macOS/공급자 조합이 문서와 실제 동작에서 일치한다.

## 11. 검증 행렬

| 축 | 필수 케이스 |
|---|---|
| 서비스 | Claude만, Codex만, 둘 다, 둘 다 없음, AutoDetect 전환 |
| Claude 원본 | status bridge, 기존 status line 공존, 첫 응답 전, Desktop fallback 검증, malformed, offline |
| Codex 원본 | CLI, Desktop bundled runtime, logged out, missing executable, child crash |
| 위젯 | Small/Compact/Comfortable, 한 줄/두 줄, progress on/off |
| 데이터 | loading, ready, partial, login required, rate limited, offline |
| 화면 | Retina, 비 Retina 외부 화면, 주/보조 화면, 연결/해제, 배율 변경 |
| macOS | 재부팅, 로그인 시 실행, 절전/복귀, Spaces, 전체화면, Command+Q |
| 배포 | 신규 설치, 현재 버전, 업데이트 있음, 다운로드 실패, apply/restart, 데이터 초기화, 앱 제거 |
| 언어 | 한국어, 영어, 긴 상태 문구, VoiceOver |
| 회귀 | 기존 Windows 설치·위젯·업데이트·제거 |

## 12. 주요 리스크와 대응

| 리스크 | 영향 | 대응 |
|---|---|---|
| Claude 사용량 endpoint가 공개 계약이 아님 | 갑작스러운 파손·정책 위험 | provider 격리, fallback, 호환성 문서, 오류 시 마지막 정상 값 |
| macOS Claude credential이 Keychain에 있음 | Windows 토큰 파일 방식 재사용 불가 | credential 비접근, 공식 status line bridge 사용 |
| macOS Desktop 데이터 경로/스키마가 다름 | Desktop-only 자동 감지 미지원 | Phase 0에서 실측하고 확인 전에는 기능을 약속하지 않음 |
| Claude status line이 한 명령만 지원 | 기존 사용자 설정과 충돌 | wrapper로 JSON과 기존 출력 보존, 명시적 동의·복구 제공 |
| 공식 Claude status line에 Fable이 없음 | Windows와 기능 차이 | Mac v1 미제공을 명시하고 공식 필드 추가 시 재검토 |
| GUI 앱의 PATH가 셸과 다름 | CLI 자동 감지 실패 | Homebrew/npm/version manager 후보 + override + 진단 UI |
| Codex Desktop 번들 경로 변경 | Desktop 사용자 감지 실패 | 후보 탐색, 프로토콜 smoke test, CLI fallback |
| WPF 분리 과정의 Windows 회귀 | 기존 사용자 품질 저하 | 작은 이동, fixture 테스트, Windows 릴리스 병행 검증 |
| macOS 플로팅 창과 Spaces 동작 차이 | 위젯 유실·집중 방해 | AppKit bridge, 위치 복구, 실제 다중 화면 QA |
| Apple 서명·공증 실패 | 배포 차단 | unsigned prototype과 서명 pipeline 분리, 업로드 전 강제 검증 |
| `/Applications` 업데이트 권한 | 업데이트마다 승인 가능 | 설치 위치 spike, 실패 시 명확한 안내와 기존 버전 유지 |
| Mac App Sandbox 제한 | 로컬 공급자 감지 불가 | 첫 배포는 notarized non-sandbox 직접 배포 |
| Intel 지원 비용 | 패키지·QA·업데이트 채널 증가 | arm64 베타 후 실제 수요 기반 결정 |

## 13. 권장 Epic과 이슈 분할

### Epic A — macOS feasibility

- MAC-001 Apple Silicon 테스트 환경과 fixture 수집 절차
- MAC-002 Claude status line bridge와 Desktop fallback 검증
- MAC-003 Codex CLI/Desktop `app-server` 검증
- MAC-004 Avalonia menu bar/floating panel prototype
- MAC-005 Velopack macOS package/update prototype

### Epic B — shared core

- MAC-010 solution/프로젝트 구조 분리
- MAC-011 state·parser·settings core 이동
- MAC-012 refresh coordinator 추출
- MAC-013 platform interface와 Windows 구현
- MAC-014 provider fixture 및 Windows 회귀 테스트

### Epic C — macOS product

- MAC-020 macOS provider locator, Claude bridge와 process service
- MAC-021 menu bar와 app lifecycle
- MAC-022 floating widget와 위치 복구
- MAC-023 details/settings/onboarding
- MAC-024 login at startup와 시스템 안내
- MAC-025 한국어·영어와 접근성

### Epic D — release

- MAC-030 Apple certificate와 임시 Keychain workflow
- MAC-031 sign/notarize/staple/verify pipeline
- MAC-032 Velopack channel과 in-app update
- MAC-033 설치·업데이트·데이터 초기화·앱 제거 QA
- MAC-034 웹사이트·README·개인정보·출시 문서

## 14. 착수 전 필요한 결정과 준비물

| 항목 | 권장안 | 결정 시점 |
|---|---|---|
| UI 기술 | Avalonia + 필요한 AppKit bridge | Phase 0 종료 |
| 최소 OS | macOS 14 이상 | Phase 0 종료 |
| 1차 CPU | Apple Silicon arm64 | 지금 |
| Intel | 베타 수요 확인 후 | 공개 베타 이후 |
| 배포 | 웹사이트/GitHub 직접 배포 | 지금 |
| 업데이트 | Velopack 우선 | Phase 0 종료 |
| App Store | 제외 | 공개 베타 이후 재검토 |
| 첫 테마 | Modern | 지금 |
| 저장소 | 기존 `dejavu` 저장소 | 지금 |

필수 준비물:

- 실제 Apple Silicon Mac 한 대
- Claude Desktop/Code와 Codex Desktop/CLI 테스트 계정 및 설치 조합
- 기존 Claude status line을 사용하는 테스트 프로필
- Apple Developer Program 계정
- Developer ID 인증서 발급 권한
- GitHub Actions macOS runner 사용 가능 여부
- 민감정보를 제거한 provider 응답 fixture 작성 절차

## 15. 공개 베타 완료 정의

다음 조건을 모두 충족해야 macOS 공개 베타로 표시한다.

- 지원한다고 명시한 Claude/Codex 조합이 실제 Mac에서 검증됨
- 메뉴 막대, 플로팅 위젯, 상세, 설정, 온보딩이 정상 동작함
- 모든 필수 서비스·밀도·배치·상태 조합에서 빈 공간과 잘림이 없음
- 토큰·대화·프롬프트가 저장, 로그, fixture에 포함되지 않음
- Developer ID 서명, Hardened Runtime, 공증과 staple 검증 성공
- 깨끗한 Mac에서 설치, 업데이트, 재시작, 데이터 초기화와 앱 제거 성공
- 앱 종료 시 Dejavu가 만든 자식 프로세스와 작업만 종료함
- Windows Release 빌드와 핵심 회귀 테스트가 통과함
- README, 웹사이트, 개인정보, 보안, 제한사항과 릴리스 노트가 일치함

## 16. 공식 참고 자료

- [Avalonia supported platforms](https://docs.avaloniaui.net/docs/supported-platforms)
- [Avalonia macOS platform guide](https://docs.avaloniaui.net/docs/platform-specific-guides/macos)
- [Avalonia TrayIcon](https://docs.avaloniaui.net/controls/navigation/trayicon)
- [Claude Code authentication](https://code.claude.com/docs/en/authentication)
- [Claude Code status line](https://code.claude.com/docs/en/statusline)
- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-usage)
- [Codex App Server](https://developers.openai.com/codex/app-server)
- [Codex install script](https://github.com/openai/codex/blob/main/scripts/install/install.sh)
- [Apple MenuBarExtra](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra)
- [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple Developer ID](https://developer.apple.com/help/glossary/developer-id-certificate/)
- [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple hardened runtime](https://developer.apple.com/documentation/security/hardened-runtime)
- [Apple universal macOS binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary)
- [Velopack macOS packaging](https://docs.velopack.io/packaging/operating-systems/macos)
- [Velopack signing and notarization](https://docs.velopack.io/packaging/signing)
- [Velopack channels](https://docs.velopack.io/packaging/channels)
