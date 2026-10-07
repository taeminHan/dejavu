// Dependency-free TrueType compiler for Dejavu's original square-pixel alphabet.
// Input is the bitmap registry in RetroPixelVisuals.cs; output is a generated font asset.
const fs = require('node:fs');
const path = require('node:path');
const repo = process.argv[2];
if (!repo) throw new Error('Usage: node tools/BuildPixelFont.cjs <repo>');
const source = fs.readFileSync(path.join(repo, 'RetroPixelVisuals.cs'), 'utf8');
const alphabet = new Map([...source.matchAll(/\['(.)'\]\s*=\s*"([01/]+)"/g)].map(m => [m[1], m[2]]));
if (alphabet.size !== 44) throw new Error(`Unexpected bitmap registry: ${alphabet.size}`);
for (const [ch, pattern] of [...alphabet]) {
  if (ch >= 'A' && ch <= 'Z') alphabet.set(ch.toLowerCase(), pattern);
}
const chars = [...alphabet.keys()].sort((a, b) => a.charCodeAt(0) - b.charCodeAt(0));
const u16 = n => {const b=Buffer.alloc(2);b.writeUInt16BE(n);return b;};
const s16 = n => {const b=Buffer.alloc(2);b.writeInt16BE(n);return b;};
const u32 = n => {const b=Buffer.alloc(4);b.writeUInt32BE(n >>> 0);return b;};
const concat = (...a) => Buffer.concat(a.flat());
const pad = b => concat(b, Buffer.alloc((4 - b.length % 4) % 4));
function glyph(pattern) {
  const points=[],ends=[];
  const rows=pattern.split('/');
  for (let y=0;y<7;y++) for(let x=0;x<5;x++) if(rows[y][x]==='1') {
    const px=x*100,py=(6-y)*100;
    // Clockwise contours, all on-curve, unhinted integer square outlines.
    points.push([px,py],[px,py+100],[px+100,py+100],[px+100,py]);ends.push(points.length-1);
  }
  if (!points.length) return Buffer.alloc(0);
  const flags=Buffer.alloc(points.length,1);let lastX=0,lastY=0;
  const xs=[],ys=[];
  for(const [x,y] of points){xs.push(s16(x-lastX));ys.push(s16(y-lastY));lastX=x;lastY=y;}
  return pad(concat(s16(ends.length),s16(0),s16(0),s16(500),s16(700),ends.map(u16),u16(0),flags,xs,ys));
}
const glyphs=[glyph('11111/10001/10101/10101/10101/10001/11111'),...chars.map(ch=>glyph(alphabet.get(ch)))];
const count=glyphs.length,offsets=[0];for(const g of glyphs)offsets.push(offsets.at(-1)+g.length);
const glyf=concat(glyphs),loca=concat(offsets.map(u32));
const head=Buffer.alloc(54);head.writeUInt32BE(0x10000,0);head.writeUInt32BE(0x10000,4);
head.writeUInt32BE(0x5f0f3cf5,12);head.writeUInt16BE(3,16);head.writeUInt16BE(1000,18);
head.writeInt16BE(0,36);head.writeInt16BE(0,38);head.writeInt16BE(500,40);head.writeInt16BE(700,42);
head.writeUInt16BE(8,46);head.writeInt16BE(2,48);head.writeInt16BE(1,50);
const hhea=Buffer.alloc(36);hhea.writeUInt32BE(0x10000,0);hhea.writeInt16BE(800,4);hhea.writeInt16BE(-200,6);
hhea.writeUInt16BE(600,10);hhea.writeInt16BE(100,14);hhea.writeInt16BE(500,16);hhea.writeInt16BE(1,18);hhea.writeUInt16BE(count,34);
const maxp=Buffer.alloc(32);maxp.writeUInt32BE(0x10000,0);maxp.writeUInt16BE(count,4);
maxp.writeUInt16BE(140,6);maxp.writeUInt16BE(35,8);maxp.writeUInt16BE(2,14);
const hmtx=concat(glyphs.map(()=>concat(u16(600),s16(0))));
const segCount=chars.length+1,power=2**Math.floor(Math.log2(segCount));
const cmap4=concat(u16(4),u16(16+segCount*8),u16(0),u16(segCount*2),u16(power*2),u16(Math.log2(power)),u16(segCount*2-power*2),
 chars.map(ch=>u16(ch.charCodeAt(0))),u16(0xffff),u16(0),chars.map(ch=>u16(ch.charCodeAt(0))),u16(0xffff),
 chars.map((ch,i)=>u16((i+1-ch.charCodeAt(0))&0xffff)),u16(1),Buffer.alloc(segCount*2));
const cmap=concat(u16(0),u16(1),u16(3),u16(1),u32(12),cmap4);
function utf16be(s){const b=Buffer.from(s,'utf16le');return b.swap16();}
const names={1:'Dejavu Pixel',2:'Regular',3:'DejavuPixel-Regular-1.0',4:'Dejavu Pixel',5:'Version 1.0',6:'DejavuPixel-Regular',
 0:'Copyright 2026 Dejavu contributors',13:'Original bitmap alphabet and font generator. Licensed under the MIT license; see repository LICENSE.'};
let no=0;const nr=[],ns=[];
for(const [id,value]of Object.entries(names)){const b=utf16be(value);nr.push(concat(u16(3),u16(1),u16(0x409),u16(+id),u16(b.length),u16(no)));ns.push(b);no+=b.length;}
const name=concat(u16(0),u16(nr.length),u16(6+nr.length*12),nr,ns);
const post=Buffer.alloc(32);post.writeUInt32BE(0x30000,0);post.writeInt16BE(-100,8);post.writeInt16BE(50,10);post.writeUInt32BE(1,12);
const os2=Buffer.alloc(78);os2.writeInt16BE(600,2);os2.writeUInt16BE(400,4);os2.writeUInt16BE(5,6);
for(const [off,val]of [[10,650],[12,600],[16,75],[18,650],[20,600],[24,350],[26,50],[28,250]])os2.writeInt16BE(val,off);
os2.writeUInt32BE(1,42);os2.write('DJVU',58,'ascii');os2.writeUInt16BE(64,62);
os2.writeUInt16BE(chars[0].charCodeAt(0),64);os2.writeUInt16BE(chars.at(-1).charCodeAt(0),66);
os2.writeInt16BE(800,68);os2.writeInt16BE(-200,70);os2.writeUInt16BE(800,74);os2.writeUInt16BE(200,76);
const tables=Object.entries({'OS/2':os2,cmap,glyf,head,hhea,hmtx,loca,maxp,name,post}).sort(([a],[b])=>a<b?-1:a>b?1:0);
function sum(b){let s=0;const p=pad(b);for(let i=0;i<p.length;i+=4)s=(s+p.readUInt32BE(i))>>>0;return s;}
const n=tables.length,p=2**Math.floor(Math.log2(n));let pos=12+n*16;
const directory=[],data=[];let headOffset;
for(const [tag,b]of tables){const record=Buffer.alloc(16);record.write(tag,0,4,'ascii');record.writeUInt32BE(sum(b),4);
 record.writeUInt32BE(pos,8);record.writeUInt32BE(b.length,12);directory.push(record);data.push(pad(b));if(tag==='head')headOffset=pos;pos+=pad(b).length;}
const font=concat(u32(0x10000),u16(n),u16(p*16),u16(Math.log2(p)),u16(n*16-p*16),directory,data);
font.writeUInt32BE((0xb1b0afba-sum(font))>>>0,headOffset+8);
if(sum(font)!==0xb1b0afba)throw new Error('Font checksum failed');
const target=path.join(repo,'assets','Fonts','DejavuPixel-Regular.ttf');fs.writeFileSync(target,font);
console.log(`Compiled ${count} original glyphs, ${font.length} bytes; whole-font checksum verified.`);
