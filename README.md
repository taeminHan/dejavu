# dejavu

Windows 11에서 Claude와 Codex 사용량을 항상 표시하는 네이티브 데스크톱 앱입니다.

### 이름이 Dejavu인 이유는
### 그냥 리센느 Deja vu 듣다가 떠오른 아이디어여서 그렇습니다.

### 리센느 화이팅

현재 공개 배포 버전은 `0.9.0-rc.7`입니다. rc.2부터 Velopack 기반 설치와 앱 내 자동 업데이트를 지원합니다. 정식판 배포 전 확인해야 할 항목은 [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)에 정리되어 있습니다.

[공식 웹사이트](https://taemtaem.dev/dejavu/) · [사용 설명서](https://taemtaem.dev/dejavu/guide/) · [최신 버전 다운로드](https://github.com/taeminHan/dejavu/releases/latest) · [문제 신고](https://github.com/taeminHan/dejavu/issues) · [MIT 라이선스](LICENSE)

- Claude: 5시간, 주간 전체, 계정에 제공되는 주간 Fable 사용률
- Codex: 5시간 및 주간 사용률, 다음 초기화 시각
- Codex 초기화권: 보유 개수와 가장 가까운 만료 시각을 읽기 전용으로 표시
- 한 줄 또는 두 줄(Codex 위 · Claude 아래) 배치, 작음/중간/큼 크기
- 자동 감지(기본), Claude + Codex, Claude만, Codex만 서비스 표시 모드
- 진행률 막대 또는 퍼센트 표시, 투명도·색상·위치 설정
- 약 1분마다 자동 갱신하며 마지막 정상 값을 유지
- Windows 시작 시 실행과 알림 영역 메뉴 지원
- 실행 시 한 번 업데이트 확인, 앱 안에서 다운로드·적용·재시작

Windows 11은 타사 앱이 작업표시줄 본문에 임의의 정보를 삽입하는 공식 API를 제공하지 않습니다. dejavu는 작업표시줄 위에 독립적인 상시 위젯을 두는 방식입니다.

## 데이터 연동

- Claude Code가 로그인되어 있으면 로컬 로그인 정보를 일시적으로 사용합니다. 이때 Anthropic 계정 응답에 Fable 전용 한도가 포함된 경우 Fable도 표시합니다. Claude Desktop만 사용하는 경우에는 토큰 대신 최근 5시간·주간 사용률 기록을 읽으며 Fable과 초기화 시각은 제공되지 않습니다. 두 경로 모두 공개된 제3자 연동 계약은 아닙니다.
- Codex는 Codex Desktop에 포함된 런타임 또는 별도로 설치된 CLI의 공식 로컬 `app-server` 인터페이스를 사용합니다. CLI를 직접 사용하는 사람일 필요는 없으며, 미로그인 상태에서는 dejavu가 공식 ChatGPT 브라우저 로그인을 시작합니다. 사용량과 초기화권 상태만 읽으며 초기화권을 사용하지 않습니다.
- OAuth 토큰, 대화 내용, 프롬프트는 설정이나 진단 파일에 저장하지 않습니다.

Codex 표시에는 Codex Desktop 또는 로컬에서 실행 가능한 Codex CLI가 필요합니다. 필요하면 `CODEX_CLI_PATH` 환경 변수로 네이티브 `codex.exe` 경로를 지정할 수 있습니다.

## 시스템 요구 사항

- Windows 11 64비트(빌드 22000 이상)
- Claude 표시: 이 PC에 로그인된 Claude Code 또는 최근 사용 기록이 있는 Claude Desktop
- Codex 표시: Codex Desktop 또는 이 PC에서 실행 가능한 Codex CLI

앱은 사용자 권한으로 실행되며 관리자 권한을 요구하지 않습니다.

## 설치와 제거

GitHub Releases의 `dejavu-Setup.exe`를 실행하면 현재 사용자 계정에 설치됩니다. 설치 버전은 실행할 때 한 번 GitHub Releases를 확인하며, 새 버전이 있으면 앱 안에서 다운로드·적용한 뒤 재시작할 수 있습니다. 업데이트 확인은 설정에서 끌 수 있습니다.

기존 Inno Setup 기반 `0.9.0-rc.1` 사용자는 첫 Velopack 버전만 설치 프로그램으로 한 번 다시 설치해야 합니다. 그 이후 버전부터는 앱 안에서 업데이트됩니다. Windows 설정의 **설치된 앱**에서 dejavu를 제거하면 앱·바로가기·시작프로그램 등록뿐 아니라 `%LocalAppData%\dejavu`의 설정, 위젯 위치, 캐시와 진단 파일도 함께 삭제됩니다. Claude Code와 Codex의 로그인 정보 및 해당 프로그램의 데이터는 삭제하지 않습니다.

Windows SmartScreen의 게시자 경고가 표시되는 서명되지 않은 빌드는 정식 배포본으로 간주하지 않습니다. 배포 파일은 함께 제공되는 `SHA256SUMS.txt`와 대조할 수 있습니다.

## 배포 문서

- [개인정보 안내](PRIVACY.md)
- [보안 정책](SECURITY.md)
- [변경 내역](CHANGELOG.md)
- [제품화 상태](PRODUCTIZATION.md)
- [출시 점검표](RELEASE_CHECKLIST.md)

## 로컬 릴리스 빌드

PowerShell에서 다음 명령을 실행합니다.

```powershell
.\tools\BuildRelease.ps1
```

스크립트는 Velopack 설치 프로그램, 전체 패키지, 업데이트 피드와 SHA-256 체크섬을 `outputs/dejavu-velopack-releases`에 만듭니다. 이전 GitHub Release를 받아 델타 패키지도 만들려면 `-DownloadPrevious`를 추가합니다.

```powershell
.\tools\BuildRelease.ps1 -DownloadPrevious
```
