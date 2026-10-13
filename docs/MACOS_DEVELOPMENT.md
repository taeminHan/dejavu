# Dejavu macOS development guide

> 2026-10-13 재개: 사용자가 macOS 누락 기능 구현, 우선순위별 버그 수정과 로컬 빌드·검사를 승인했습니다. 병렬 분담과 격리된 테스트 앱의 임시 ad-hoc 서명도 승인됐습니다. 실제 계정 로그인, 공급자 요청, 커밋·푸시·공개 배포는 이번 검사에 포함되지 않습니다. 아래의 배포 예시는 실행 승인이 아닙니다.

macOS 앱은 기존 Windows WPF 앱을 변경하지 않는 별도 SwiftUI/AppKit 제품이다. 구현 범위와 개인정보 경계는 `MACOS_SUPPORT_PLAN.md`, UI 불변조건은 `WIDGET_UI.md`, 취소·저장 원칙은 `STABILITY.md`를 따른다.

## 2026-10-13 implementation handoff

현재 검증 기기는 Apple Silicon, macOS 27.0.1, Xcode 27.0 (27A266a), Swift 6.4다. 배포 최소 버전은 macOS 14를 유지한다. 이 기기의 빌드 성공이 macOS 14 실기기 검증을 대신하지 않는다.

- 인증: Codex는 공식 app-server의 로그인 시작/완료 알림을 처리하고 브라우저를 연다. 재클릭은 진행 중인 URL만 다시 열며, 완료/취소 이후에는 재사용하지 않는다. Claude는 발견한 실제 CLI의 `auth login`을 개인 임시 `.command`로 실행하고 종료 코드를 관찰한다. Terminal만 여는 동작과 클립보드 복사를 제거했다.
- 수집: 사용자 지정 `CLAUDE_CONFIG_DIR`, 명시적 프로젝트/관리 설정 사전 점검, Dejavu 소유 bridge 자동 교체를 지원한다. 설정 충돌은 덮어쓰지 않는다. 연결 성공과 최초 사용량 수신을 구분하며 모델 요청을 자동 생성하지 않는다.
- 안정성: 독립 공급자 상태, 만료 값 제거, 10초/30초 제한 재시도, 절전 복귀·세션 활성·네트워크 회복 시 조기 갱신, HTTP Retry-After 게이트, 수동 갱신의 명시적 백오프 해제를 적용했다. Claude 로그인 관찰만으로 Codex를 반복 호출하거나 정기 갱신을 계속 미루지 않는다.
- 개인정보/저장: 초기화 시 실행 중 Fable 정책과 저장된 동의를 먼저 해제한다. 후속 정리가 실패해도 해제는 유지하며, 초기화 중 재동의·설정·연결 변경을 차단한다. 로그인 항목도 해제한다. 자동 진단은 허용된 상태/숫자/실제 플로팅 위치만 기록한다.
- 화면: 단색 메뉴 막대, 메뉴 항목에 붙는 일시적 상세 팝오버, 네이티브 사이드바 설정, 실제 상태를 반영하는 시작 안내와 원인별 복구 동작, 한국어 문구, 제품 앱 아이콘을 적용했다. 기존 플로팅/WidgetKit 코드와 설정은 삭제하지 않았으며 플로팅 사용자 지정은 고급 설정에 남겼다. 구현에는 [Apple의 메뉴 막대 추가 항목 API](https://developer.apple.com/documentation/swiftui/menubarextra)와 [팝오버 지침](https://developer.apple.com/design/human-interface-guidelines/popovers/)을 참고했다. 모든 접근성/다중 화면 동작이 검증됐다는 뜻은 아니다.
- 업데이트: Sparkle 확인 가능 상태 관찰을 수정하고, 후속 확인 실패 때문에 이미 발견한 새 버전이 사라지지 않게 했다. 실제 다운로드·설치는 Sparkle 소유다.

### Isolated local validation

실제 사용자 설정, Claude 설정, Keychain, 계정 또는 공급자 API를 사용하지 않는다. 테스트 경로는 임시 예시이며 기존 배포 앱을 덮어쓰지 않는다.

```bash
swift test --package-path macos/Packages/DejavuKit \
  --scratch-path /tmp/dejavu-macos-implementation-package \
  -Xswiftc -warnings-as-errors
bash tools/RunMacAppModelProbe.sh /tmp/dejavu-macos-implementation-package
bash tools/RunMacUpdateProbe.sh /tmp/dejavu-macos-implementation-package
xcodebuild -project macos/DejavuMac.xcodeproj -scheme DejavuMac \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /tmp/dejavu-macos-implementation-xcode \
  CODE_SIGNING_ALLOWED=NO MARKETING_VERSION=0.9.5 CURRENT_PROJECT_VERSION=42 build
```

임시 서명을 승인받은 로컬 테스트 복사본에 한해서 다음처럼 실제 SwiftUI/AppKit 배치와 합성 화면을 검사한다. 앱의 이 실행 경로는 공급자·실제 설정·Sparkle를 시작하지 않는다.

```bash
codesign --force --deep --sign - --timestamp=none \
  /tmp/dejavu-macos-implementation-xcode/Build/Products/Release/Dejavu.app
/tmp/dejavu-macos-implementation-xcode/Build/Products/Release/Dejavu.app/Contents/MacOS/Dejavu \
  --validate-ui --ui-validation-output=/tmp/dejavu-macos-implementation-ui
```

화면 검사는 상세 84, 설정 84, 시작 안내 18, 기존 플로팅 288 조합의 자연 크기를 실제 배치 크기와 비교한다. 설정은 한국어/영어, 700×500/780×580과 이전 인증 위치 선택 상태 12개를 포함한다. 플로팅은 0/1/2 공급자, 밀도, 행 배치, 진행률/Fable, 외관 조합을 검사한다. 선택된 실제 렌더링 PNG도 별도로 육안 확인해야 한다. 성공한 배치 검사는 VoiceOver·외부 디스플레이·실제 메뉴 막대 입력 검사를 대신하지 않는다.

2026-10-13 최종 로컬 결과:

- 핵심 패키지 181 tests, 0 failures: WidgetShared 7, Providers 85, Persistence 17, Domain 59, Application 13. 경고를 오류로 처리한 테스트와 Release 패키지 빌드 모두 통과.
- 실제 `AppModel` 41 checks, 0 failed: 초기화 실패와 재진입 중 동의 해제, 저장/재시작, 시작 안내, 진단 위치·허용 필드 포함. 공급자 준비 신호와 gate로 초기화 중 재동의를 결정적으로 검사한다.
- 실제 `UpdateCoordinator` + 합성 Sparkle transport 10 checks, 0 failed. 다운로드·설치를 실행하지 않았다.
- DejavuMac, DejavuClaudeBridge, DejavuUsageWidget Release 빌드 성공. 최종 앱은 Windows 공개 버전과 같은 0.9.5, 로컬 테스트 build 42이며 공개 배포 버전을 발행하지 않았다.
- Native UI matrix: `84 details, 72 settings, 18 onboarding, 288 floating, 0 invalid`. 선택 PNG 14개 육안 검토. 발견된 최소 설정 크기, Gauge 중복 레이블, Compact 진행 막대/Small 빈 상태 높이를 수정 후 재검사했다.
- 합성 Connections 창을 실제 화면에서도 확인했다. `cacheDisplay` PNG에서 선택된 사이드바가 검게 보이는 것은 시스템 material 합성 캡처의 한계이며 실제 창에서는 선택 제목/아이콘이 정상적으로 보인다. 해당 PNG를 실화면 결함 또는 검증 완료의 단독 근거로 사용하지 않는다.
- 임시 ad-hoc 서명과 `codesign --verify --deep --strict` 통과. 설치된 앱/기존 테스트 앱은 덮어쓰지 않았다.
- `git diff --check`, Info.plist/프로젝트 plist 및 문자열 카탈로그 검사 통과. Xcode의 CoreDevice/CoreSimulator 버전 불일치 진단은 남아 있으나 위 macOS 대상 빌드는 성공했다. 이 작업에서 Xcode 설치/시스템 보안 설정은 변경하지 않았다.

### Remaining acceptance boundaries

- 실제 Claude/Codex 로그인 완료와 연결 이후 실사용 값은 사용자가 로그인 동작을 승인·실행한 환경에서 확인한다. 합성 응답 검사는 계정 수락 검사와 다르다.
- Fable은 명시적 확장 접근에 한하며 비공개 응답 형식의 변경 가능성이 남는다. 사용자 지정 Claude 프로필은 해당 Keychain service를 안전하게 식별할 수 없어 기본 접근을 차단한다. 임의 추정·credential 복사는 하지 않는다.
- WidgetKit compile/embed는 유지하지만 무료 ad-hoc 앱의 App Group 공유와 시스템 위젯 실데이터는 보장하지 않는다.
- 설치형 Sparkle 업데이트, VoiceOver/키보드 전체 흐름, 다중/Retina 디스플레이와 macOS 14 실기기는 별도 수락 검사다. Developer ID·공증이 없다는 이유로 일반 앱 기능을 제외하지 않는다.

### Follow-up: Claude login succeeded but usage is absent

2026-10-13 사용자 보고 후 읽기 전용으로 확인했다. 실행 앱은 위 로컬 테스트 빌드였으며, 허용된 진단 필드상 Codex 주간 사용량은 수신 중이고 Claude만 `loginRequired`였다. Claude bridge snapshot은 오래된 빈 값이었다. 이 사실만으로 로그인이 실패했다고 판단하면 안 된다.

설치된 공식 Claude Code 2.1.291의 동작과 코드에서 로그인 identity 불일치를 확인했다. 이전 Dejavu 로그인 명령은 기본 `~/.claude` 경로에도 항상 `CLAUDE_CONFIG_DIR`를 명시했다. CLI는 경로가 기본값과 같아도 환경변수가 명시되면 별도 Keychain service 이름을 사용하지만, Dejavu reader는 기본 service만 조회했다. 실제 `auth status`의 `loggedIn`/`authMethod`만 비교해 일반 실행과 명시된 기본 경로 실행의 상태가 달라짐을 확인했다. 계정 식별자·token·credential 내용은 출력하지 않았고 로그인·설정·credential을 변경하지 않았다.

수정 원칙:

- 기본 프로필 로그인은 Terminal에서 상속될 수 있는 설정/보안 저장소 경로 변수를 제거해 CLI 기본 identity와 일치시킨다. 로그인과 조회의 account도 공식 CLI의 ASCII 계정명 규칙으로 정렬하고, 조회를 정확한 service/account 조합으로 제한한다. 명시적인 사용자 지정 프로필은 별도로 취급한다.
- 이전 Dejavu 명령으로 만들어진 동일 기본 경로의 service를 호환 조회하더라도 정확한 공식 경로 hash 한 개만 허용한다. Keychain 열거, 임의 프로필 추정, credential 복사/삭제는 금지한다.
- 기본 항목이 존재하거나 접근이 거부된 경우에는 다른 항목으로 자동 계정 전환하지 않는다. 기본 항목이 존재하면서 이전 경로에만 로그인한 사용자는 수정 앱에서 명시적으로 다시 로그인하거나, 별도 승인된 인증 위치 선택을 해야 한다. 호환 코드만으로 실제 사용자 복구 완료를 주장하지 않는다.
- Fable의 비공개 API 경계와 명시적 확장 접근 동의는 그대로 유지한다. 기본 status-line 수집은 여전히 사용자 CLI 세션의 실제 응답이 필요하며 검사 목적으로 모델 요청을 자동 생성하지 않는다.

수정 후 격리된 로컬 검사:

- 핵심 패키지 193 tests, 0 failures: WidgetShared 7, Providers 97, Persistence 17, Domain 59, Application 13. 경고를 오류로 처리했다. 로그인 명령/Keychain identity 집중 검사 15개는 합성 실행 파일과 주입한 조회 결과만 사용한다.
- 실제 AppModel 41 checks와 UpdateCoordinator 10 checks, 실패 0. 업데이트 검사는 제한 환경에서 시작이 차단돼 허용된 별도 실행으로 재검사했으며, 실제 다운로드·설치는 하지 않았다.
- DejavuMac Release 빌드 성공. 새 복사본 `outputs/local-tests/0.9.5-claude-login.GrAKaG/Dejavu.app`에 임시 ad-hoc 서명을 적용하고 deep/strict 검증을 통과했다. 기존 실행 앱과 설치본은 교체하지 않았다.
- 새 복사본의 합성 Native UI matrix는 `84 details, 72 settings, 18 onboarding, 288 floating, 0 invalid`. 이번 변경은 화면 디자인 변경이 아니며 합성 검사는 실제 인증·사용량 수신을 대신하지 않는다.
- 현재 사용자 환경은 기본 Keychain 항목도 존재하므로 기존 항목을 자동 우회하지 않는다. 수정 앱의 명시적 재로그인 뒤 실제 Claude 사용량을 수락 검사해야 한다. 아직 실제 계정 복구가 확인된 상태는 아니다.

### Follow-up: explicitly reuse the previous Dejavu sign-in

이후 사용자는 재로그인 대신 **기존 로그인 재사용 선택 기능**을 승인했다. 앞 절의 재로그인 안내는 첫 수정본에 대한 기록이며 새 선택 기능의 필수 절차가 아니다.

- 설정 → 연결 → 확장 Claude 접근의 **인증 위치**에서 **기본 Claude 로그인** / **이전 Dejavu 로그인**을 선택한다. 기본값은 기본 Claude 로그인이며, 이전 선택은 과거 Dejavu가 명시한 동일한 기본 설정 경로의 정확한 service/account 한 개만 사용한다.
- 선택은 `AppSettings.claudeCredentialIdentity`로 저장하며 누락되거나 잘못된 enum은 기본값으로 복구한다. 인증 내용, 임의 service 이름, 개인 경로는 설정·진단에 저장하지 않는다. credential 열거·복사·삭제나 자동 계정 전환을 하지 않는다. 첫 수정의 absent-only 자동 호환 조회도 제거해 각 선택이 해당 위치 하나만 조회하도록 한다.
- 인증 위치 선택 자체는 Fable/확장 접근 동의를 켜지 않는다. 동의가 꺼져 있으면 status-line 수집을 유지하며 Keychain을 읽지 않는다. 확장 접근이 켜진 경우에는 선택한 인증의 응답/오류만 표시하고, 계정을 식별할 수 없는 status-line snapshot으로 우회하지 않는다.
- 변경 직후 이전 Claude 숫자·오류·retry 상태를 비우고 진행 중 조회를 취소/배수한다. 오래된 성공·실패·429가 새 선택의 값이나 백오프를 복원하지 못하게 한다. Codex의 마지막 결과·확인 시각은 보존하고 별도 Codex 로그인 후속 요청이 없으면 Claude만 다시 확인한다.
- 공식 로그인 버튼도 선택된 인증 위치를 사용한다. 진행 중인 로그인에서는 위치를 바꿀 수 없으며, 사용자 지정 Claude 프로필의 Keychain 접근 차단은 유지한다. 개인정보 초기화는 동의를 해제하고 성공 시 기본 위치로 돌아가지만 실제 공급자 로그인은 삭제하지 않는다.
- 구현·합성 검사는 실제 Keychain credential이나 공급자 API를 사용하지 않는다. 새 앱에서 사용자가 이전 인증 위치를 직접 선택한 뒤 실사용량 수신을 확인해야 한다.

최종 로컬 결과:

- warnings-as-errors 핵심 패키지 211 tests, 0 failures: Providers 106, Domain 61, Application 20, Persistence 17, WidgetShared 7. 선택별 정확한 항목 조회, 설정 migration, 전환 직후 late 200/429/503/손상 응답/timeout 폐기, 취소된 설정 task와 동시 reset 배수 포함.
- 실제 AppModel 65 checks, 0 failed. 이전 값 즉시 제거, 새 위치 첫 실패에 이전 값 미복원, Codex 추가 조회 없음, 저장/재시작/초기화, 동의 비활성 유지, 이미 Codex가 ready인 상태의 전환 중 명시 후속 조회 보존을 합성 공급자로 검사했다. Keychain 읽기 횟수 0 검사는 model 설정 변경의 부작용 없음에 한하며 실제 공급자 동의 경계는 provider 검사가 담당한다.
- 실제 UpdateCoordinator 합성 검사 10 checks, 0 failed. 설치 업데이트는 실행하지 않았다.
- DejavuMac Release 빌드 및 새 복사본의 ad-hoc deep/strict 서명 검사 통과. 새 앱: `outputs/local-tests/0.9.5-claude-sign-in-choice.hPQdcn/Dejavu.app` (0.9.5, local build 42). 이전 앱은 덮어쓰거나 종료하지 않았다.
- 새 복사본 Native UI matrix: `84 details, 84 settings, 18 onboarding, 288 floating, 0 invalid` (474 states). 합성 PNG 15개를 생성했으며 신규 한국어 이전 로그인 선택 화면에서 인증 위치·재사용·동의 안내가 보이고 잘리지 않는지 육안 확인했다. 시스템 material 캡처의 선택된 sidebar 검은 영역 한계는 앞 절과 동일하며 새 실화면 결함으로 판단하지 않는다.
- `git diff --check` 및 문자열 카탈로그 JSON 검사 통과. 실제 계정의 복구 완료는 아직 주장하지 않는다. 기존 앱 종료 → 새 앱 실행 → 연결의 인증 위치에서 이전 Dejavu 로그인 선택 → 필요 시 사용자가 macOS Keychain 접근 승인 순서로 수락 검사한다. 확장 접근 동의는 사용자가 켠 상태여야 하며 재로그인은 필수 단계가 아니다.

## 0.9.6 release validation — 2026-10-13

사용자가 Windows 오류 4건·Codex 취소 검증과 함께 macOS 변경을 0.9.6으로 공개하는 작업을 승인했다. 로컬 0.9.6 build 43 복사본 `outputs/local-tests/0.9.6-release.veOpa1/Dejavu.app`은 Release 빌드, ad-hoc deep/strict 서명, 핵심 211 tests, 실제 AppModel 65 checks, UpdateCoordinator 10 checks, Native UI `84 details, 84 settings, 18 onboarding, 288 floating, 0 invalid`를 통과했다. 기존 설치본은 교체하지 않았다. 사용자는 직전 수정본의 이전 로그인 선택 후 실제 Claude 사용량 표시를 확인했다.

CI와 태그 workflow에도 실제 AppModel·UpdateCoordinator 검사를 연결하고, 배포 ZIP에서 추출한 정확한 앱의 합성 UI 검사까지 통과한 뒤 게시하도록 보강했다. Windows 실행·공급자 취소 경합과 WPF 회귀는 Windows runner의 별도 검사다. 배포 내부 빌드 번호는 최종 태그 커밋 수로 계산하므로 이전 공개 appcast의 42보다 큰지 확인한다. 실제 설치형 Sparkle 업데이트·macOS 14 기기·VoiceOver·다중 디스플레이·App Group 수락 검사는 아직 별도 범위다.

## Prerequisites

- Apple Silicon Mac
- macOS 14 이상
- Xcode 26.6 또는 저장소가 지정한 호환 버전
- Swift 6 strict concurrency 지원 toolchain

현재 개발 기기는 `xcode-select`가 Command Line Tools를 가리킬 수 있으므로 아래 예시처럼 Xcode를 명시한다.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

실제 Claude 설정이나 provider credential을 변경하지 않고도 core와 fixture 테스트가 전부 실행돼야 한다.

## Core package

```bash
swift package resolve --package-path macos/Packages/DejavuKit
swift test --package-path macos/Packages/DejavuKit -Xswiftc -warnings-as-errors
swift build -c release --package-path macos/Packages/DejavuKit -Xswiftc -warnings-as-errors
```

## Native app

```bash
xcodebuild \
  -project macos/DejavuMac.xcodeproj \
  -scheme DejavuMac \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/dejavu-mac-derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Claude bridge target도 같은 project에서 별도로 빌드한다.

```bash
xcodebuild \
  -project macos/DejavuMac.xcodeproj \
  -scheme DejavuClaudeBridge \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/dejavu-bridge-derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

WidgetKit extension도 독립 scheme과 앱 embed 결과를 확인한다.

```bash
xcodebuild \
  -project macos/DejavuMac.xcodeproj \
  -scheme DejavuUsageWidget \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/dejavu-widget-derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

`CODE_SIGNING_ALLOWED=NO`는 compile/embed 검증만 의미한다. 데스크탑·알림 센터 widget gallery와 App Group 공유는 동일 Team과 `group.dev.taemtaem.dejavu` entitlement로 서명한 설치 앱에서 별도로 확인한다.

## Structural validation

```bash
git diff --check
plutil -lint macos/DejavuMac/Config/Info.plist
find contracts -type f -name '*.json' -print0 | xargs -0 -n1 jq empty
swift test --package-path macos/Packages/DejavuKit -Xswiftc -warnings-as-errors
```

## Signed release and updates

Sparkle 2.9.4가 exact revision으로 고정되어 있다. 앱 설정을 읽은 뒤 자동 확인이 켜져 있으면 시작 4초 후와 다음 로컬 정각에 검사하고, 수동 확인은 Apple 표준 Sparkle 창을 사용한다. 저장소의 공개 EdDSA 키는 무료 ad-hoc build에서도 update archive를 검증하며, release feed에 게시된 `CFBundleVersion`이 현재 build보다 높을 때만 설치 대상으로 판단한다.

서명·공증·appcast 생성은 저장소에 credential을 기록하지 않는 `tools/BuildMacRelease.sh`로 수행한다.

```bash
BUILD_NUMBER=1 \
APPLE_TEAM_ID=ABCDE12345 \
APPLE_NOTARY_KEY_PATH=/secure/path/AuthKey_ABC123.p8 \
APPLE_NOTARY_KEY_ID=ABC123 \
APPLE_NOTARY_ISSUER_ID=00000000-0000-0000-0000-000000000000 \
SPARKLE_PUBLIC_KEY='base64-public-key' \
SPARKLE_ED_PRIVATE_KEY='private-key-from-secure-secret-store' \
./tools/BuildMacRelease.sh
```

스크립트는 Developer ID archive/export, app 공증과 staple, 업데이트 ZIP, DMG 공증과 staple, EdDSA appcast, SHA-256을 차례로 검증한다. 실제 Team provisioning과 App Group 등록이 필요하다. ad-hoc 또는 unsigned build로 update/install 경로가 검증됐다고 주장하지 않는다.

macOS의 공개 버전은 `ClaudeUsageTray.csproj`의 Windows `Version`을 단일 기준으로 사용한다. 두 macOS 빌드 스크립트는 이 값을 자동으로 읽으며, 다른 `VERSION`을 명시하면 실패한다. `v<version>` 태그를 push하면 기본 `Release dejavu` workflow가 같은 버전의 Windows와 무료 ad-hoc macOS 자산을 각각 검증하고, 하나의 GitHub Release에 모두 올린 뒤 공개한다. macOS `CFBundleVersion`은 모든 release workflow에서 동일하게 전체 Git 이력의 현재 커밋 순번을 사용하므로 workflow별 실행 번호가 달라도 업데이트 순서가 역전되지 않는다.

GitHub의 수동 `Build macOS release` workflow는 향후 Developer ID 배포용이며 기본적으로 검증된 artifact만 보관한다. `publish_to_release`를 명시적으로 켰을 때만 Windows 프로젝트 버전과 동일한 `v<version>` Release에 업로드한다. `macos-release` environment에는 `APPLE_TEAM_ID`, `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID`, `APPLE_NOTARY_PRIVATE_KEY_BASE64`, `SPARKLE_PUBLIC_KEY`, `SPARKLE_ED_PRIVATE_KEY`를 secret으로 등록한다.

## Free direct distribution

Apple Developer Program 가입 전에는 `tools/BuildMacFreeRelease.sh`를 사용한다. 이 경로는 ad-hoc 코드 서명된 DMG/ZIP과 Sparkle EdDSA 서명 appcast를 생성하지만 Apple Developer ID와 공증은 제공하지 않는다.

```bash
BUILD_NUMBER=1 ./tools/BuildMacFreeRelease.sh
```

로컬에서는 `dev.taemtaem.dejavu` 계정명의 Sparkle 개인 키를 로그인 Keychain에서 읽는다. GitHub Actions의 태그 릴리스와 `Build free macOS release`는 저장소 secret `SPARKLE_ED_PRIVATE_KEY` 하나만 필요하다. 이는 `macos-release` Environment가 아니라 Repository secret으로 넣어도 된다. 개인 키는 Sparkle `generate_keys --account dev.taemtaem.dejavu -x <임시파일>`로 내보낸 뒤 secret에 옮기고 즉시 삭제한다. 수동 무료 workflow도 버전을 입력받지 않고 Windows 프로젝트 버전을 읽으므로 서로 다른 버전의 자산을 만들 수 없다.

무료 build의 첫 실행에는 macOS가 알려지지 않은 개발자 경고를 표시한다. 사용자는 앱을 한 번 실행한 후 **시스템 설정 → 개인정보 보호 및 보안 → 보안 → 확인 없이 열기**를 선택해야 한다. 이 절차를 숨기거나 Apple이 검증한 앱이라고 표현하지 않는다. Apple Developer ID와 공증이 준비되면 `BuildMacRelease.sh` 경로로 전환한다.

App Group entitlement가 필요한 시스템 Widget 데이터 공유는 Developer ID provisioning 없이 보장하지 않는다. 무료 배포에서 보장하는 UI는 메뉴 막대와 플로팅 오버레이이며, Widget gallery 항목이 보여도 실데이터 공유를 릴리스 완료 조건으로 주장하지 않는다.

## Provider safety

- Claude bridge 테스트는 임시 directory와 명시적인 snapshot path만 사용한다.
- `~/.claude/settings.json`은 사용자가 UI에서 연결을 승인하기 전에는 읽거나 수정하지 않는다.
- Fable provider 테스트는 합성 credential/response만 사용한다. 실제 Keychain 읽기는 사용자가 설정에서 확장 접근을 켠 뒤에만 수행하고 token은 저장하거나 출력하지 않는다.
- Codex probe는 usage 숫자나 원문을 출력하지 않고 response shape만 확인한다.
- 종료 시 Dejavu가 시작한 child PID만 종료한다.
- fixture에 token, authorization header, account id, prompt, 대화, transcript와 cwd를 넣지 않는다.

Widget extension에서는 provider process, Keychain과 네트워크를 사용하지 않는다. 메인 앱이 App Group에 게시한 최소 snapshot만 읽는다.

## Local settings

macOS 설정은 `~/Library/Application Support/dejavu/settings.json`에 저장한다. 메뉴 막대의 Claude 지표 선택, Codex 단일 퍼센트 표시 여부와 플로팅 위젯 표시 여부도 같은 원자적 설정 파일을 사용한다. 위젯을 꺼도 `NSStatusItem`은 남으며, 저장된 꺼짐 상태로 다시 시작할 때 플로팅 패널을 먼저 표시하지 않는다.

## Historical issue: Claude is hidden after connecting

2026-10-13 소스 후속 조치: 최초 snapshot 부재를 `waitingForData`로 분류하고 연결된 수집기의 대기 항목을 표시하도록 수정했다. 사용자 지정 프로필 경로, 프로젝트/관리 설정 점검과 최초 응답 안내도 추가했다. 아래는 당시의 원문 분석이며, 현재 코드 설명이 아니다. 합성 회귀 검사는 추가했지만 당시 사용자 계정에서의 원인을 확정하거나 사건 재현에 성공한 것으로 기록하지 않는다.

기록일: 2026-10-07. 사용자 보고는 2026-10-06 Mac 실행에서 Claude Code를 연결했는데 Codex만 표시됐다는 내용이다. 설치한 Dejavu/Claude Code 버전, macOS 버전, 연결 이후 실제 응답 수신 여부는 아직 확인되지 않았다. Windows에서 기존 Mac 소스만 검토했으며, 원인 확정이나 native Mac 재현/수정/빌드 검증은 하지 않았다. Mac에서 후속 작업할 때 이 항목을 먼저 확인한다.

### Confirmed code behavior, not a confirmed incident cause

- `AppModel.connectClaudeStatusLine()`의 `.connected`는 상태 표시줄 설정과 bridge 설치가 성공했다는 뜻이다. 로그인 유효성이나 첫 사용량 snapshot 수신을 확인하지 않는다.
- 기본 `ClaudeCombinedUsageProvider`는 확장 접근이 꺼져 있으면 `ClaudeStatusSnapshotProvider`만 사용한다. Claude Code 로그인 자체를 설치/연결 감지 근거로 삼지 않는다.
- 공식 status-line `rate_limits`는 지원 계정에서 세션의 첫 API 응답 이후 제공된다. 로그인 또는 수집기 연결만으로 사용량이 생성된다고 안내하면 안 된다. 창별 값이 없을 수 있으며, 현재 bridge는 gateway의 `spend_limit`가 아닌 `five_hour`/`seven_day`만 읽는다. 참고: [Claude Code status-line fields](https://code.claude.com/docs/en/statusline).
- snapshot이 없으면 `UsageProviderAdapters.swift`는 이를 `.loginRequired`로 변환한다. 값이 없거나 만료된 snapshot은 unavailable이 될 수 있다. 따라서 데이터 수신 대기와 실제 로그인 실패가 UI에서 혼동될 수 있다.
- `ServiceVisibilityResolver`의 자동 감지는 snapshot 또는 `.ready`를 기준으로 한다. Codex만 준비된 상태에서는 Claude 항목이 숨겨진다. 서비스가 숨겨졌다는 사실만으로 Claude Code 미설치나 로그아웃을 확정할 수 없다.
- `AppModel.localPaths()`의 연결 대상은 `~/.claude/settings.json`으로 고정돼 있다. 다른 `CLAUDE_CONFIG_DIR` 또는 project/local/managed 설정이 실제 status line을 정하면 Dejavu가 설치한 수집기가 실행되지 않을 가능성이 있다. 이는 확인할 가설이지 이번 사용자 환경의 확정 원인이 아니다.
- 선택적 Fable 확장 접근은 별도 경로다. `MacOSClaudeKeychainCredentialReader`는 고정 service `Claude Code-credentials`를 읽는다. 접근 승인/거부, custom profile 및 파일 저장 fallback 호환성은 기본 status-line 수신과 분리해서 확인해야 한다. 문제 해결을 위해 이 옵션을 자동 활성화하거나 credential을 복사하지 않는다.

### Mac follow-up checklist

1. 설치 앱과 소스의 정확한 Dejavu 버전/커밋, Claude Code 버전, macOS 버전, 서비스 표시 설정과 메뉴 막대 지표 선택을 기록한다. 이번 보고를 특정 릴리스의 재현 성공으로 기재하지 않는다.
2. 연결 결과를 설정 설치 여부와 데이터 수신 여부로 나눠 확인한다. bridge가 설치됐는지, Claude Code가 실제 사용하는 설정과 수집기 설정이 일치하는지 확인하되 설정 전체나 기존 명령을 공개 로그에 출력하지 않는다.
3. 연결 뒤 새 Claude Code 세션에서 사용자가 평소 작업으로 받은 응답이 있는지 확인한다. 진단을 위해 모델 요청을 자동 생성하거나 사용량을 소비하지 않는다. 최초 응답 전/후, CLI 재시작 전/후, 다른 설정 폴더와 status-line 우선순위를 각각 구분한다.
4. Dejavu의 `claude-status.json` 존재/수정 시각, schema 유효 여부, 지원 사용량 창 존재 여부와 만료 판정만 확인한다. credential, account id, 대화 또는 원본 status-line payload를 수집하거나 출력하지 않는다.
5. 자동 감지와 강제 Claude 표시를 비교해 수집 실패와 표시 정책을 분리한다. Codex 정상 여부를 Claude 인증 정상의 근거로 사용하지 않는다.
6. 후속 수정 시 미연결, 설정 연결됨/수신 대기, 사용량 수신됨, 오래된 데이터, 권한 거부, 실제 로그인 필요를 구분한다. 연결 후 수신 대기 상태를 숨기지 않는 UX와 원인별 안내를 검토한다. 구현과 native 검증은 Mac에서 별도 승인 후 진행한다.

Historical status (2026-10-07): deferred. 당시 작업은 문제 기록만 추가했다. 2026-10-13 구현·로컬 검증 범위는 문서 위쪽의 최신 handoff를 따른다. 실제 계정 수락 검사는 남아 있다.
