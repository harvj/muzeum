import https from 'node:https';
import http from 'node:http';
import net from 'node:net';
import fs from 'node:fs';
const routes = {'auth.harvj.com':55492, 'muzeum.fm':55493};
https.createServer({cert:fs.readFileSync('tls.pem'),key:fs.readFileSync('tls.key')}, (req,res) => {
  const port=routes[req.headers.host];
  if (!port) {res.writeHead(403).end();return;}
  const out=http.request({host:'127.0.0.1',port,path:req.url,method:req.method,headers:{...req.headers,'x-forwarded-proto':'https'}}, incoming => {
    res.writeHead(incoming.statusCode,incoming.headers);incoming.pipe(res);
  });out.on('error',()=>res.writeHead(502).end());req.pipe(out);
}).listen(55494,'127.0.0.1');
const proxy=http.createServer((req,res)=>res.writeHead(403).end());
proxy.on('connect',(req,client,head)=>{
  if (!Object.keys(routes).some(host=>req.url===host+':443')) {client.end('HTTP/1.1 403 Forbidden\r\n\r\n');return;}
  const target=net.connect(55494,'127.0.0.1',()=>{
    client.write('HTTP/1.1 200 Connection Established\r\n\r\n'); target.write(head); client.pipe(target).pipe(client);
  });target.on('error',()=>client.destroy());client.on('error',()=>target.destroy());
});proxy.listen(55495,'127.0.0.1');
