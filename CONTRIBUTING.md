# Contributing to dejavu

dejavu 개선 제안과 버그 제보를 환영합니다.

## 시작하기

앱에는 Windows 11과 .NET 10 SDK가 필요합니다.

```powershell
dotnet build -c Release
```

## 변경 제출

1. 관련 이슈가 있는지 먼저 확인합니다.
2. 한 변경에는 한 가지 목적만 담습니다.
3. 앱 변경은 Release 빌드를 통과시킵니다.
4. 토큰, Claude/Codex 로그인 파일, 개인 경로, 진단 파일을 커밋하지 않습니다.

Claude 사용량 연동은 공개된 제3자 API 계약이 아니므로 이 경로를 수정할 때는 호환성과 개인정보 안내를 함께 검토해야 합니다.
