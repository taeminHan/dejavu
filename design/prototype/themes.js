'use strict';
window.DejavuThemes = Object.freeze({
 modern:{name:'Studio',old:'Modern',tag:'01 / INSTRUMENT',desc:'정갈한 계기판. 숫자는 크게, 정보는 질서 있게.',shape:'분할 패널 · 눈금 막대 · 절제된 타이포'},
 retro:{name:'Arcade',old:'Retro Night',tag:'02 / PIXEL HUD',desc:'게임 HUD처럼. 픽셀 프레임과 도트 게이지.',shape:'계단형 모서리 · 픽셀 칸 · 고정폭 숫자'},
 glass:{name:'Prism',old:'Fluent Glass',tag:'03 / TRANSLUCENT',desc:'겹쳐진 유리 패널. 밝고 또렷한 숫자.',shape:'라운드 캡슐 · 빛나는 경계 · 겹친 깊이'},
 terminal:{name:'Console',old:'Terminal Mono',tag:'04 / COMMAND LINE',desc:'명령줄의 사용량. 괄호와 블록으로 바로 읽기.',shape:'각진 창 · 고정폭 타이포 · 터미널 막대'},
 paper:{name:'Field Notes',old:'Paper Ink',preserved:true,tag:'05 / ORIGINAL PAPER',desc:'기존 Paper Ink의 손글씨와 색연필 느낌 그대로.',shape:'기존안 유지 · 손글씨 · 구불구불한 색연필'}
});
window.DejavuProgress = function(value,visual,extra='') {
 const known=Number.isFinite(value),v=known?Math.max(0,Math.min(100,value)):0;
 const attrs=`class="usage-graph graph-${visual} ${extra}" data-value="${known?v:'unknown'}" aria-hidden="true" style="--usage:${v}%"`;
 if(visual==='terminal')return `<span ${attrs}><span class="graph-bracket">[</span><span class="graph-track"><span class="terminal-empty">░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░</span><span class="graph-fill"><span>████████████████████████████████████████████████████████████████████████████████</span></span></span><span class="graph-bracket">]</span></span>`;
 if(visual==='paper')return `<span ${attrs}><svg viewBox="0 0 200 12" preserveAspectRatio="none"><path class="pencil-track" d="M2 6Q20 1 40 6T80 6T120 6T160 6T198 6"/><g class="pencil-fill" style="clip-path:inset(0 ${100-v}% 0 0)"><path d="M2 5Q20 0 40 5T80 5T120 5T160 5T198 5"/><path d="M2 8Q20 3 40 8T80 8T120 8T160 8T198 8"/><path d="M2 3Q20 8 40 3T80 3T120 3T160 3T198 3"/></g></svg></span>`;
 return `<span ${attrs}><span class="graph-track"><span class="graph-fill"></span></span></span>`;
};
