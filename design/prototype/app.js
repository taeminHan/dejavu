'use strict';
const state={os:'windows',page:'display',visual:'modern',placement:'taskbar',menuMetric:'session',service:'auto',density:'medium',rows:false,progress:true,opacity:100,claude:true,codex:true,startup:false,topmost:true,notify:true,animations:true,reducedMotion:false,reducedTransparency:false,macAppearance:'auto',windowsAppearance:'dark',x:22,y:194,customPosition:false};
const systemAppearance=matchMedia('(prefers-color-scheme: dark)');
const $=s=>document.querySelector(s);
const icon=name=>DejavuIcons.svg(name);
const actionLabel=(name,label)=>`${icon(name)}<span>${label}</span>`;
const scrollBehavior=()=>DejavuMotion.reduced()?'auto':'smooth';
const iconExamples=[['display','표시','화면과 배치'],['appearance','꾸미기','색상과 테마'],['connections','연결','서비스 연결'],['behavior','동작','실행과 알림'],['updates','업데이트','새 버전 확인'],['privacy','개인정보','데이터 보호'],['settings','설정','환경설정 열기'],['refresh','새로고침','사용량 다시 확인'],['details','상세 사용량','모든 한도 보기'],['expand','넓게 보기','미리보기 확대'],['close','닫기','패널 닫기'],['sun','색상 모드','라이트 / 다크']];
$('#icon-grid').innerHTML=iconExamples.map(([name,label,meaning])=>`<article class="icon-sample"><div class="icon-sample-glyph">${icon(name)}${name==='sun'?icon('moon'):''}</div><h3>${label}</h3><p>${meaning}</p></article>`).join('');
const taskbar=$('.desktop-taskbar');
const taskbarHost=$('#taskbar-widget-host');
const desktop=$('#desktop');
const screenViewport=$('#screen-viewport');
desktop.appendChild($('#details'));
const systemPaths={search:'<circle cx="7" cy="7" r="4.5"/><path d="m10.5 10.5 3.5 3.5"/>',chevron:'<path d="m3 10 5-5 5 5"/>',wifi:'<path d="M1 5a11 11 0 0 1 14 0M3.5 8a7 7 0 0 1 9 0M6 11a3 3 0 0 1 4 0"/><circle cx="8" cy="14" r=".5" fill="currentColor"/>',volume:'<path d="M2 6h3l4-3v10l-4-3H2zM12 5a5 5 0 0 1 0 6M14 3a8 8 0 0 1 0 10"/>',battery:'<rect x="1" y="4" width="12" height="8" rx="1.5"/><path d="M15 6v4"/><rect x="3" y="6" width="7" height="4" rx=".5" fill="currentColor" stroke="none"/>'};
document.querySelectorAll('[data-symbol]').forEach(n=>{n.innerHTML=`<svg viewBox="0 0 16 16" aria-hidden="true">${systemPaths[n.dataset.symbol]}</svg>`;});
const metrics={claude:[['Claude 5H','5시간',8,'초기화까지 2시간 15분'],['주간','주간 전체',24,'금요일 오후 3:00 초기화'],['Fable','주간 Fable',3,'금요일 오후 3:00 초기화']],codex:[['Codex 5H','5시간',35,'초기화까지 1시간 40분'],['주간','주간',62,'일요일 오후 9:00 초기화']]};
const services=()=>['claude','codex'].filter(p=>state.service==='auto'?state[p]:state.service===p||state.service==='both');
const ready=p=>state[p];
const inTaskbar=()=>state.os==='windows'&&state.placement==='taskbar';
const inMenuBar=()=>state.os==='mac';
const menuMetric=p=>metrics[p][state.menuMetric==='weekly'?1:0];
function applyVisual(){
 for(const node of [$('.app-window'),$('#details'),$('#widget')]){
  node.classList.add('product-surface');
  // OS docking remains theme-neutral and uses its existing independent geometry.
  node.dataset.visual=inMenuBar()||node.id==='widget'&&inTaskbar()?'native':state.visual;
 }
}
function renderThemeLab(){
 $('#theme-grid').innerHTML=Object.entries(DejavuThemes).map(([id,t])=>`<article class="theme-card" data-visual="${id}"><header><h3>${t.name}</h3><span class="theme-number">${t.preserved?'기존안 유지':t.tag.split(' / ')[0]}</span></header><p class="theme-description">${t.desc}</p><p class="specimen-label">FLOATING WIDGET / FORM STUDY</p><div class="specimen-widget">${[['5H',8],['주간',24],['Fable',3]].map(([label,v])=>`<div class="specimen-metric"><small>${label}</small><b>${v}%</b>${DejavuProgress(v,id)}</div>`).join('')}</div><p class="specimen-label">DETAILS + CONTROLS / FORM STUDY</p><div class="specimen-panel"><header><span class="specimen-title">Claude</span><small>최신 상태</small></header><div class="specimen-row"><span>주간 전체</span><strong>24%</strong></div>${DejavuProgress(24,id)}<p class="specimen-reset">금요일 오후 3:00 초기화</p><div class="specimen-control"><span>사용량 그래프</span><span class="specimen-toggle" aria-hidden="true"></span></div></div><p class="theme-shape">${t.shape}</p><button class="theme-try" data-theme-try="${id}">${t.name} 체험하기</button></article>`).join('')+'<article class="orbit-keep"><p class="eyebrow">UNCHANGED / ORBIT</p><h3>Orbit은 그대로.</h3><p>행성 궤도 위젯과 태양계 상세창은 이번 재설계에서 제외합니다.<br><br>Field Notes도 기존 Paper Ink의 느낌을 유지합니다. 나머지 네 테마만 새 방향으로 개편합니다. Orbit을 다른 디자인으로 대체하지 않습니다.</p></article>';
}
function choices(key,items,extra=''){return `<div class="segmented" aria-label="${key}" ${extra}>${items.map(([v,t])=>`<button data-setting="${key}" data-value="${v}" aria-pressed="${state[key]===v}">${t}</button>`).join('')}</div>`;}
function toggle(key,title,desc){return `<label class="setting-row"><span><strong>${title}</strong><small>${desc}</small></span><input class="switch" type="checkbox" data-toggle="${key}" ${state[key]?'checked':''} aria-label="${title}"></label>`;}
function intro(num,title,desc){return `<p class="section-kicker">${num} / PREFERENCES</p><h2>${title}</h2><p class="section-desc">${desc}</p>`;}
const macPageTitles={display:'메뉴 막대',appearance:'모양',connections:'연결',behavior:'동작',updates:'업데이트',privacy:'개인정보'};
function macGroup(title,rows,help=''){return `<section class="mac-form-section"><h3>${title}</h3><div class="mac-form-group">${rows}</div>${help?`<p class="help">${help}</p>`:''}</section>`;}
function macPicker(key,title,items,desc=''){return `<label class="mac-form-row"><span><strong>${title}</strong>${desc?`<small>${desc}</small>`:''}</span><select data-picker="${key}" aria-label="${title}">${items.map(([v,t])=>`<option value="${v}" ${state[key]===v?'selected':''}>${t}</option>`).join('')}</select></label>`;}
function renderMacSettings(){
 let html=`<h2 class="sr-only">${macPageTitles[state.page]}</h2>`;
 if(state.page==='display')html+=`<p class="section-desc">메뉴 막대에는 필요한 숫자만.<br>한 번 클릭해 모든 한도와 초기화 시간을 확인하세요.</p>`+macGroup('메뉴 막대',macPicker('service','표시할 서비스',[['auto','자동 감지'],['claude','Claude'],['codex','Codex'],['both','모두']])+macPicker('menuMetric','표시할 한도',[['session','5시간'],['weekly','주간']]),'자동 감지는 연결된 서비스만 표시합니다. Fable과 초기화권은 상세 패널에서 확인할 수 있어요.')+`<div class="mac-info">${icon('details')}<p>바탕화면이나 Dock에 별도 위젯을 추가하지 않습니다. 상단의 서비스 아이콘과 사용률이 Dejavu입니다.</p></div>`;
 if(state.page==='appearance')html+=`<p class="section-desc">Mac의 모양을 그대로 따릅니다.<br>별도 테마 없이, 밝은 화면에서도 어두운 화면에서도 또렷하게.</p>`+macGroup('모양',macPicker('macAppearance','색상 모드',[['auto','시스템 설정'],['light','라이트'],['dark','다크']]),'시스템 설정을 선택하면 운영체제의 라이트·다크 모드에 맞춰 바뀝니다.')+`<div class="mac-info">${icon('appearance')}<p>유리 효과와 대비는 운영체제의 접근성 설정을 따르는 방향입니다. HTML 시안의 투명도 줄이기 체험은 ‘동작’에 있습니다.</p></div>`;
 if(state.page==='connections')html+=`<p class="section-desc">연결된 서비스와 제공되는 한도를 확인하세요.</p>`+macGroup('서비스',['claude','codex'].map(p=>`<div class="mac-form-row mac-provider-row"><span class="provider-template ${p}" aria-hidden="true"></span><span><strong>${p==='claude'?'Claude':'Codex'}</strong><small>${state[p]?'연결된 상태':'연결되지 않음'}</small></span><span class="mac-connection-state ${state[p]?'is-ready':''}">${state[p]?'연결됨':'연결 필요'}</span></div>`).join(''),'Fable은 계정과 연결 방식에 따라 제공되지 않을 수 있습니다.')+macGroup('연결 상태 체험',toggle('claude','Claude 연결','예시 사용량을 표시합니다.')+toggle('codex','Codex 연결','예시 사용량을 표시합니다.'),'이 스위치는 시뮬레이션입니다. 로그인하거나 인증 정보를 읽지 않습니다.');
 if(state.page==='behavior')html+=`<p class="section-desc">작업을 방해하지 않고, 필요한 순간에만 펼쳐집니다.</p>`+macGroup('일반',toggle('startup','로그인 시 시작','시안에서는 실제 시작 항목을 변경하지 않습니다.')+toggle('animations','상세 그래프 애니메이션','숫자는 즉시, 그래프는 짧고 부드럽게 표시합니다.'))+macGroup('접근성 체험',toggle('reducedMotion','동작 줄이기 미리보기','시스템의 동작 줄이기 설정이 항상 우선합니다.')+toggle('reducedTransparency','투명도 줄이기 미리보기','메뉴 막대와 조작 영역의 배경을 불투명하게 표시합니다.'),'실제 Mac 접근성 설정은 변경하지 않습니다.')+`<p class="help">패널 밖 클릭 · Esc · 메뉴 막대 다시 클릭으로 닫기<br>설정 열기: ⌘ ,</p>`;
 if(state.page==='updates')html+=`<p class="section-desc">버전 확인과 결과를 이 화면에서 바로 확인합니다.</p>`+macGroup('Dejavu',`<div class="mac-form-row"><span><strong>디자인 프로토타입</strong><small>실제 배포 버전이 아닙니다.</small></span><button id="check-update" class="secondary">업데이트 확인 체험</button></div><div id="update-status" class="mac-update-status" aria-live="polite"></div>`)+macGroup('알림',toggle('notify','새 버전 알림','새로운 버전이 있을 때 알려줍니다.'),'서버 요청, 파일 다운로드, 프로그램 업데이트는 수행하지 않습니다.');
 if(state.page==='privacy')html+=`<p class="section-desc">무엇을 읽고, 무엇을 보관하는지 분명하게.</p>`+macGroup('이 시안의 데이터',`<div class="mac-form-row"><span><strong>계정 접근 없음</strong><small>고정된 예시 사용량만 표시합니다. 대화, 비밀번호, 인증 정보는 읽지 않습니다.</small></span></div><div class="mac-form-row"><span><strong>페이지 안에서만 유지</strong><small>설정은 메모리에서만 유지됩니다. 새로고침하면 초기 상태로 돌아갑니다.</small></span></div>`);
 $('#settings').innerHTML=html;
 updateSettingsNavigation();
}
function updateSettingsNavigation(){
 document.querySelectorAll('nav [data-page]').forEach(b=>b.setAttribute('aria-current',b.dataset.page===state.page?'page':'false'));
 $('.sidebar nav [data-page="appearance"]').innerHTML=`<span>${icon('appearance')}</span>${inMenuBar()?'모양':'꾸미기'}`;
 $('#settings-window-title').textContent=inMenuBar()?macPageTitles[state.page]:'dejavu 설정';
 $('.sidebar-bottom small').textContent=inMenuBar()?'macOS 27 · HTML 시안':'Windows · macOS';
}
function renderSettings(){if(inMenuBar()){renderMacSettings();return;}let html='';
 if(state.page==='display')html=intro('01',inMenuBar()?'상단에서, 가볍게 확인':'필요한 만큼만, 표시',inMenuBar()?'메뉴 막대에는 핵심 숫자만. 자세한 내용은 클릭해서 확인하세요.':'연결된 서비스와 나에게 맞는 위젯 배치를 선택하세요.')+
 (inMenuBar()?'<div class="placement-note"><span>메뉴 막대 중심</span><p>바탕화면에 별도 위젯을 띄우지 않습니다.<br>서비스 아이콘과 사용량이 상단에 표시됩니다.</p></div>':`<div class="field-group"><span class="field-label">위젯 배치</span>${choices('placement',[['floating','바탕화면'],['taskbar','작업표시줄 안']])}<p class="help">${inTaskbar()?'작업표시줄 높이에 맞춰 한 줄로 고정합니다.':'바탕화면 위젯은 끌어서 위치를 바꿀 수 있어요.'}</p></div>`)+
 `<div class="field-group"><span class="field-label">표시할 서비스</span>${choices('service',[['auto','자동 감지'],['claude','Claude'],['codex','Codex'],['both','모두']])}<p class="help">자동 감지는 연결된 서비스만 표시합니다.</p></div>`+
 (inMenuBar()?`<div class="field-group"><span class="field-label">메뉴 막대에 표시할 한도</span>${choices('menuMetric',[['session','5시간'],['weekly','주간']])}<p class="help">선택한 한도의 사용률을 각 서비스 옆에 표시합니다.<br>Fable과 다른 한도는 상세 패널에서 확인할 수 있어요.</p></div>`:inTaskbar()?'<div class="placement-note"><span>작업표시줄 전용 크기</span><p>Claude와 Codex를 한 줄로 표시합니다.<br>크기와 두 줄 설정은 바탕화면 배치에서 사용할 수 있어요.</p></div>':`<div class="field-group"><span class="field-label">위젯 크기</span><div class="choice-grid">${[['small','작음','숫자와 링'],['medium','중간','간결한 막대'],['large','큼','더 편한 가독성']].map(([v,t,d])=>`<button class="choice" data-setting="density" data-value="${v}" aria-pressed="${state.density===v}"><span>${t}</span><small>${d}</small></button>`).join('')}</div></div>`+toggle('rows','서비스별 두 줄 표시','두 서비스가 표시될 때만 두 줄로 나눕니다.'))+
 (inMenuBar()?'':toggle('progress','사용량 그래프','숫자는 그래프를 꺼도 항상 표시합니다.'))+
 `<div class="inline-note">${inMenuBar()?'메뉴 막대의 사용량을 한 번 클릭하면 상세 패널이 열립니다.<br>초기화 시간과 초기화권을 보고, 새로고침과 설정도 바로 이용하세요.':inTaskbar()?'작업표시줄의 사용량을 누르면 상세 정보가 열립니다.':'트레이에서 언제든 상세 사용량을 열 수 있어요.<br>위젯을 누르면 상세 정보를, 끌면 위치를 바꿉니다.'}</div>`;
 if(state.page==='appearance')html=intro('02','숫자는 같아도, 느낌은 다르게',inMenuBar()?'메뉴 막대는 단색 그대로. 설정과 상세 패널의 테마를 골라보세요.':'위젯·설정·상세창에 같은 디자인 언어를 적용합니다.')+`<div class="field-group"><span class="field-label">테마</span><div class="theme-picker">${Object.entries(DejavuThemes).map(([id,t])=>`<button class="theme-choice" data-setting="visual" data-value="${id}" data-visual="${id}" aria-pressed="${state.visual===id}"><span class="theme-swatch" aria-hidden="true"></span><span><strong>${t.name}</strong><small>${t.preserved?'Paper Ink · 기존안 유지':t.old+'의 새 방향'}</small></span></button>`).join('')}</div><p class="orbit-preserved">Orbit과 Field Notes는 기존안의 느낌을 유지합니다. 나머지 네 테마만 개편합니다.</p></div><div class="field-group"><span class="field-label">색상 모드</span><div class="segmented"><button data-appearance="dark" aria-pressed="${document.documentElement.dataset.theme==='dark'}">다크</button><button data-appearance="light" aria-pressed="${document.documentElement.dataset.theme==='light'}">라이트</button></div></div><label class="slider-label" for="opacity"><span>배경 불투명도</span><output id="opacity-value">${state.opacity}%</output></label><input type="range" id="opacity" min="15" max="100" value="${state.opacity}"><p class="help">값이 낮을수록 배경이 투명해집니다.<br>글자와 그래프에는 투명도를 적용하지 않습니다.</p><div class="inline-note">형태·글자·그래프가 함께 바뀝니다.<br>작업표시줄은 운영체제에 맞춘 중립적인 표현을 유지합니다.</div>`;
 if(state.page==='connections')html=intro('03','연결은 쉽게, 상태는 분명하게','아래 스위치는 연결 상태를 시험하기 위한 시뮬레이션입니다.')+['claude','codex'].map(p=>`<section class="provider-card"><header><strong>${p==='claude'?'Claude':'Codex'}</strong><span class="pill">${state[p]?'연결된 상태':'연결되지 않음'}</span></header><p>${p==='claude'?'Fable은 계정과 연결 방식에 따라 제공되지 않을 수 있어요.':'이용 중인 계정에서 제공되는 한도를 표시해요.'}</p>${toggle(p,'연결된 상태로 보기','실제 로그인이나 인증 정보에는 접근하지 않습니다.')}</section>`).join('')+`<p class="help">자동 감지에서는 미연결 서비스를 숨깁니다.<br>서비스를 직접 선택했다면 ‘연결 필요’로 안내합니다.</p>`;
 if(state.page==='behavior')html=intro('04','작업 흐름에 맞추기','자주 바꾸지 않는 동작은 한곳에 모았습니다.')+toggle('topmost','항상 위에 표시','실제 창 순서가 아닌 설정 UX를 보여주는 시안입니다.')+toggle('startup',state.os==='windows'?'Windows 로그인 시 시작':'Mac 로그인 시 시작','이 시안은 운영체제의 시작 항목을 변경하지 않습니다.')+`<div class="inline-note">위젯 클릭과 드래그를 구분합니다.<br>크기와 줄 수를 바꿔도 현재 위치를 유지하고, 화면 밖으로 나갈 때만 안쪽으로 조정합니다.</div>`;
 if(state.page==='updates')html=intro('05','새로운 변화, 놓치지 않게','확인은 이 화면에서. 작업을 가리는 새 창 없이.')+`<section class="provider-card"><header><strong>Dejavu</strong><span class="pill">디자인 시안</span></header><p>업데이트 확인의 로딩·결과 표시를 체험할 수 있습니다.</p><button id="check-update" class="secondary">업데이트 확인 체험</button><p id="update-status" aria-live="polite"></p></section>`+toggle('notify','새 버전 알림','새로운 버전이 있을 때 알림을 표시합니다.')+`<div class="inline-note">실제 서버 요청, 파일 다운로드, 프로그램 업데이트는 수행하지 않습니다.</div>`;
 if(state.page==='privacy')html=intro('06','내 데이터는, 내 PC에','어떤 정보를 사용하는지 알 수 있도록 명확하게 안내합니다.')+`<section class="provider-card"><strong>이 시안은 계정에 접근하지 않아요</strong><p>모든 사용량은 고정된 예시 데이터입니다. 대화 내용, 비밀번호, 인증 정보는 읽지 않습니다.</p></section><section class="provider-card"><strong>설정도 이 페이지 안에서만</strong><p>변경값은 메모리에서만 유지됩니다. 페이지를 새로고침하면 처음 상태로 돌아갑니다.</p></section>`;
 if(state.page==='behavior')html+=toggle('animations','상세 그래프 애니메이션','패널을 열 때만 짧게 채워집니다. 숫자는 바로 표시합니다.')+toggle('reducedMotion','동작 줄이기 미리보기','시스템 설정이 켜져 있으면 이 옵션과 관계없이 동작을 줄입니다.');
 $('#settings').innerHTML=html;updateSettingsNavigation();
 if(state.page==='appearance'&&inTaskbar()){$('#opacity').disabled=true;$('#opacity').nextElementSibling.textContent='작업표시줄 배치에서는 작업표시줄 배경을 사용합니다. 배경 불투명도는 바탕화면 위젯에 적용됩니다.';}
}
function metricMarkup(p,m){
 const value=ready(p)?m[2]:null;
 const label=inTaskbar()?(p==='claude'?(m===metrics[p][0]?'5H':m[0]):m===metrics[p][0]?'5시간':'Codex'):state.density==='small'&&m===metrics[p][0]?(p==='claude'?'C · 5H':'O · 5H'):m[0];
 const useRing=!inTaskbar()&&state.density==='small'&&state.progress&&['modern','glass'].includes(state.visual);
 const graph=inTaskbar()?`<span class="wm-bar"><i style="width:${value??0}%"></i></span>`:DejavuProgress(value,state.visual);
 const content=useRing?`<span class="ring"><svg viewBox="0 0 36 36" aria-hidden="true"><circle cx="18" cy="18" r="15.5"/><circle class="arc" cx="18" cy="18" r="15.5" pathLength="100" style="stroke-dashoffset:${100-(value??0)}" ${value===null?'visibility="hidden"':''}/></svg><span class="wm-value">${value===null?'--':value}%</span></span>`:`<span class="wm-value">${value===null?'--':value}%</span>${state.progress?graph:''}`;
 return `<span class="wm"><span class="wm-label">${label}</span>${content}</span>`;
}
function clampPosition(){if(inTaskbar()||inMenuBar())return;const a=$('#widget-anchor'),d=$('#desktop'),w=$('#widget');const pad=16;const bottomGap=64;if(!state.customPosition){state.x=d.clientWidth-w.offsetWidth-pad;state.y=d.clientHeight-w.offsetHeight-bottomGap;}state.x=Math.max(pad,Math.min(state.x,d.clientWidth-w.offsetWidth-pad));state.y=Math.max(pad,Math.min(state.y,d.clientHeight-w.offsetHeight-bottomGap));a.style.left=state.x+'px';a.style.top=state.y+'px';}
function renderContext(){
 const mac=inMenuBar(),list=services(),menu=$('#menu-open');
 $('#preview-platform').textContent=mac?'macOS 27 · 메뉴 막대':'Windows 11 · 화면 오른쪽';
 $('#expanded-title').textContent=mac?'macOS 27 메뉴 막대 미리보기':'Windows 11 화면 미리보기';
 $('#context-window-title').textContent=mac?'프로젝트':'파일 탐색기';
 menu.innerHTML=list.length?list.map(p=>`<span class="menu-provider"><span class="provider-template ${p}" aria-hidden="true"></span><span>${ready(p)?menuMetric(p)[2]+'%':'--%'}</span></span>`).join(''):'<span class="menu-brand-template" aria-hidden="true"></span><span>연결 필요</span>';
 const summary=list.length?list.map(p=>`${p==='claude'?'Claude':'Codex'} ${menuMetric(p)[1]} ${ready(p)?menuMetric(p)[2]+'%':'연결 필요'}`).join(', '):'연결된 서비스 없음';
 menu.title=summary;menu.setAttribute('aria-label',summary+' · 상세 패널 열기');menu.setAttribute('aria-haspopup','dialog');menu.setAttribute('aria-expanded',String(mac&&$('#details').open));
 $('#preview-hint').textContent=mac?'상단의 아이콘과 숫자가 Dejavu입니다. 클릭하면 바로 아래에 상세 패널이 열립니다.':inTaskbar()?'사용량은 시스템 트레이 바로 왼쪽에 표시됩니다. 누르면 위쪽에 상세창이 열립니다.':'트레이 아이콘에서 Dejavu 메뉴를 열 수 있습니다. 위젯은 끌어서 이동합니다.';
 $('#show-details').innerHTML=`<span>${mac?'메뉴 막대 패널 살펴보기':'상세 사용량 살펴보기'}</span>${icon('details')}`;
 $('.intro-note p').textContent=mac?'메뉴 막대 / 상세 패널 / 설정':'상시 위젯 / 상세 사용량 / 설정';
 $('.screen-dialog-header span').textContent=mac?'상단의 사용량을 누르면 상세 패널이 열립니다.':'위젯을 누르면 상세 정보를 확인할 수 있어요.';
 $('#panel-settings').hidden=!mac;
 const actions=$('#details .panel-actions'),actionHost=mac?$('#detail-toolbar-actions'):$('#details .detail-footer');
 if(actions.parentElement!==actionHost)actionHost.appendChild(actions);
 $('#detail-heading').textContent=mac?'사용량':'지금, 얼마나 썼을까?';
 if(mac){
  $('#dimensions').textContent=`${Math.round(menu.offsetWidth)} × 28 · 메뉴 막대 · ${list.length}개 서비스`;
  const sceneRect=desktop.getBoundingClientRect(),menuRect=menu.getBoundingClientRect();
  const visibleWidth=Math.min(desktop.clientWidth,desktop.parentElement.clientWidth),panelWidth=Math.min(420,visibleWidth-24);
  desktop.style.setProperty('--menu-panel-width',panelWidth+'px');
  desktop.style.setProperty('--menu-panel-right',Math.max(12,Math.min(sceneRect.right-menuRect.right,visibleWidth-panelWidth-12))+'px');
 }
}
function renderWidget(){
 const list=services(),w=$('#widget'),docked=inTaskbar();
 const split=!docked&&state.rows&&list.length===2;
 const displayList=split?[...list].reverse():list;
 const showGraph=state.progress&&list.length>0;
 const host=docked?taskbarHost:$('#widget-anchor');
 if(w.parentElement!==host)host.appendChild(w);
 $('#widget-anchor').hidden=docked||inMenuBar();
 taskbar.classList.toggle('taskbar-embedded',docked);
 w.className=`widget product-surface ${docked?'taskbar-widget':state.density} ${split?'two-row':''} ${showGraph?'':'no-progress'}`;
 applyVisual();
 w.style.backgroundColor=docked?'transparent':`rgba(var(--widget-bg),${state.opacity/100})`;
 w.innerHTML=list.length?displayList.map(p=>`<span class="widget-group ${p}">${metrics[p].map(m=>metricMarkup(p,m)).join('')}</span>`).join(''):docked?'<span class="wm"><span class="wm-label">dejavu</span><span class="wm-value">--%</span></span>':'<span class="widget-empty">서비스를 연결해 주세요</span>';
 w.setAttribute('aria-label',list.length?list.map(p=>`${p} ${ready(p)?metrics[p].map(m=>m[1]+' '+m[2]+'%').join(', '):'연결 필요'}`).join('; ')+' · 상세 사용량 열기':'서비스 연결 안내 열기');
 clampPosition();
 // On a short specimen canvas, prioritize a readable scrollable panel.
 const panelFitsAbove=desktop.clientHeight>=w.offsetHeight+396;
 desktop.style.setProperty('--details-bottom',docked||inMenuBar()||!panelFitsAbove?'58px':Math.round(w.offsetHeight+76)+'px');
 $('#dimensions').textContent=`${Math.round(w.offsetWidth)} × ${Math.round(w.offsetHeight)} · ${docked?'작업표시줄 고정 배치':list.length+'개 서비스'}`;
 $('#reset-position').hidden=docked||inMenuBar();
 renderContext();
 if($('#details').open)renderDetails();
}
let detailsMarkup='';
function detailGraph(value){return inMenuBar()?`<span class="usage-graph graph-native" data-value="${value}" style="--usage:${value}%" aria-hidden="true"><span class="graph-track"><span class="graph-fill"></span></span></span>`:DejavuProgress(value,state.visual);}
function renderDetails(){const list=services(),html=list.length?list.map(p=>`<section class="detail-provider ${p}"><h3><strong>${p==='claude'?'Claude':'Codex'}</strong><span>${ready(p)?'예시 · 최신 상태':'연결 필요'}</span></h3>${ready(p)?metrics[p].map(m=>`<div class="detail-metric"><div><span>${m[1]}</span><b>${m[2]}%</b></div>${inMenuBar()||state.progress?`<div role="progressbar" aria-label="${p} ${m[1]}" aria-valuenow="${m[2]}" aria-valuemin="0" aria-valuemax="100">${detailGraph(m[2])}</div>`:''}<small>${m[3]}</small></div>`).join(''):'<p class="help">연결한 계정의 사용량을 이곳에서 볼 수 있어요.</p><button class="secondary" data-connect>연결 설정 보기</button>'}${p==='codex'&&ready(p)?'<div class="credits"><div>Codex 초기화권<small>가장 빠른 만료 · 10월 14일 10:14</small></div><strong>2개</strong></div>':''}</section>`).join(''):'<section class="provider-card"><h3>아직 연결된 서비스가 없어요</h3><p>연결 설정에서 서비스를 선택해 주세요.</p><button class="secondary" data-connect>연결 설정 보기</button></section>';if(html!==detailsMarkup){DejavuMotion.cancel();$('#details-body').innerHTML=html;detailsMarkup=html;}}
function openDetails(){closeNativeMenu();const panel=$('#details'),opening=!panel.open;renderDetails();if(opening)panel.show();renderContext();if(opening){DejavuMotion.open(panel);panel.focus({preventScroll:true});}}
function closeDetails(){$('#details').close();renderContext();}
function closeNativeMenu(){$('#menu-popover').hidden=true;$('#menu-open').setAttribute('aria-expanded',String(inMenuBar()&&$('#details').open));$('#tray-open').setAttribute('aria-expanded','false');}
function openNativeMenu(){const popover=$('#menu-popover');if(!popover.hidden){closeNativeMenu();return;}$('#details').close();popover.innerHTML=services().map(p=>`<div class="menu-summary">${p==='claude'?'Claude':'Codex'} · ${ready(p)?metrics[p].map(m=>m[1]+' '+m[2]+'%').join(' / '):'연결 필요'}</div>`).join('')+`<hr><button data-native-action="details">상세 사용량</button><button data-native-action="refresh">지금 새로고침</button><button data-native-action="settings">설정… ${state.os==='mac'?'<small>⌘ ,</small>':''}</button>`;popover.hidden=false;$('#menu-open').setAttribute('aria-expanded','true');$('#tray-open').setAttribute('aria-expanded','true');}
function changed(){DejavuMotion.sync(state);applyAppearance();renderWidget();$('#announcement').textContent='미리보기에 변경사항을 적용했습니다.';}
function applyAppearance(){const value=inMenuBar()?(state.macAppearance==='auto'?(systemAppearance.matches?'dark':'light'):state.macAppearance):state.windowsAppearance;document.documentElement.dataset.theme=value;$('#theme').innerHTML=actionLabel(value==='dark'?'sun':'moon',value==='dark'?'라이트 모드':'다크 모드');}
function theme(value){if(inMenuBar())state.macAppearance=value;else state.windowsAppearance=value;applyAppearance();if(state.page==='appearance')renderSettings();renderWidget();}
systemAppearance.addEventListener('change',()=>{if(inMenuBar()&&state.macAppearance==='auto'){applyAppearance();renderWidget();}});

document.addEventListener('click',e=>{const trial=e.target.closest('[data-theme-try]');if(!trial)return;state.visual=trial.dataset.themeTry;state.page='appearance';if(state.os==='windows')state.placement='floating';renderSettings();changed();$('.workspace').scrollIntoView({block:'start',behavior:scrollBehavior()});});
document.addEventListener('click',e=>{const page=e.target.closest('[data-page]');if(page){state.page=page.dataset.page;renderSettings();}const setting=e.target.closest('[data-setting]');if(setting){state[setting.dataset.setting]=setting.dataset.value;renderSettings();changed();}const appearance=e.target.closest('[data-appearance]');if(appearance)theme(appearance.dataset.appearance);if(e.target.closest('[data-connect]')){$('#details').close();state.page='connections';renderSettings();}if(e.target.closest('#check-update')){const b=$('#check-update');b.disabled=true;b.textContent='확인 중…';$('#update-status').textContent='업데이트 확인 동작을 재현하고 있습니다.';setTimeout(()=>{if($('#check-update')){$('#check-update').disabled=false;$('#check-update').textContent='다시 확인';$('#update-status').textContent='체험 완료 · 실제 업데이트 서버에는 연결하지 않았습니다.';}},1000);}});
document.addEventListener('change',e=>{if(e.target.matches('[data-picker]')){state[e.target.dataset.picker]=e.target.value;changed();}if(e.target.matches('[data-toggle]')){state[e.target.dataset.toggle]=e.target.checked;if(state.page==='connections')renderSettings();changed();}});
document.addEventListener('input',e=>{if(e.target.id==='opacity'){state.opacity=Number(e.target.value);$('#opacity-value').value=state.opacity+'%';changed();}});
$('#platform').addEventListener('click',e=>{const b=e.target.closest('button');if(!b)return;closeNativeMenu();$('#details').close();state.os=b.dataset.value;document.body.dataset.os=state.os;applyAppearance();$('#platform').querySelectorAll('button').forEach(n=>n.setAttribute('aria-pressed',n===b));renderSettings();renderWidget();});
$('#theme').onclick=()=>theme(document.documentElement.dataset.theme==='dark'?'light':'dark');
$('#show-details').onclick=openDetails;$('#tray-open').onclick=openNativeMenu;$('#menu-open').onclick=()=>inMenuBar()?($('#details').open?closeDetails():openDetails()):openNativeMenu();$('#close-details').onclick=closeDetails;
$('#panel-settings').onclick=()=>{closeDetails();$('#screen-dialog').close();$('#settings').scrollIntoView({block:'center',behavior:scrollBehavior()});};
document.addEventListener('click',e=>{const insidePanel=e.composedPath().some(node=>node instanceof Element&&node.matches('#details,#menu-open,#show-details'));if(inMenuBar()&&$('#details').open&&!insidePanel)closeDetails();});
$('#details').addEventListener('close',()=>{DejavuMotion.cancel();if(inMenuBar())$('#menu-open').setAttribute('aria-expanded','false');});
document.addEventListener('click',e=>{const action=e.target.closest('[data-native-action]');if(action){if(action.dataset.nativeAction==='details')openDetails();if(action.dataset.nativeAction==='settings'){closeNativeMenu();$('#screen-dialog').close();$('#settings').scrollIntoView({block:'center',behavior:scrollBehavior()});}if(action.dataset.nativeAction==='refresh'){closeNativeMenu();$('#announcement').textContent='예시 사용량을 새로 확인했습니다.';}return;}if(!e.target.closest('#menu-popover,#tray-open,#menu-open'))closeNativeMenu();});
document.addEventListener('keydown',e=>{if(inMenuBar()&&e.metaKey&&e.key===','){e.preventDefault();closeDetails();$('#screen-dialog').close();$('#settings').scrollIntoView({block:'center',behavior:DejavuMotion.reduced()?'auto':'smooth'});return;}if(e.key!=='Escape')return;if(!$('#menu-popover').hidden){closeNativeMenu();e.preventDefault();}else if($('#details').open){closeDetails();if(inMenuBar())$('#menu-open').focus({preventScroll:true});e.preventDefault();}});
$('#expand-preview').onclick=()=>{closeNativeMenu();$('#details').close();$('#expanded-screen').appendChild(desktop);$('#screen-dialog').showModal();renderWidget();$('#expanded-screen').scrollLeft=$('#expanded-screen').scrollWidth;};
$('#close-preview').onclick=()=>$('#screen-dialog').close();
$('#screen-dialog').addEventListener('close',()=>{$('#details').close();closeNativeMenu();screenViewport.appendChild(desktop);renderWidget();screenViewport.scrollLeft=screenViewport.scrollWidth;});
$('#details').addEventListener('click',e=>{const r=$('#details').getBoundingClientRect();if(e.target===$('#details')&&(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom))$('#details').close();});
$('#refresh').onclick=()=>{const b=$('#refresh');b.disabled=true;b.innerHTML=actionLabel('refresh','확인 중…');setTimeout(()=>{b.disabled=false;b.innerHTML=actionLabel('refresh','새로고침');$('#freshness').textContent='시연 완료 · 예시 데이터는 그대로입니다.';},800);};
$('#reset-position').onclick=()=>{state.customPosition=false;renderWidget();};
let drag=null,suppressClick=false;
$('#widget').addEventListener('pointerdown',e=>{suppressClick=false;if(inTaskbar()||e.button!==0)return;drag={id:e.pointerId,startX:e.clientX,startY:e.clientY,x:state.x,y:state.y,moved:false};$('#widget').setPointerCapture(e.pointerId);});
$('#widget').addEventListener('pointermove',e=>{if(!drag||drag.id!==e.pointerId)return;const dx=e.clientX-drag.startX,dy=e.clientY-drag.startY;if(Math.hypot(dx,dy)>5)drag.moved=true;if(drag.moved){state.customPosition=true;state.x=drag.x+dx;state.y=drag.y+dy;clampPosition();}});
$('#widget').addEventListener('pointerup',()=>{suppressClick=!!drag?.moved;drag=null;});
$('#widget').addEventListener('pointercancel',()=>{drag=null;suppressClick=true;});
$('#widget').addEventListener('click',e=>{if(suppressClick&&e.detail!==0){suppressClick=false;return;}openDetails();});
// The viewport can resize without changing the logical-size desktop. Re-anchor
// its visible right edge too, so a platform switch never clips menu-bar items.
const previewResizeObserver=new ResizeObserver(()=>{renderWidget();if(!$('#screen-dialog').open)screenViewport.scrollLeft=screenViewport.scrollWidth;});
previewResizeObserver.observe(desktop);
previewResizeObserver.observe(screenViewport);
$('#tray-open').innerHTML='<span class="brand-template" aria-hidden="true"></span>';
document.body.dataset.os=state.os;DejavuMotion.sync(state);applyAppearance();renderThemeLab();renderSettings();renderWidget();
screenViewport.scrollLeft=screenViewport.scrollWidth;
