# Public release checklist

## Required before public distribution

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
- [ ] Windows 11 100%, 125%, 150%, 200% DPI 검증
- [ ] Windows Defender 및 SmartScreen 제출 전 검사

## Release artifact checks

- [ ] Release 빌드에 PDB와 개발용 설정이 포함되지 않음
- [ ] `dejavu-desktop-win-Setup.exe`, `dejavu-Setup.exe`, full/delta nupkg, `releases.win.json` 생성 확인
- [ ] 실행 파일과 설치 프로그램의 제품명, 버전, 저작권 확인
- [ ] `Get-AuthenticodeSignature`로 공개 실행 파일의 서명 상태 `Valid` 확인
- [ ] Velopack 설치 프로그램이 현재 사용자 권한으로 동작
- [ ] 제거 시 실행 프로세스를 닫고 dejavu 사용자 데이터가 완전히 삭제되는지 확인
- [ ] `SHA256SUMS.txt`가 모든 공개 Velopack 자산의 해시와 일치
- [ ] 깨끗한 Windows 11 VM에서 Claude만, Codex만, 둘 다, 둘 다 없음 검증
