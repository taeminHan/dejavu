'use strict';
// Original code-native vectors. One registry for the prototype and its icon reference.
const DejavuIcons=Object.freeze({
 paths:Object.freeze({
  display:'<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M9 21h6M12 17v4"/>',
  appearance:'<path d="M12 3a9 9 0 1 0 0 18h1a2 2 0 0 0 1.6-3.2 1.5 1.5 0 0 1 1.2-2.4H18a3 3 0 0 0 3-3A9 9 0 0 0 12 3Z"/><circle cx="7.5" cy="11" r=".8" fill="currentColor" stroke="none"/><circle cx="10" cy="7.5" r=".8" fill="currentColor" stroke="none"/><circle cx="14.5" cy="7.5" r=".8" fill="currentColor" stroke="none"/><circle cx="17" cy="11" r=".8" fill="currentColor" stroke="none"/>',
  connections:'<path d="m10 14 4-4M8.5 15.5l-1 1a3.5 3.5 0 0 1-5-5l4-4a3.5 3.5 0 0 1 5 0M15.5 8.5l1-1a3.5 3.5 0 0 1 5 5l-4 4a3.5 3.5 0 0 1-5 0"/>',
  behavior:'<path d="M4 7h4m4 0h8M4 17h8m4 0h4"/><circle cx="10" cy="7" r="2"/><circle cx="14" cy="17" r="2"/>',
  updates:'<circle cx="12" cy="12" r="9"/><path d="M12 16V8m-4 4 4-4 4 4"/>',
  privacy:'<path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6l8-3Z"/><path d="m8.5 12 2.5 2.5 4.5-5"/>',
  settings:'<path d="m9 3-.5 2.5-2 1.2L4 6l-2 3.5 2 1.8v2.4l-2 1.8L4 19l2.5-.7 2 1.2L9 22h6l.5-2.5 2-1.2 2.5.7 2-3.5-2-1.8v-2.4l2-1.8L20 6l-2.5.7-2-1.2L15 3H9Z" transform="translate(1 .5) scale(.92)"/><circle cx="12" cy="12" r="3"/>',
  refresh:'<path d="M20 8a8.5 8.5 0 0 0-14-3L3 8m0-5v5h5M4 16a8.5 8.5 0 0 0 14 3l3-3m0 5v-5h-5"/>',
  details:'<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M8 9h8M8 13h8M8 17h4"/>',
  expand:'<path d="M9 3H3v6M15 3h6v6M3 15v6h6M21 15v6h-6"/>',
  close:'<path d="m6 6 12 12M18 6 6 18"/>',
  sun:'<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M19 5l-1.5 1.5m-11 11L5 19"/>',
  moon:'<path d="M20.5 14A9 9 0 0 1 10 3.5 9 9 0 1 0 20.5 14Z"/>'
 }),
 svg(name){
  const path=this.paths[name];
  if(!path)throw new Error('Unknown Dejavu icon: '+name);
  return `<svg class="ui-icon" data-icon-name="${name}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${path}</svg>`;
 },
 paint(root=document){root.querySelectorAll('[data-icon]').forEach(node=>{node.innerHTML=this.svg(node.dataset.icon);});}
});
DejavuIcons.paint();
