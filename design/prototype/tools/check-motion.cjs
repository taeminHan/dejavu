const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const media=new Map(),calls=[],body={dataset:{}};
const sandbox={window:{},document:{body},matchMedia(query){const item={matches:false,addEventListener(_,fn){this.change=fn;}};media.set(query,item);return item;},getComputedStyle(node){return {clipPath:node.clip||'none'};}};
vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../motion.js'),'utf8'),sandbox);
function node(clip){return {clip,animate(frames,options){const animation={frames,options,cancelled:false,cancel(){this.cancelled=true;},finished:new Promise(()=>{})};calls.push(animation);return animation;}};}
function graph(value,clip){const fill=node(clip);return {dataset:{value:String(value)},querySelector(){return fill;}};}
const panel=node();panel.querySelectorAll=()=>[graph(0),graph('unknown'),graph(8),graph(24,'inset(0 76% 0 0)'),graph(100)];
const motion=sandbox.window.DejavuMotion;
motion.sync({animations:true});motion.open(panel);
assert.equal(calls.length,4,'shell and three positive graphs only');
assert.equal(calls[0].options.duration,180);
assert.equal(calls[1].options.duration,420);
assert.equal(calls[1].frames[1].clipPath,'inset(0 0% 0 0)');
assert.equal(calls[2].frames[1].clipPath,'inset(0 76% 0 0)','pencil retains its true target clipping');
assert.equal(calls[3].options.delay,48);
motion.sync({reducedMotion:true});assert(calls.every(a=>a.cancelled));
motion.open(panel);assert.equal(calls.length,4,'reduced motion must not animate');
motion.sync({reducedMotion:false,animations:false});motion.open(panel);assert.equal(calls.length,4);
motion.sync({animations:true});media.get('(prefers-reduced-motion: reduce)').matches=true;media.get('(prefers-reduced-motion: reduce)').change();motion.open(panel);assert.equal(calls.length,4,'system preference wins');
assert.equal(body.dataset.reduceMotion,'true');
motion.sync({reducedTransparency:true});assert.equal(body.dataset.reduceTransparency,'true');
media.get('(prefers-reduced-motion: reduce)').matches=false;media.get('(prefers-reduced-motion: reduce)').change();motion.open(panel);assert.equal(calls.length,8);
motion.cancel();assert(calls.every(a=>a.cancelled));
console.log('Motion: reveal targets, zero/unknown skip, cancel, re-open, system/preview/off preferences passed');
