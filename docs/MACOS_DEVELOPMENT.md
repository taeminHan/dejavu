# Dejavu macOS development guide

> 2026-10-02 범위 갱신: Mac 구현·검증은 추후 Mac에서 별도로 진행합니다. 아래는 기존 개발/배포 참고 자료이며 이번 문서 작업에서 도구 버전이나 실행 결과를 새로 검증하지 않았습니다. 재개 시 [macos/AGENTS.md](../macos/AGENTS.md)와 [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)를 먼저 읽고 실제 OS/SDK에 맞춰 확인합니다. 서명·배포 예시는 실행 승인이 아닙니다.

macOS 앱은 기존 Windows WPF 앱을 변경하지 않는 별도 SwiftUI/AppKit 제품이다. 구현 범위와 개인정보 경계는 `MACOS_SUPPORT_PLAN.md`, UI 불변조건은 `WIDGET_UI.md`, 취소·저장 원칙은 `STABILITY.md`를 따른다.

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

## Deferred issue: Claude is hidden after connecting

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

Status: deferred. 이번 작업은 문제 기록만 추가한다. Mac provider, 인증/설정 또는 배포 파일은 변경하지 않는다.
