#!/usr/bin/env node
// Path router: forge.gitgraphs.dev (tunnel) -> single port 8080
//   /webhook*           -> 127.0.0.1:8787  (forge-pr)
//   /webhooks/agentmail -> 127.0.0.1:3000  (forge-issue)
const http = require('http');
const ROUTES = [
  { prefix: '/mcp', target: { host: '127.0.0.1', port: 3000 } },
  { prefix: '/webhooks/agentmail', target: { host: '127.0.0.1', port: 3000 } },
  { prefix: '/webhook', target: { host: '127.0.0.1', port: 8787 } },
];
http.createServer((req, res) => {
  const route = ROUTES.find(r => req.url.startsWith(r.prefix));
  if (!route) { res.writeHead(404, {'content-type':'text/plain'}); return res.end('no route'); }
  const proxy = http.request({ ...route.target, path: req.url, method: req.method, headers: req.headers }, upstream => {
    res.writeHead(upstream.statusCode, upstream.headers);
    upstream.pipe(res);
  });
  proxy.on('error', () => { res.writeHead(502); res.end('upstream down'); });
  req.pipe(proxy);
}).listen(8080, '127.0.0.1', () => console.log('forge router on :8080'));
