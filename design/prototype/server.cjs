const http=require('node:http');
const fs=require('node:fs');
const path=require('node:path');
const root=__dirname;
const types={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'application/javascript; charset=utf-8','.svg':'image/svg+xml','.png':'image/png','.ttf':'font/ttf'};
const allowed=new Set(['index.html','style.css','preview.css','themes.css','platform.css','themes.js','motion.js','NanumPenScript-Regular.ttf','icons.js','app.js','brand-mark.svg','brand-exploration/frame-mark.svg','brand-exploration/frame-mono.svg','claude-menu.png','codex-menu.png']);
http.createServer((req,res)=>{const pathname=new URL(req.url,'http://localhost').pathname;const name=pathname==='/'?'index.html':pathname.slice(1);if(!allowed.has(name)){res.writeHead(404);res.end('Not found');return;}fs.readFile(path.join(root,name),(error,data)=>{if(error){res.writeHead(500);res.end('Unable to load preview');return;}res.writeHead(200,{'Content-Type':types[path.extname(name)],'Cache-Control':'no-store'});res.end(data);});}).listen(5184,'127.0.0.1',()=>console.log('Dejavu design preview: http://127.0.0.1:5184'));
