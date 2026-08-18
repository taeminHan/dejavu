# Dejavu macOS development guide

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
