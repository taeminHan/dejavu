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

생성되는 `dist` 폴더의 내용은 `https://taemtaem.dev/dejavu/` 경로를 기준으로 빌드됩니다. 별도 서버 런타임이나 환경 변수는 필요하지 않습니다.

다운로드 버튼은 GitHub API 응답을 기다리지 않고 최신 Release의 고정 자산명 `dejavu-Setup.exe`를 직접 내려받습니다. GitHub API는 버전 표시와 휴대용 ZIP 링크를 제공할 때만 사용합니다.

## Docker

이미지는 `/dejavu/` 경로를 8080 포트로 제공합니다.

```powershell
docker build --platform linux/amd64 -t dejavu-website:0.9.0-rc.1 .
docker run --rm -p 18080:8080 dejavu-website:0.9.0-rc.1
```

기존 `taemtaem.dev` Nginx 컨테이너와 `dejavu-site` 컨테이너를 같은 Docker 네트워크에 연결한 뒤, HTTPS 서버의 기존 `location /`보다 앞에 `deploy/taemtaem-nginx-location.conf` 내용을 추가합니다. `proxy_pass` 뒤에 슬래시를 붙이지 않아 `/dejavu/` 요청 경로가 그대로 유지되어야 합니다.
