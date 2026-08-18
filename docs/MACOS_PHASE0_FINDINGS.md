# macOS Phase 0 검증 기록

- 최초 검증일: 2026-08-12
- 구현 검증 갱신: 2026-08-13
- 상태: 진행 중
- 범위: `docs/MACOS_SUPPORT_PLAN.md`의 Phase 0

이 문서는 공개 가능한 구조 정보와 성공/실패 여부만 기록한다. 계정 식별자, 퍼센트, 초기화 시각, token, authorization header와 provider 응답 원문은 기록하지 않는다.

## 개발 환경

| 항목 | 확인 결과 |
|---|---|
| CPU | Apple Silicon arm64 |
| macOS | 26.5.2 |
| Swift | Apple Swift 6.3.3 |
| Xcode | 26.6 (17F113) |
| macOS SDK | 26.5 |
| Xcode license | 동의 확인 |
| active developer directory | Command Line Tools; 명령별 `DEVELOPER_DIR`로 Xcode 지정 |
| .NET SDK | 설치되지 않음; Windows 회귀는 Windows CI 필요 |

## Codex

발견한 실행 후보:

```text
/Applications/ChatGPT.app/Contents/Resources/codex
```

후보는 `codex-cli 0.147.0-alpha.6.6`으로 응답했다. 이 bundle 내부 경로와 버전은 공개 호환 계약이 아니므로 제품에서는 여러 제한 후보와 실행 smoke test를 함께 사용한다.

실데이터 값을 출력하거나 저장하지 않는 구조 probe 결과:

| 검사 | 결과 |
|---|---|
| `codex app-server` 시작 | 성공 |
| `initialize` 응답 | 성공 |
| `initialized` 후 `account/rateLimits/read` | 성공 |
| `rateLimitsByLimitId["codex"]` | 존재 |
| backward-compatible `rateLimits` | 존재 |
| `rateLimitResetCredits` envelope | 존재 |
| 요청 오류 | 없음 |
| probe 종료 후 자식 `app-server` | 0개 |

따라서 Swift parser는 exact `codex` bucket을 우선하고 legacy single bucket만 fallback으로 사용한다. 다른 bucket을 window 시간만으로 섞지 않는다.

## Claude

Claude Code CLI `2.1.228`이 nvm 관리 경로에서 발견됐고 `--version` smoke test에 성공했다. 사용자 Applications 아래의 `Claude.app`은 bundle identifier가 `com.google.Chrome.app...`인 Chrome 앱 래퍼이며 Claude Code status line 원본이 아니다. 공식 status-line 입력을 받는 bridge와 명시적 연결 관리자는 구현했고, 기존 command chaining·JSON 보존·충돌 감지·연결/해제를 실제 홈이 아닌 합성 임시 경로에서 검증했다. 실제 사용자 설정 연결과 workspace trust 동작은 아직 실행하지 않았다.

발견한 실행 후보:

```text
/Users/hantaemin/.nvm/versions/node/v20.11.1/bin/claude
```

이 경로는 nvm 버전에 종속되므로 제품에서는 고정 경로가 아니라 login shell의 `PATH`와 제한된 후보 탐지를 함께 사용해야 한다. 설치 확인 중 실제 Claude 설정, Keychain, 인증 상태와 대화 기록은 읽지 않았다.

현재 기본 경로는 다음 경계를 지킨다.

- 공식 status line schema를 축소한 비식별 fixture 테스트
- 임시 HOME과 임시 `settings.json`만 사용하는 bridge 및 연결 관리자 테스트
- 실제 `~/.claude/settings.json`, Keychain과 provider 데이터는 읽거나 수정하지 않음

공식 status-line에는 Fable 사용량이 없다. Fable은 설정에서 사용자가 별도로 켠 경우에만 Claude Code Keychain item을 읽기 전용으로 요청하는 확장 경로로 구현했다. 이 환경에서는 해당 토글을 켜거나 Keychain 내용을 읽지 않았다. Chrome 앱 UI, DOM, browser storage와 대화 기록은 지원 원본으로 사용하지 않는다.

Claude 실기기 검증이 완료되기 전에는 Claude 연동을 공개 베타 완료로 표시하지 않는다.

## 네이티브 창과 배포

| 검사 | 상태 |
|---|---|
| SwiftUI/AppKit compile | Debug/Release unsigned build 성공, Swift warnings-as-errors |
| `NSStatusItem` | native `NSMenu` 연결과 일반 클릭 pull-down 구현·컴파일 확인 |
| nonactivating `NSPanel` | 선택형 Floating Overlay 구현·컴파일 확인 |
| WidgetKit extension | small/medium 구현, 앱 bundle embed와 extension point 확인 |
| Spaces/full-screen/Stage Manager | 실제 UI smoke test 예정 |
| unsigned `.app` Release build | 성공 |
| Swift package tests | 116/116 성공 |
| Developer ID identity | 확인/사용하지 않음 |
| 서명·공증·Sparkle | Phase 4 및 별도 승인 대상 |

## Phase 0 잔여 게이트

- Claude Code에서 status line 실제 입력 fixture 확보(민감 값은 폐기하고 구조만 정제)
- 사용자가 승인한 실제 Claude 설정에서 연결·해제 왕복과 workspace trust 검증
- Fable opt-in의 실제 Keychain 승인/거부와 schema 변화 검증
- NSPanel이 포커스를 훔치지 않는지와 Spaces/full-screen 동작 확인
- accessory activation 상태에서 설정·상세 창의 키보드/VoiceOver 확인
- 동일 Team/App Group으로 서명한 설치 앱에서 Widget Gallery, Desktop과 Notification Center 확인
- Windows CI에서 Release build와 504개 layout probe 실행
- local update feed prototype은 Phase 4 전 별도 구현
