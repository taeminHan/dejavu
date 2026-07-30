import { useEffect, useState, type CSSProperties } from 'react'

const repositoryUrl = 'https://github.com/taeminHan/dejavu'
const releasesUrl = `${repositoryUrl}/releases/latest`

type ReleaseAsset = { name: string; browser_download_url: string }
type Release = { tag_name: string; html_url: string; assets: ReleaseAsset[] }

const features = [
  { number: '01', title: 'Claude와 Codex를 한눈에', body: '5시간·주간 사용률과 다음 초기화 시각을 하나의 작은 위젯에서 확인하세요.' },
  { number: '02', title: '방해하지 않는 상시 표시', body: '투명도, 위치, 크기와 한 줄·두 줄 배치를 작업 환경에 맞게 조절할 수 있습니다.' },
  { number: '03', title: '내 PC에서 직접 연결', body: '별도 dejavu 계정이나 중계 서버 없이 로컬 Claude Code와 Codex 로그인을 사용합니다.' },
]

const progressStyle = (value: number) => ({ '--progress': `${value}%` }) as CSSProperties

function App() {
  const [release, setRelease] = useState<Release | null>(null)
  const [menuOpen, setMenuOpen] = useState(false)

  useEffect(() => {
    const controller = new AbortController()
    fetch('https://api.github.com/repos/taeminHan/dejavu/releases/latest', {
      signal: controller.signal,
      headers: { Accept: 'application/vnd.github+json' },
    })
      .then((response) => (response.ok ? response.json() : Promise.reject()))
      .then((data: Release) => setRelease(data))
      .catch(() => undefined)
    return () => controller.abort()
  }, [])

  const installer = release?.assets.find((asset) =>
    asset.name.toLowerCase().includes('setup') && asset.name.endsWith('.exe'))
  const portable = release?.assets.find((asset) => asset.name.toLowerCase().includes('win-x64.zip'))
  const downloadHref = installer?.browser_download_url ?? release?.html_url ?? releasesUrl
  const releaseLabel = release?.tag_name ?? '최신 버전'

  return (
    <div className="site-shell">
      <header className="site-header">
        <a className="brand" href="#top" aria-label="dejavu 홈">
          <span className="brand-mark" aria-hidden="true"><span /></span><span>dejavu</span>
        </a>
        <button className="menu-button" type="button" aria-label="메뉴 열기" aria-expanded={menuOpen}
          onClick={() => setMenuOpen((open) => !open)}><span /><span /></button>
        <nav className={menuOpen ? 'site-nav is-open' : 'site-nav'} aria-label="주요 메뉴">
          <a href="#features" onClick={() => setMenuOpen(false)}>기능</a>
          <a href="#privacy" onClick={() => setMenuOpen(false)}>개인정보</a>
          <a href={repositoryUrl} target="_blank" rel="noreferrer">GitHub</a>
          <a className="nav-download" href={downloadHref}>다운로드</a>
        </nav>
      </header>

      <main id="top">
        <section className="hero-section">
          <div className="hero-copy">
            <div className="eyebrow"><span /> Windows 11용 AI 사용량 위젯</div>
            <h1>사용량을 확인하는<br />흐름까지 <em>가볍게.</em></h1>
            <p className="hero-description">Claude와 Codex의 남은 사용량을 바탕화면에서 바로 확인하세요. 작고, 조용하고, 필요할 때 늘 그 자리에 있습니다.</p>
            <div className="hero-actions">
              <a className="primary-button" href={downloadHref}>
                <span className="windows-glyph" aria-hidden="true"><i /><i /><i /><i /></span>Windows용 다운로드
              </a>
              <a className="secondary-button" href={repositoryUrl} target="_blank" rel="noreferrer">소스 코드 보기 <span aria-hidden="true">↗</span></a>
            </div>
            <p className="release-note">{releaseLabel} · Windows 11 x64 · 무료</p>
          </div>

          <div className="hero-visual" aria-label="dejavu 위젯 미리보기">
            <div className="ambient ambient-one" /><div className="ambient ambient-two" />
            <div className="widget-window">
              <div className="widget-topbar">
                <div className="widget-brand"><span className="brand-mark small"><span /></span> dejavu</div>
                <div className="window-controls" aria-hidden="true"><i /><i /><i /></div>
              </div>
              <div className="service-row">
                <div className="service-heading"><strong>Codex</strong><span>주간 초기화 금 15:00</span></div>
                <div className="meter-line"><div className="meter"><i style={progressStyle(39)} /></div><b>39%</b></div>
                <div className="service-meta"><span>5시간 —</span><span>초기화권 2개</span></div>
              </div>
              <div className="service-divider" />
              <div className="service-row">
                <div className="service-heading"><strong>Claude</strong><span>5시간 초기화 11:42</span></div>
                <div className="meter-line"><div className="meter"><i style={progressStyle(16)} /></div><b>16%</b></div>
                <div className="service-meta"><span>주간 20%</span><span>Fable 27%</span></div>
              </div>
              <div className="live-pill"><i /> 최신 상태</div>
            </div>
            <div className="mini-widget">
              <span>Codex</span><div className="meter"><i style={progressStyle(39)} /></div><b>39%</b>
              <span>Claude</span><div className="meter"><i style={progressStyle(16)} /></div><b>16%</b>
            </div>
          </div>
        </section>

        <section className="trust-strip" aria-label="제품 특징 요약">
          <span>항상 표시</span><i /><span>약 1분 자동 갱신</span><i /><span>별도 계정 없음</span><i /><span>소스 공개</span>
        </section>

        <section className="features-section" id="features">
          <div className="section-heading"><p>WHY DEJAVU</p><h2>확인은 빠르게.<br />집중은 그대로.</h2></div>
          <div className="feature-grid">
            {features.map((feature) => (
              <article className="feature-card" key={feature.number}>
                <span className="feature-number">{feature.number}</span>
                <div className={`feature-illustration illustration-${feature.number}`} aria-hidden="true"><span /><span /><span /></div>
                <h3>{feature.title}</h3><p>{feature.body}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="privacy-section" id="privacy">
          <div className="privacy-orbit" aria-hidden="true"><span className="brand-mark large"><span /></span></div>
          <div className="privacy-copy">
            <p className="section-kicker">LOCAL FIRST</p><h2>당신의 데이터는<br />당신의 PC에.</h2>
            <p>dejavu는 자체 계정이나 중계 서버를 운영하지 않습니다. 사용량은 이 PC에 로그인된 Claude Code와 Codex에서 조회하며 토큰과 대화 내용은 dejavu 설정에 저장하지 않습니다.</p>
            <a href={`${repositoryUrl}/blob/main/PRIVACY.md`} target="_blank" rel="noreferrer">개인정보 처리 방식 자세히 보기 <span aria-hidden="true">→</span></a>
          </div>
        </section>

        <section className="download-section" id="download">
          <div><p className="section-kicker">READY WHEN YOU ARE</p><h2>사용량 대신,<br />작업에 집중하세요.</h2><p>Windows 11에서 바로 시작할 수 있습니다.</p></div>
          <div className="download-card">
            <a className="primary-button large-button" href={downloadHref}>
              <span className="windows-glyph" aria-hidden="true"><i /><i /><i /><i /></span>Windows용 다운로드
            </a>
            <div className="download-meta"><span>{releaseLabel}</span><span>Windows 11 · x64</span></div>
            {portable && <a className="portable-link" href={portable.browser_download_url}>휴대용 ZIP 받기</a>}
          </div>
        </section>
      </main>

      <footer>
        <a className="brand footer-brand" href="#top"><span className="brand-mark" aria-hidden="true"><span /></span><span>dejavu</span></a>
        <p>Claude와 Codex 사용량을 위한 작은 Windows 위젯.</p>
        <div className="footer-links"><a href={repositoryUrl} target="_blank" rel="noreferrer">GitHub</a><a href={`${repositoryUrl}/blob/main/PRIVACY.md`} target="_blank" rel="noreferrer">개인정보</a><a href={`${repositoryUrl}/blob/main/SECURITY.md`} target="_blank" rel="noreferrer">보안</a></div>
        <small>© 2026 taeminHan and contributors · MIT License</small>
      </footer>
    </div>
  )
}

export default App
