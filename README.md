# dejavu

Windows 11에서 Claude와 Codex 사용량을 항상 표시하는 네이티브 데스크톱 앱입니다.

현재 배포 버전은 `0.9.0-rc.1` 공개 릴리스 후보입니다. 정식판 배포 전 확인해야 할 항목은 [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)에 정리되어 있습니다.

[최신 버전 다운로드](https://github.com/taeminHan/dejavu/releases/latest) · [웹사이트 소스](website) · [문제 신고](https://github.com/taeminHan/dejavu/issues) · [MIT 라이선스](LICENSE)

- Claude: 5시간, 주간 전체, 주간 Fable 사용률
- Codex: 5시간 및 주간 사용률, 다음 초기화 시각
- Codex 초기화권: 보유 개수와 가장 가까운 만료 시각을 읽기 전용으로 표시
- 한 줄 또는 두 줄(Codex 위 · Claude 아래) 배치, 컴팩트/일반 크기
- 자동 감지(기본), Claude + Codex, Claude만, Codex만 서비스 표시 모드
- 진행률 막대 또는 퍼센트 표시, 투명도·색상·위치 설정
- 약 1분마다 자동 갱신하며 마지막 정상 값을 유지
- Windows 시작 시 실행과 알림 영역 메뉴 지원

Windows 11은 타사 앱이 작업표시줄 본문에 임의의 정보를 삽입하는 공식 API를 제공하지 않습니다. dejavu는 작업표시줄 위에 독립적인 상시 위젯을 두는 방식입니다.

## 데이터 연동

- Claude는 Claude Code의 로컬 로그인 정보를 일시적으로 사용합니다. 현재 사용량 경로는 공개된 제3자 API 계약이 아니므로 공개 출시 전에 별도 검토가 필요합니다.
- Codex는 설치된 Codex CLI의 공식 로컬 `app-server` 인터페이스를 사용합니다. 사용량과 초기화권 상태만 읽으며 초기화권을 사용하지 않습니다.
- OAuth 토큰, 대화 내용, 프롬프트는 설정이나 진단 파일에 저장하지 않습니다.

Codex 표시에는 로컬에서 실행 가능한 Codex CLI가 필요합니다. 필요하면 `CODEX_CLI_PATH` 환경 변수로 네이티브 `codex.exe` 경로를 지정할 수 있습니다.

## 시스템 요구 사항

- Windows 11 64비트(빌드 22000 이상)
- Claude 표시: 이 PC에 로그인된 Claude Code
- Codex 표시: 이 PC에서 실행 가능한 Codex CLI

앱은 사용자 권한으로 실행되며 관리자 권한을 요구하지 않습니다.

## 설치와 제거

서명된 설치 프로그램이 제공되는 경우 해당 설치 프로그램을 사용합니다. 휴대용 패키지는 압축을 푼 뒤 `dejavu.exe`를 실행합니다. 제거 후 사용자 설정과 진단 파일을 함께 지우려면 앱을 종료하고 `%LocalAppData%\dejavu` 폴더를 삭제합니다.

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

스크립트는 단일 실행 파일, 휴대용 ZIP, SHA-256 체크섬을 `outputs` 폴더에 만듭니다. Inno Setup Compiler가 설치되어 있으면 설치 프로그램도 함께 빌드합니다.

## 웹사이트

소개 사이트는 React + Vite 정적 사이트이며 `website` 폴더에 있습니다.

```powershell
cd website
pnpm install
pnpm build
```

서버에는 `website/dist`의 내용을 배포합니다. 다운로드 버튼은 GitHub Releases의 최신 배포 파일을 자동으로 확인하며, 릴리스가 없을 때는 최신 릴리스 페이지로 연결됩니다.
