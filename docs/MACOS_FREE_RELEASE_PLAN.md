# Dejavu macOS 무료 배포 실행 계획

- 작성일: 2026-08-18
- 기준 버전: `0.9.1`
- 대상: macOS 14 이상, Apple Silicon
- 배포 방식: ad-hoc 서명 DMG + Sparkle EdDSA 업데이트
- 제품 상태: 무료 직접 배포 정식 경로

## 1. 목표

Apple Developer Program 가입 여부를 기능 개발이나 공개 배포의 선행 조건으로 사용하지 않는다. 메뉴 막대, 플로팅 오버레이, 실제 Claude/Codex 사용량, 설정, 진단, 로그인 시 실행과 Sparkle 업데이트를 무료 배포 경로에서 완성한다.

Windows와 동일하게 유지할 것은 데이터 의미, 설정 보존, 색상 임계값, 새로고침·취소·오류 처리와 개인정보 경계다. 화면은 Windows를 복제하지 않고 Apple 표준 AppKit/SwiftUI 동작을 따른다.

## 2. Apple Developer Program 전용 범위

아래 항목은 무료 배포 완료 조건에서 제외한다.

1. Developer ID Application 신뢰 서명
2. Apple 공증과 staple
3. 배포용 App Group entitlement를 통한 시스템 위젯 실데이터 공유 보장
4. Mac App Store 배포

WidgetKit extension과 App Group 코드는 유지하되, 무료 배포에서는 메뉴 막대와 플로팅 오버레이를 보장 기능으로 정의한다. 시스템 위젯은 정적 UI와 빌드 검증까지만 수행한다.

## 3. 무료 배포 완료 범위

### 3.1 플로팅 오버레이와 메뉴 막대

- Claude 5시간·주간·Fable과 Codex 단일 사용량을 각각 선택
- 설정 변경을 다음 main-actor turn까지 기다리지 않고 즉시 반영
- Small, Compact, Comfortable 밀도
- 한 줄, 두 줄 배치
- 자동 감지, Claude와 Codex, Claude만, Codex만 서비스 정책
- 진행률 표시와 임계값 색상 켜기/끄기
- 70% 이상 warning, 90% 이상 danger를 값과 진행률에 동일 적용
- 투명도 조절
- 우상단, 우하단, 사용자 지정 위치
- 드래그 위치의 디스플레이 식별자·좌상단 좌표 저장과 복원
- 위치 초기화와 전체 설정 기본값 복원
- 플로팅 오버레이를 꺼도 메뉴 막대·새로고침·업데이트 유지

### 3.2 공급자와 로그인

- Claude Status Line 명시적 연결·해제와 기존 명령 보존
- Claude Code 설치·로그인 안내
- Fable 확장 접근의 별도 동의와 Keychain 거부·만료 처리
- Codex CLI/Desktop 자동 탐지
- 사용자 행동으로만 공식 Codex CLI 로그인 명령 준비
- 로그인 취소·시간 초과·앱 종료 시 Dejavu가 만든 child만 종료
- 누락, 로그인 필요, 오프라인, rate limited와 오류를 공급자별로 독립 표시

Claude Desktop history fallback은 macOS 파일·스키마·최신성 의미가 실제로 확인될 때만 추가한다. UI, DOM, 접근성 트리, Chrome 저장소와 대화 데이터 scraping은 구현하지 않는다.

### 3.3 앱 수명주기와 설정

- `SMAppService` 로그인 항목 등록·해제·상태 복구
- Settings의 모든 표시값을 실제 편집 가능한 표준 컨트롤로 제공
- 변경 즉시 원자 저장, 종료 시 최종 저장 대기
- 손상 설정을 보존하고 정상화된 기본값으로 시작
- 한국어·영어, 키보드, VoiceOver, Reduce Motion/Transparency/Contrast
- 메뉴 막대 일반 클릭, `Command+,`, 재열기와 명시적 종료
- 두 번째 실행은 기존 인스턴스의 설정을 열고 즉시 종료

### 3.4 진단과 데이터 초기화

- 자격증명 없는 `status.json`
- 256 KiB 제한과 이전 파일 회전을 적용한 `diagnostics.log`
- 설정에서 진단 폴더 열기
- Dejavu 데이터 초기화 전에 refresh·child process 중단
- 현재 managed Claude bridge일 때만 원래 Status Line 복구
- Dejavu 설정·snapshot·로그·helper만 삭제
- Claude, Codex, Keychain, 브라우저와 대화 데이터는 삭제하지 않음

### 3.5 업데이트와 배포

- Windows 프로젝트 버전을 공통 공개 버전으로 사용
- Sparkle EdDSA 서명 ZIP과 HTTPS appcast
- 시작 4초 후, 다음 로컬 정각, 절전 복귀와 시간 변경 확인
- 자동 확인 ON/OFF와 수동 확인
- 다운로드·검증·설치·재실행·설정 보존
- 실패·취소 후 기존 앱 정상 실행
- ad-hoc 서명 DMG, ZIP, appcast와 SHA-256 생성
- GitHub Release 직접 다운로드 자산과 웹사이트 링크 검증
- 공개 자산과 소스 커밋·태그를 일치시켜 재현성 확보

## 4. 작업 순서

### Phase A — 릴리스 기준 고정

- 이 계획서를 기능 완료 기준으로 사용
- 현재 작업 트리의 macOS 소스를 검증 가능한 변경 단위로 정리
- 릴리스 자산이 만들어진 소스 커밋과 태그를 일치

완료 조건:

- `git diff --check`
- Swift 6 warnings-as-errors
- 패키지 전체 테스트 통과
- DMG 내부 버전·빌드·Sparkle 공개 키 확인

### Phase B — 오버레이 설정과 위치

- `AppModel`에 실제 편집 가능한 오버레이 설정 publisher 추가
- `WidgetPanelController`에서 저장된 밀도·배치·서비스·위치를 사용
- 드래그 종료 시 좌상단 좌표와 디스플레이 식별자 저장
- 패널 크기 변경 시 custom 좌상단 보존, edge 배치는 같은 모서리에 재고정
- Settings에 표준 Picker, Toggle, Slider 추가

완료 조건:

- Claude만, Codex만, 둘 다, 둘 다 없음
- 세 밀도 × 두 배치 × 진행률 ON/OFF
- custom/top-right/bottom-right 위치 복원
- Fable 추가·제거 시 빈 슬롯과 위치 이동 오류 없음

### Phase C — 수명주기와 공급자 행동

- `SMAppService` 로그인 항목
- Claude/Codex 설치·로그인 행동
- 로그인 작업 취소와 child process 정리
- 설정 초기화와 데이터 초기화

완료 조건:

- 재부팅 후 로그인 항목 상태 일치
- 로그인 성공·취소·실패에서 orphan child 0개
- Claude 사용자 설정 충돌 시 자동 덮어쓰기 없음

### Phase D — 진단과 업데이트

- `DiagnosticsStore`를 실제 `ApplicationState` 갱신에 연결
- 제한 로그와 진단 폴더 UI
- build 23보다 높은 로컬 테스트 build로 Sparkle 업데이트
- 업데이트 전후 설정·위젯 위치 비교

완료 조건:

- 진단 파일에 token, header, prompt, transcript, cwd 없음
- 업데이트 성공·실패·취소 후 앱과 설정 정상

### Phase E — 무료 릴리스 QA

- 깨끗한 Apple Silicon Mac 설치
- 최초 실행 Gatekeeper 안내
- 메뉴 막대-only와 오버레이 ON/OFF
- 다중 모니터, Spaces, 전체화면, Stage Manager
- 절전·복귀, 네트워크 전환, 시스템 시간 변경
- 한국어·영어와 VoiceOver
- Windows Release CI와 504개 WPF layout probe 회귀

완료 조건:

- P0 crash, 설정 손상, credential 노출과 provider 간섭 0건
- 공개 문서와 실제 무료 빌드 기능 일치
- DMG 직접 다운로드와 Sparkle feed 검증

## 5. 현재 우선순위

1. 플로팅 오버레이 설정과 위치 복원
2. 로그인 시 실행
3. Claude/Codex 로그인 행동
4. 진단과 데이터 초기화
5. Sparkle 실제 업데이트 검증
6. 소스·태그·릴리스 자산 재현성 정리

## 6. 릴리스 표기

무료 배포본은 정식 Dejavu macOS 릴리스로 제공한다. 다만 다운로드 페이지에는 다음 사실만 명확하게 안내한다.

- Apple 공증 전 ad-hoc 서명본
- 최초 실행 시 개인정보 보호 및 보안에서 `확인 없이 열기` 필요
- 시스템 위젯의 실데이터 공유는 Apple Developer 서명 전 보장하지 않음

그 외 구현 가능한 기능을 Apple Developer Program 가입 이후로 미루지 않는다.

## 7. 2026-08-18 구현 상태

완료:

- Phase A의 warnings-as-errors Release 빌드, Sparkle EdDSA, SHA-256, bundle version·helper·extension 검증
- Phase B의 오버레이 밀도, 배치, 서비스, 진행률, 임계값 색상, 투명도, 위치 저장·복원 및 즉시 반영
- 배경·강조·텍스트 색상 ColorPicker, 원자 저장, 기본 색상 초기화와 오버레이 즉시 반영
- Phase C의 `SMAppService`, 설정 초기화, Claude 연결·안전 원복, Claude/Codex 로그인 안내, 단일 인스턴스 활성화
- Phase D의 allow-list `status.json`, 256 KiB `diagnostics.log` 회전, refresh 취소 후 안전한 로컬 데이터 초기화
- 한국어 설정 화면과 실제 nonactivating overlay 접근성 트리 확인
- 최신 Sparkle feed에서 업데이트 발견 화면 표시 확인

릴리스 전 남은 수동 검증:

- `/Applications`에 설치한 ad-hoc 빌드의 로그인 항목 등록·로그아웃 후 재실행
- Sparkle 업데이트 설치·취소·실패 후 설정과 오버레이 위치 보존
- 다중 모니터, Spaces, 전체화면, Stage Manager, 절전·복귀
- 영어·한국어, VoiceOver, Reduce Motion/Transparency/Contrast
- 깨끗한 Mac에서 Gatekeeper 최초 실행 안내와 직접 다운로드
- Windows Release CI와 504개 WPF layout probe 실제 GitHub Actions 결과
