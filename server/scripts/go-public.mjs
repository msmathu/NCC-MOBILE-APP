// Makes the game playable from anywhere, for free, from this PC:
//   1. starts the game server (unless one is already running on PORT)
//   2. opens a Cloudflare quick tunnel (no account needed) -> https://<random>.trycloudflare.com
//   3. writes ../server.json with the new address and pushes it to GitHub, where every
//      installed app / web page looks it up (see client/scripts/net.gd CONFIG_URL)
// Keep this window open while people play. Ctrl+C stops everything.
import { spawn, execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SERVER_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ROOT = path.resolve(SERVER_DIR, '..');
const PORT = Number(process.env.PORT ?? 2567);
const CLOUDFLARED = process.env.CLOUDFLARED
  ?? [path.join(ROOT, '_tools', 'cloudflared.exe'), path.join(ROOT, '_tools', 'cloudflared'), 'cloudflared']
    .find((p) => !p.includes(path.sep) || fs.existsSync(p));
const REMOTE = process.env.NCC_CONFIG_REMOTE ?? 'website';
const children = [];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function healthy(base) {
  try { return (await fetch(`${base}/health`, { signal: AbortSignal.timeout(4000) })).ok; } catch { return false; }
}

function run(cmd, args, opts = {}) {
  const child = spawn(cmd, args, { cwd: SERVER_DIR, ...opts });
  children.push(child);
  return child;
}

function shutdown() {
  for (const c of children) c.kill();
  process.exit(0);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

// 1. game server
if (await healthy(`http://localhost:${PORT}`)) {
  console.log(`Game server already running on :${PORT}`);
} else {
  const srv = run(process.execPath, ['--disable-warning=ExperimentalWarning', 'src/index.js'], { stdio: 'inherit' });
  srv.on('exit', (code) => { console.error(`Game server stopped (${code}).`); shutdown(); });
  for (let i = 0; i < 40 && !(await healthy(`http://localhost:${PORT}`)); i++) await sleep(250);
}

// 2. tunnel
console.log('Opening free Cloudflare tunnel...');
const tunnel = run(CLOUDFLARED, ['tunnel', '--no-autoupdate', '--url', `http://localhost:${PORT}`]);
const publicUrl = await new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error('No tunnel URL after 60s')), 60000);
  const scan = (buf) => {
    const m = buf.toString().match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/);
    if (m) { clearTimeout(timer); resolve(m[0]); }
  };
  tunnel.stdout.on('data', scan);
  tunnel.stderr.on('data', scan);
  tunnel.on('exit', (code) => reject(new Error(`cloudflared exited (${code})`)));
});
tunnel.on('exit', () => { console.error('Tunnel closed.'); shutdown(); });

// Wait until the public address really reaches the server (DNS can take a few seconds).
let ok = false;
for (let i = 0; i < 30 && !ok; i++) { ok = await healthy(publicUrl); if (!ok) await sleep(2000); }
if (!ok) console.warn('Warning: tunnel not reachable yet; publishing anyway.');

// 3. publish the address
const wsUrl = publicUrl.replace('https://', 'wss://');
const configFile = path.join(ROOT, 'server.json');
fs.writeFileSync(configFile, JSON.stringify({ server: wsUrl, web: publicUrl, updated: new Date().toISOString() }, null, 2) + '\n');
try {
  const git = (...args) => execFileSync('git', ['-C', ROOT, ...args], { stdio: 'pipe' }).toString();
  git('add', 'server.json');
  git('commit', '-m', 'Update public game server address');
  git('push', REMOTE, 'HEAD:main');
  console.log(`Published server.json to the "${REMOTE}" GitHub repo. Apps pick it up within ~5 minutes.`);
} catch (err) {
  console.warn(`Could not push server.json automatically (${String(err.stderr ?? err.message).trim().split('\n')[0]}).`);
  console.warn('Commit and push server.json yourself so installed apps can find the server.');
}

console.log(`
=========================================================
 NCC CADET CHALLENGE IS LIVE - anyone, anywhere can play
   Website:  ${publicUrl}
   App:      Settings > server "auto" (default) finds it
             or enter ${wsUrl}
 Keep this window open. Press Ctrl+C to stop.
=========================================================`);
