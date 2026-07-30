# dejavu website

dejavu 소개 및 다운로드를 위한 React + Vite 정적 웹사이트입니다.

## Development

```powershell
pnpm install
pnpm dev
```

## Production build

```powershell
pnpm build
```

생성되는 `dist` 폴더의 내용을 웹 서버에 배포합니다. 별도 서버 런타임이나 환경 변수는 필요하지 않습니다.

다운로드 버튼은 GitHub API에서 `taeminHan/dejavu`의 최신 Release를 확인합니다. 설치 프로그램이 있으면 해당 EXE를 직접 내려받고, 아직 릴리스가 없거나 API 호출이 실패하면 최신 릴리스 페이지로 연결됩니다.
