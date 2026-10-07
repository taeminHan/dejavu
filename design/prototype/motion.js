'use strict';
// Animate presentation only: text and accessibility values always show the real target.
window.DejavuMotion=(()=>{
 const systemMotion=matchMedia('(prefers-reduced-motion: reduce)');
 const systemTransparency=matchMedia('(prefers-reduced-transparency: reduce)');
 let preferences={animations:true,reducedMotion:false,reducedTransparency:false};
 const active=new Set();
 const reduced=()=>systemMotion.matches||preferences.reducedMotion||!preferences.animations;
 function cancel(){for(const animation of active)animation.cancel();active.clear();}
 function sync(next){preferences={...preferences,...next};document.body.dataset.reduceMotion=String(reduced());document.body.dataset.reduceTransparency=String(systemTransparency.matches||preferences.reducedTransparency);if(reduced())cancel();}
 function play(node,frames,options){const animation=node.animate(frames,options);active.add(animation);animation.finished.then(()=>active.delete(animation),()=>active.delete(animation));}
 function open(panel){
  cancel();if(reduced())return;
  play(panel,[{opacity:0,transform:'translateY(4px)'},{opacity:1,transform:'translateY(0)'}],{duration:180,easing:'ease-out'});
  let index=0;
  for(const graph of panel.querySelectorAll('.usage-graph')){
   if(!(Number(graph.dataset.value)>0))continue;
   const fill=graph.querySelector('.graph-fill,.pencil-fill');if(!fill)continue;
   const target=getComputedStyle(fill).clipPath;
   play(fill,[{clipPath:'inset(0 100% 0 0)'},{clipPath:target==='none'?'inset(0 0% 0 0)':target}],{duration:420,delay:Math.min(index++*24,120),easing:'cubic-bezier(.2,.7,.2,1)',fill:'backwards'});
  }
 }
 systemMotion.addEventListener('change',()=>sync(preferences));
 systemTransparency.addEventListener('change',()=>sync(preferences));
 return Object.freeze({open,cancel,sync,reduced});
})();
