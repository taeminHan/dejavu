# Public release checklist

`0.9.7`는 제품 소유자의 명시적 요청에 따라 Windows 제품 아이콘과 추가 브랜드 누락을 수정하고, 실제 배포 파일 검증 후 공개합니다. 무료 배포 방침을 유지하며 Windows 공인 코드 서명·macOS Developer ID/공증을 받은 제품이라고 표시하지 않습니다. 아래 수동 검증과 신뢰 배포의 미완료 항목은 그대로 남깁니다.

## 0.9.7 release validation scope — 2026-10-17

- 제품 로고: canonical SVG → 앱 ICO/트레이 단색 ICO → 앱/창/설치/실행 stub/바로가기 아이콘. 각 ICO는 16/20/24/32/40/48/64/128/256px를 포함한다.
- 추가 누락 수정: 시작 안내·상세 사용량·업데이트 헤더의 옛 제품 글리프와 위젯의 미지정 창 아이콘. 테마별 제품 글리프 메타데이터를 제거하고, 시작 안내 합성 캡처의 바깥 여백 잘림도 고친다.
- 사용자 설정, Percentage/Hidden 선택, Orbit/Paper Ink와 위젯 기하를 유지한다. macOS 기능 코드는 변경하지 않고 기존 통합 릴리즈 방식으로 버전만 맞춘다.
- [ ] 전체 Windows 빌드/XAML/504 위젯/1512 작업표시줄/166 전이/Orbit/Retro/설정/수집 회귀 검사.
- [ ] 승인된 SVG와 production SVG 일치, manifest의 ICO 27개 frame/해시, 실제 full/portable/설치 EXE/stub의 PE icon 리소스 일치 검사.
- [ ] 격리된 Windows runner의 실제 무인 설치, 생성된 Start Menu 바로가기 target/IconLocation 및 Apps & Features DisplayIcon 검증.
- [ ] 독립 runner에 공개 0.9.6을 실제 설치하고 구형 아이콘을 확인한 뒤, 새 실제 패키지의 Update.exe apply --norestart 실행. 기존 바로가기와 앱/stub/updater가 모두 새 로고로 바뀌는지 확인. 태그 workflow도 초안에서 재다운로드한 실제 파일로 이 검사를 수행한다.
- [ ] 설치된 실제 EXE의 controller-free `--validate-brand` 실행: 48개 창·단색 트레이 크기/밝기·고정 브랜드색과 runtime PNG/JSON 검증. 실제 사용자 인증·공급자·설정 저장은 사용하지 않는다.
- [ ] 성공한 사전 CI의 패키지/원본 및 shell-selected 아이콘 PNG를 내려받아 육안 확인.
- [ ] 태그 workflow는 초안만 작성. 실제 업로드 파일을 다시 내려받아 PE icon/체크섬/버전/설치 증거와 검사한 패키지 hash 일치를 확인한 뒤 별도 최종 공개.
- [ ] 0.9.7 공통 버전/태그 대상 및 Mac build >45, Mac 서명·업데이트 피드·공개 파일 해시 검증.

### Additional omission audit

- 위 항목은 소스 및 배포 아이콘의 실제 누락이며 이번 패치에서 수정한다. 일반 Windows icon cache가 원인이라고 가정하지 않는다. 기존에 고정한 taskbar 아이콘/캐시까지 OS가 즉시 다시 그린다는 보장은 하지 않는다.
- 별도 미완료 계획: Studio/Arcade/Prism/Console의 전면 테마 구조 이관 및 상세 열기 모션. 0.9.7 로고 통일이 그 구현 완료를 뜻하지 않는다.
- 별도 수동 수락: 실제 Windows 11의 100/125/150/200% 물리 DPI, 대화형 Explorer 트레이/고정 바로가기, 키보드·스크린리더, 이전 설치본의 앱 내 GUI 다운로드·적용·재시작. 격리된 실제 updater package apply는 추가하지만 전체 GUI 자동 업데이트 수락과 같지 않다. CI 설치 결과와 합성 WPF PNG로 이 항목을 통과했다고 주장하지 않는다.
- 공인 서명/Apple 공증/App Group 등 외부 등록 항목도 아래와 같이 미완료 상태를 유지한다.

## 0.9.6 release validation scope — 2026-10-13

- Windows: Codex 다중 버킷 처리, 손상된 Claude 인증의 Desktop 대체 수집, Codex 취소/완료 배수, 테마 리소스 14곳, 기본 강조색 일치 수정.
- macOS: 공식 로그인 흐름, 이전 Claude 로그인의 명시적 재사용 선택, 네이티브 설정/상세/시작 안내, 갱신·초기화·업데이트 상태·아이콘 개선. 사용자가 이전 로그인 선택 후 실제 Claude 사용량 표시를 확인했다.
- 기존 사용자 설정과 플로팅/WidgetKit 구현을 보존한다. 인증 정보를 복사·삭제하지 않고, 합성 검사에서 실제 계정·공급자 API·모델 요청을 사용하지 않는다.
- [x] macOS 핵심 211 tests, AppModel 65 checks, UpdateCoordinator 10 checks 및 네이티브 UI 474 states 로컬 검사(0.9.6 최종 재검사 로그는 `docs/MACOS_DEVELOPMENT.md`).
- [x] Windows CI에서 Release 빌드, XAML XML, 기존 전체 위젯/작업표시줄/Orbit/Retro, 설정 144/업데이트 48, Claude 파서 20 검사.
- [x] 새 Windows provider 72 checks 및 실제 WPF 테마 36 states/강조색 5 checks 검사. 기존 연결 토큰 방식의 `early-abort reproduced`를 Windows runner에서 확인했으며, 수정된 실제 수집 코드는 취소 후 완료 표식 보존과 기존 15초 제한을 통과했다.
- [x] 태그 대상 7ccadbe, 공통 0.9.6 버전, macOS build45 >42 확인.
- [x] 2026-10-17 단일 정식 Release 공개, 설치 파일/업데이트 피드/전체 체크섬 재다운로드 검사. [release run39016455771](https://github.com/taeminHan/dejavu/actions/runs/39016455771).
- 개발 기기에서는 WPF를 실행하지 않는다. Windows 설치형 업그레이드·실제 물리 DPI·키보드·다중 모니터와 macOS 설치형 Sparkle/App Group은 CI/합성 검사와 별도 수락 범위다.

첫 전체 CI 근거: [8cea7e5 Windows/macOS 검사](https://github.com/taeminHan/dejavu/actions/runs/38365333008). 테마 수정 화면의 합성 WPF PNG도 별도 artifact로 보관한다. 이는 실제 설치 앱·물리 DPI 수락 검사와 다르다.

## 0.9.5 release validation scope — 2026-10-07

- Windows 개선 범위: 여섯 메뉴 설정 화면, Retro Night 픽셀 렌더링, Orbit 행성 순서, Fable 전용 한도 매핑.
- 필수 자동 검사: Release 빌드, 전체 위젯·작업표시줄·Orbit·Retro 프로브, 설정 144조합/업데이트 48상태, Claude 파서 20사례.
- 태그 workflow는 기존 macOS 코드를 같은 제품 버전으로 재패키징합니다. 이번 Windows 작업에서 Mac 기능을 수정하거나 네이티브 Mac 사용성을 검증하지 않습니다.
- 공개 전 workflow 성공, 정식 릴리스 여부, 태그 대상, 설치 파일·업데이트 피드·패키지와 SHA-256을 확인합니다.
- 아래 수동 설치·업데이트·제거, 실제 DPI·포커스·접근성 및 공인 서명 항목은 자동 검사와 별개이며 미완료 상태를 유지합니다.

## Outstanding before signed/trusted distribution

- [x] 제품 소유자와 MIT 배포 라이선스 확정
- [ ] `dejavu` 상표 및 제품명 충돌 검토
- [ ] SignPath Foundation 승인 및 GitHub trusted build 연동 완료
- [ ] 신뢰된 코드 서명 인증서로 `dejavu.exe`, 업데이트 패키지 내부 실행 파일과 설치 프로그램 서명
- [ ] SignPath에서 릴리스별 수동 서명 승인 완료
- [ ] 서명 후 SHA-256 체크섬 생성 및 공개
- [x] GitHub Issues 및 Security Advisory 문의 경로 입력
- [ ] Claude 사용량 연동에 대한 Anthropic 이용약관 또는 별도 승인 검토
- [ ] 설치, 업그레이드, 제거, 시작 프로그램, 다중 모니터 동작 검증
- [ ] 기존 Inno `0.9.0-rc.1`에서 첫 Velopack 버전 수동 재설치 안내 검증
- [ ] Velopack 설치 버전에서 다음 버전 감지, 다운로드, 적용, 재시작 검증
- [ ] 업데이트 다운로드 실패와 오프라인 상태에서 기존 버전이 계속 실행되는지 검증
- [ ] 자동 업데이트 확인 ON/OFF, 앱 시작 후 확인, 다음 로컬 정시 경계에서 확인 검증
- [ ] 시작·정시·수동 확인이 겹쳐도 조회가 한 번만 실행되고 수동 결과가 정상 표시되는지 검증
- [ ] 같은 버전 자동 알림은 재시작 후에도 반복되지 않고 새 버전은 한 번 다시 알리는지 검증
- [ ] 트레이 알림 클릭과 트레이 숨김 대체 화면이 테마에 맞게 동작하는지 검증
- [ ] 절전 복귀·시스템 시간 변경 후 누락 횟수와 무관하게 한 번만 확인하고 다음 정시에 다시 맞는지 검증
- [ ] 자동 확인 중 설정을 OFF로 바꾸거나 앱을 종료해도 뒤늦은 알림·창·예외가 발생하지 않는지 검증
- [ ] Windows 11 100%, 125%, 150%, 200% DPI 검증
- [ ] 125%·150%·200%에서 작업표시줄 오른쪽·오른쪽 위·사용자 지정 위치, 드래그 이동과 상세 사용량 창이 화면 안 올바른 위치에 표시되는지 검증
- [ ] Win+L/잠금 해제, 절전/복귀, Explorer 재시작, RDP·디스플레이 전환 뒤 위젯 Topmost·포커스·위치·크기 검증
- [ ] Windows Defender 및 SmartScreen 제출 전 검사

## In-taskbar placement checks

- [ ] 레이아웃 프로브가 `Taskbar layout matrix: 1512 checked, 0 clipped, 0 over band, 0 mismatched`를 출력
- [ ] 레이아웃 프로브가 `Taskbar tracker transitions: 166 checked, 0 mismatched`를 출력
- [ ] **작업표시줄 안 · 시계 옆**에서 위젯이 알림 영역 왼쪽, 작업표시줄 높이 안에 표시되고 드래그되지 않으며 좌클릭 상세·우클릭 설정이 동작
- [ ] 작업표시줄 클릭, 시작 메뉴, 트레이 플라이아웃, 점프 목록 사용 시 포커스를 가져가지 않고 열린 메뉴를 가리지 않은 채 작업표시줄 위로 복귀
- [ ] 전체 화면 동영상과 테두리 없는 전체 화면 게임에서 숨겨졌다가 종료 후 다시 표시
- [ ] 작업 보기(Win+Tab), Alt+Tab, 스냅 도우미를 사용하는 동안 위젯이 숨겨지지 않음
- [ ] 작업표시줄 자동 숨기기, Explorer 재시작, 로그온 직후 대체 표시·재배치 동작 확인
- [ ] Windows 밝게·어둡게 모드와 고대비에서 글자색이 작업표시줄 테마를 따르고, 고대비 테마를 서로 바꿔도 새 색상으로 바뀜
- [ ] 100%, 125%, 150%, 200% 배율에서 작업표시줄 안 배치와 대체 위젯 위치 확인
- [ ] 왼쪽 정렬 작업표시줄과 위젯 단추, 아이콘이 많은 가운데 정렬 작업표시줄, RTL 언어 환경 확인
- [ ] ExplorerPatcher·StartAllBack 환경에서 기존 떠 있는 위젯으로 대체 표시
- [ ] 배치를 다른 위치로 바꾸면 작업표시줄 추적 타이머·훅·숨은 창이 남지 않고, `status.json`에 다른 프로세스의 창 제목·클래스가 기록되지 않음

## Release artifact checks

- [ ] Release 빌드에 PDB와 개발용 설정이 포함되지 않음
- [ ] `dejavu-desktop-win-Setup.exe`, `dejavu-Setup.exe`, full/delta nupkg, `releases.win.json` 생성 확인
- [ ] 실행 파일과 설치 프로그램의 제품명, 버전, 저작권 확인
- [ ] `Get-AuthenticodeSignature`로 공개 실행 파일의 서명 상태 `Valid` 확인
- [ ] Velopack 설치 프로그램이 현재 사용자 권한으로 동작
- [ ] 제거 시 실행 프로세스를 닫고 dejavu 사용자 데이터가 완전히 삭제되는지 확인
- [ ] `SHA256SUMS.txt`가 모든 공개 Velopack 자산의 해시와 일치
- [ ] 깨끗한 Windows 11 VM에서 Claude만, Codex만, 둘 다, 둘 다 없음 검증

## macOS release and Sparkle checks

- [ ] 태그 `v<version>`, `ClaudeUsageTray.csproj`의 Windows 버전, macOS `CFBundleShortVersionString`, Sparkle `shortVersionString`이 모두 일치함
- [ ] 태그 workflow에서 Windows와 macOS 자산이 모두 검증된 뒤 하나의 GitHub Release가 공개됨
- [ ] Developer ID Application 인증서와 `group.dev.taemtaem.dejavu` App Group이 같은 Team에 등록됨
- [ ] Release build에 Sparkle EdDSA 공개 키가 포함되고 private key는 CI secret에만 존재함
- [ ] `BuildMacRelease.sh`가 app/DMG 공증, staple, `codesign`, `spctl`을 모두 통과함
- [ ] `Dejavu-macOS-arm64.dmg`, 업데이트 ZIP, `appcast-macos.xml`, macOS SHA-256 생성 확인
- [ ] 깨끗한 Apple Silicon Mac에서 DMG 설치와 Gatekeeper 최초 실행 확인
- [ ] 이전 macOS beta에서 다음 beta 감지, EdDSA 검증, 설치, 재시작, 설정·위치 유지 확인
- [ ] 자동 확인 ON/OFF, 시작 4초 후, 다음 로컬 정각, 절전 복귀, 시간 변경 동작 확인
- [ ] 수동 current/offline/error UI와 자동 오류 무표시, 같은 버전 알림 1회 정책 확인
- [ ] signed app에서 Widget gallery, Desktop/Notification Center와 App Group snapshot 확인

### Temporary free-distribution route

- [ ] `BuildMacFreeRelease.sh`로 ad-hoc DMG/ZIP과 EdDSA appcast 생성
- [ ] ZIP 내부 앱의 ad-hoc 서명과 appcast `sparkle:edSignature` 확인
- [ ] SHA-256을 GitHub Release 설명 또는 asset으로 함께 공개
- [ ] 다운로드 페이지에 Apple 미공증 build와 **개인정보 보호 및 보안 → 확인 없이 열기** 절차 명시
- [ ] 깨끗한 Mac에서 최초 실행 경고, 수동 승인, 메뉴 막대, 플로팅 오버레이 검증
- [ ] 0.9.0에서 더 높은 `CFBundleVersion` 테스트 build로 Sparkle 설치·재시작 검증
- [ ] 시스템 Widget의 App Group 공유는 Developer ID 전까지 보장 기능에서 제외
