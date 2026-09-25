// NCC Cadet Challenge server: one process handles lobby, matchmaking and race sync
// over plain WebSockets (JSON messages). See ../README.md for the protocol.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { WebSocketServer } from 'ws';
import { Store } from './store.js';
import { Lobby } from './lobby.js';

const PORT = Number(process.env.PORT ?? 2567);
const DB_FILE = process.env.DB_FILE ?? 'data/ncc.db';
const MAX_MSGS_PER_SEC = 30;

fs.mkdirSync(path.dirname(DB_FILE), { recursive: true });
const store = new Store(DB_FILE);
const lobby = new Lobby(store);

// The browser version of the game (Godot web export) is served from WEB_DIR, so one
// free server hosts both the website and the multiplayer WebSocket (same origin).
const WEB_DIR = path.resolve(process.env.WEB_DIR ?? '../docs');
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon', '.json': 'application/json', '.webmanifest': 'application/manifest+json',
};

function serveStatic(req, res) {
  const urlPath = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const file = path.join(WEB_DIR, urlPath === '/' ? 'index.html' : urlPath);
  if (!file.startsWith(WEB_DIR + path.sep) && file !== WEB_DIR) return false;
  let stat;
  try { stat = fs.statSync(file); } catch { return false; }
  if (!stat.isFile()) return false;
  res.writeHead(200, {
    'content-type': MIME[path.extname(file)] ?? 'application/octet-stream',
    'content-length': stat.size,
    'cache-control': path.extname(file) === '.html' ? 'no-cache' : 'public, max-age=3600',
  });
  fs.createReadStream(file).pipe(res);
  return true;
}

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ ok: true, rooms: lobby.rooms.size, sessions: lobby.sessions.size }));
  }
  if (req.method === 'GET' && serveStatic(req, res)) return;
  res.writeHead(404, { 'content-type': 'text/plain' });
  res.end('NCC Cadet Challenge server. Web game not built here (see README).\n');
});

const wss = new WebSocketServer({ server, maxPayload: 4096 });

wss.on('connection', (ws) => {
  const send = (msg) => { if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg)); };
  let session = lobby.connect(send);
  let windowStart = Date.now();
  let count = 0;
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  ws.on('message', (data) => {
    const now = Date.now();
    if (now - windowStart > 1000) { windowStart = now; count = 0; }
    if (++count > MAX_MSGS_PER_SEC) return;
    let msg;
    try { msg = JSON.parse(data.toString()); } catch { return; }
    try {
      const result = lobby.handle(session, msg);
      if (msg?.t === 'hello' && result && result !== session) session = result; // resumed
    } catch (err) {
      console.error('handler error', msg?.t, err);
    }
  });

  ws.on('close', () => lobby.disconnect(session, send));
});

// Detect dead sockets (phones that lost network without closing).
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
}, 15000);

setInterval(() => lobby.tick(), 100);
setInterval(() => lobby.sweep(), 5000);
setInterval(() => lobby.broadcastStats(), 2000);

server.listen(PORT, () => console.log(`NCC Cadet Challenge server on :${PORT} (db: ${DB_FILE})`));

const shutdown = () => { server.close(); store.close(); process.exit(0); };
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
