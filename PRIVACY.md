# dejavu 개인정보 안내

최종 수정일: 2026-09-28

dejavu는 Claude와 Codex 사용량을 Windows 바탕화면에 표시하는 로컬 데스크톱 애플리케이션입니다. dejavu가 운영하는 별도 서버나 사용자 계정 시스템은 없습니다.

## 처리하는 정보

- Claude Code가 로그인되어 있으면 로컬 로그인 파일에서 사용량 요청에 필요한 OAuth 액세스 토큰과 만료 시각을 메모리에서 일시적으로 읽습니다.
- Claude Desktop만 사용하는 경우 `%AppData%\Claude\plan-usage-history.json`에서 최근 5시간·주간 사용률과 기록 시각만 읽습니다. Desktop 로그인 토큰, 브라우저 쿠키, 대화 내용은 읽지 않습니다.
- Codex를 표시할 때 Codex Desktop에 포함된 런타임 또는 Codex CLI의 로컬 app-server에서 사용률, 초기화 시각, 플랜 유형, 초기화권 개수와 만료 시각을 읽습니다.
- 위젯 배치에서 **작업표시줄 안 · 시계 옆**을 선택한 동안에만, 전체 화면 앱·게임을 감지해 위젯을 잠시 숨기기 위해 Windows의 포그라운드 창 전환 알림을 받고, 전환될 때와 그 직후(약 0.3초·0.6초 뒤), Windows 설정이 바뀔 때, 그리고 1초 간격(작업표시줄 재배치 직후 잠시 동안은 0.25초 간격)으로 현재 포그라운드 창의 프로세스 ID, 창 클래스 이름, 창 스타일, 최대화 여부, 모니터와 위치·크기를 이 PC에서 확인합니다. 다른 앱의 창 제목이나 내용은 읽지 않으며, 이 정보는 저장하거나 전송하지 않습니다. 다른 배치를 선택하면 포그라운드 창 전환 알림 수신도 중단합니다.
- 앱 설정, 위젯 위치, 마지막 사용량 수치와 연결 상태를 `%LocalAppData%\dejavu`에 저장합니다.
- 오류 발생 시 로컬 `crash.log`에 오류 내용과 PC의 파일 경로가 포함될 수 있습니다.

## 네트워크 전송

- Claude 사용량 요청은 이 PC에서 Anthropic 서비스로 직접 전송됩니다. 이때 Claude 액세스 토큰이 인증 헤더에 포함됩니다.
- Codex 사용량은 이 PC에서 실행되는 Codex app-server를 통해 조회됩니다. 이후 OpenAI 서비스와의 통신은 Codex가 관리합니다.
- dejavu 개발자가 운영하는 서버로 토큰, 사용량, 프롬프트 또는 대화 내용을 전송하지 않습니다.

## 저장하지 않는 정보

dejavu는 OAuth 액세스 토큰, 프롬프트, 대화 내용, 브라우저 비밀번호를 자체 설정이나 진단 파일에 저장하지 않습니다. 초기화권은 읽기 전용으로 표시하며 자동으로 사용하지 않습니다.

## 데이터 삭제

Windows 설정의 **설치된 앱**에서 dejavu를 제거하면 앱 설정, 위젯 위치, 캐시와 로컬 진단 파일이 함께 삭제됩니다. 제거 작업은 Claude Code와 Codex의 로그인 정보나 해당 프로그램의 데이터에는 영향을 주지 않습니다.

## 연동 관련 주의

Claude Code 사용량 조회 방식과 Claude Desktop 로컬 기록 형식은 Anthropic이 외부 앱용 공개 연동 계약으로 문서화한 방식이 아닙니다. Desktop 기록에는 초기화 시각과 Fable 사용률이 포함되지 않습니다. Anthropic의 변경에 따라 기능이 중단될 수 있습니다. Codex 사용량 조회는 OpenAI가 문서화한 로컬 app-server 인터페이스를 사용합니다.

## macOS

macOS 앱도 별도 서버 없이 이 Mac 안에서만 사용량을 읽습니다.

- 사용자가 설정에서 **Claude 상태 줄 연결**을 선택한 경우에만 `~/.claude/settings.json`의 상태 줄 설정을 읽고 바꾸며, Claude Code가 전달하는 5시간·주간 사용률과 초기화 시각만 `~/Library/Application Support/dejavu/claude-status.json`에 저장합니다.
- 상태 줄에 최근 값이 없으면 Claude Desktop이 남기는 `~/Library/Application Support/Claude/plan-usage-history.json`에서 가장 최근 기록의 5시간·주간 사용률과 기록 시각만 읽고, 이 기록이 상태 줄 값보다 최신이면 Desktop 기록을 표시합니다. 파일은 읽기 전용으로 열어 메모리로 복사한 즉시 닫고, 수정·잠금·삭제하지 않습니다. 기록에 포함된 조직 식별자와 그 밖의 항목은 해석하거나 저장하지 않으며, Desktop 로그인 토큰, 쿠키, 대화 내용도 읽지 않습니다. 40분보다 오래된 기록의 사용률은 표시하지 않고 `--%`와 기록 시각만 보여 주며, 7일이 지난 기록은 사용하지 않습니다.
- 설정에서 **Fable 사용량 활성화**를 켠 경우에만 macOS 승인 아래 키체인의 `Claude Code-credentials` 항목을 읽어 OAuth 액세스 토큰을 메모리에서만 사용하고, Anthropic 서비스에 Fable 사용량을 직접 요청합니다. 무료 ad-hoc 서명 빌드는 업데이트할 때마다 macOS가 키체인 접근을 다시 물을 수 있습니다. 접근 거부, 토큰 만료 같은 결과는 원인 분류만 화면에 표시하며 토큰이나 응답 내용은 저장하거나 기록하지 않습니다.
- Codex 사용량은 로컬 Codex app-server에서 읽으며 Codex 자격 증명은 직접 읽지 않습니다.
- 설정, 진단 상태와 사용량 스냅샷은 `~/Library/Application Support/dejavu`에, 시스템 위젯용 최소 스냅샷은 App Group 컨테이너에 저장합니다. 여기에는 토큰, 조직·계정 식별자, 프롬프트와 대화 내용이 포함되지 않습니다.
- 설정의 **Dejavu 데이터 초기화**는 Dejavu가 만든 파일만 제거하며 Claude, Claude Desktop, Codex의 파일과 키체인 항목은 삭제하지 않습니다.

## 문의

일반 문의는 [GitHub Issues](https://github.com/taeminHan/dejavu/issues)를 이용해 주세요. 토큰이나 개인 정보가 포함될 수 있는 내용은 공개 이슈에 작성하지 말고 [GitHub Security Advisory](https://github.com/taeminHan/dejavu/security/advisories/new)를 이용해 주세요.
