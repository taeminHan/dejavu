# Security policy

## Supported versions

정식 출시 후 최신 버전만 보안 업데이트 대상으로 지원합니다.

## Reporting a vulnerability

OAuth 토큰 노출, 로컬 파일 권한, 업데이트 또는 설치 프로그램 무결성과 관련된 문제는 공개 이슈로 올리기 전에 비공개 보안 채널로 신고해야 합니다.

민감한 내용은 [GitHub Security Advisory](https://github.com/taeminHan/dejavu/security/advisories/new)를 통해 비공개로 신고해 주세요. 일반 버그는 [GitHub Issues](https://github.com/taeminHan/dejavu/issues)에 등록할 수 있습니다.

## Security properties

- 토큰은 사용량 요청을 만드는 동안에만 메모리에서 사용합니다.
- 토큰과 대화 내용은 설정, 상태 파일, 로그에 기록하지 않습니다.
- Codex 초기화권은 조회만 하며 소비 API를 호출하지 않습니다.
- dejavu는 관리자 권한을 요구하지 않습니다.
