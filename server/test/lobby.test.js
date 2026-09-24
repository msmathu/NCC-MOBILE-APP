import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Store } from '../src/store.js';
import { Lobby, planBot, sampleBot, sanitizeName } from '../src/lobby.js';
import { ROOM_SIZE, COUNTDOWN_SECONDS, MIN_FINISH_MS, FINISH_X } from '../src/course.js';

function setup() {
  const clock = { t: 1_000_000 };
  const store = new Store(':memory:');
  const lobby = new Lobby(store, { now: () => clock.t });
  const join = (name, n) => {
    const inbox = [];
    const send = (m) => inbox.push(m);
    let s = lobby.connect(send);
    s = lobby.handle(s, { t: 'hello', deviceId: `device-${n}-abcdefghijklmnop`, name, directorate: 'Maharashtra' });
    return { s, inbox, send, last: (t) => [...inbox].reverse().find((m) => m.t === t) };
  };
  const advance = (ms) => {
    for (let i = 0; i < ms; i += 100) { clock.t += 100; lobby.tick(); }
  };
  return { clock, store, lobby, join, advance };
}

test('sanitizes names', () => {
  assert.equal(sanitizeName('  Cdt  Ravi!! '), 'Cdt Ravi');
  assert.equal(sanitizeName('x'), null);
  assert.equal(sanitizeName('<script>'), 'script');
});

test('bot plan is monotonic and ends at the finish line', () => {
  const plan = planBot(1);
  let prev = 0;
  for (let t = 0; t <= plan.finishMs + 500; t += 250) {
    const { p } = sampleBot(plan, t);
    assert.ok(p >= prev - 1e-9);
    prev = p;
  }
  assert.equal(prev, 1);
  assert.ok(plan.finishMs > MIN_FINISH_MS, `bot too fast: ${plan.finishMs}`);
  assert.ok(plan.finishMs < 4 * 60 * 1000, `bot too slow: ${plan.finishMs}`);
});

test('create room, join by code, spectate when full, auto-start at 7/7', () => {
  const { lobby, join, advance } = setup();
  const host = join('Host', 0);
  lobby.handle(host.s, { t: 'create' });
  const code = host.last('room').code;
  assert.match(code, /^[A-Z2-9]{4}$/);

  const others = [];
  for (let i = 1; i < ROOM_SIZE; i++) {
    const c = join(`Cadet${i}`, i);
    lobby.handle(c.s, { t: 'join', code: `#${code.toLowerCase()}` });
    others.push(c);
  }
  assert.equal(host.last('room').players.length, ROOM_SIZE);
  assert.equal(host.last('room').state, 'countdown');

  const late = join('Late', 99);
  lobby.handle(late.s, { t: 'join', code });
  assert.equal(late.last('room').spectating, true);
  assert.equal(late.last('room').players.length, ROOM_SIZE);

  advance(COUNTDOWN_SECONDS * 1000 + 100);
  assert.ok(host.inbox.some((m) => m.t === 'go'));
  assert.equal(host.last('room').state, 'racing');
  assert.ok(late.inbox.some((m) => m.t === 'snap'), 'spectator receives snapshots');
});

test('solo host races bots; forged early finish rejected; results pay DP', () => {
  const { lobby, join, advance, store } = setup();
  const host = join('Solo', 0);
  lobby.handle(host.s, { t: 'quick' });
  lobby.handle(host.s, { t: 'start' });
  const room = host.last('room');
  assert.equal(room.players.filter((p) => p.bot).length, ROOM_SIZE - 1);
  advance(COUNTDOWN_SECONDS * 1000 + 100);

  // Teleporting is clamped by the pace limit.
  lobby.handle(host.s, { t: 'progress', p: 1, st: 'run' });
  const r = lobby.rooms.get(room.code).racers.get(host.s.id);
  assert.ok(r.p < 0.05, `progress clamped, got ${r.p}`);
  lobby.handle(host.s, { t: 'finish' });
  assert.equal(host.last('error').msg, 'Finish rejected: course not completed');

  // Run the course legitimately at ~300px/s.
  for (let i = 0; i < 700 && r.p < 1; i++) {
    advance(100);
    lobby.handle(host.s, { t: 'progress', p: r.p + 30 / FINISH_X, st: 'run' });
  }
  assert.equal(r.p, 1);
  lobby.handle(host.s, { t: 'finish' });

  // Level 2: target practice. Wrong-stage and out-of-range scores are rejected / clamped.
  let view = host.last('room');
  assert.equal(view.state, 'racing');
  assert.equal(view.stage, 'range');
  assert.ok(host.last('stage').seed > 0);
  assert.ok(view.players.find((p) => p.id === host.s.id).coursePlace >= 1);
  lobby.handle(host.s, { t: 'score', stage: 'map', score: 50 });
  assert.equal(host.last('room').stage, 'range');
  lobby.handle(host.s, { t: 'score', stage: 'range', score: 999 });
  // Level 3 starts once the only human has submitted (bots are filled in).
  view = host.last('room');
  assert.equal(view.stage, 'map');
  assert.equal(view.players.find((p) => p.id === host.s.id).rangeScore, 50);
  assert.ok(view.players.filter((p) => p.bot).every((p) => p.rangeScore > 0));
  lobby.handle(host.s, { t: 'score', stage: 'map', score: 37 });

  const res = host.last('room');
  assert.equal(res.state, 'results');
  const mine = res.results.find((x) => x.id === host.s.id);
  assert.equal(mine.rangeScore, 50);
  assert.equal(mine.mapScore, 37);
  assert.ok(mine.points >= 3 * 2 && mine.place >= 1 && mine.dp > 0);
  for (let i = 1; i < res.results.length; i++) assert.ok(res.results[i - 1].points >= res.results[i].points);
  assert.equal(host.last('profile').profile.dp, mine.dp);
  assert.equal(store.leaderboard().directorates[0].name, 'Maharashtra');

  lobby.handle(host.s, { t: 'rematch' });
  assert.equal(host.last('room').state, 'waiting');
  assert.equal(host.last('room').players.length, 1);
});

test('reconnect with token resumes the same slot', () => {
  const { lobby, join, clock } = setup();
  const a = join('Alpha', 0);
  const b = join('Bravo', 1);
  lobby.handle(a.s, { t: 'create' });
  const code = a.last('room').code;
  lobby.handle(b.s, { t: 'join', code });
  const token = b.last('welcome').token;

  lobby.disconnect(b.s, b.send);
  assert.equal(a.last('room').players.find((p) => p.name === 'Bravo').connected, false);

  clock.t += 5000;
  const inbox = [];
  const send2 = (m) => inbox.push(m);
  const fresh = lobby.connect(send2);
  const resumed = lobby.handle(fresh, { t: 'hello', deviceId: 'device-1-abcdefghijklmnop', name: 'Bravo', token });
  assert.equal(resumed, b.s);
  assert.equal(inbox.find((m) => m.t === 'welcome').resumed, true);
  assert.equal(a.last('room').players.find((p) => p.name === 'Bravo').connected, true);

  // Old socket closing late must not drop the resumed session.
  lobby.disconnect(b.s, b.send);
  assert.equal(a.last('room').players.find((p) => p.name === 'Bravo').connected, true);
});

test('stages time out when a cadet never submits', () => {
  const { lobby, join, advance } = setup();
  const a = join('Alpha', 0);
  const b = join('Bravo', 1);
  lobby.handle(a.s, { t: 'create' });
  lobby.handle(b.s, { t: 'join', code: a.last('room').code });
  lobby.handle(a.s, { t: 'start' });
  advance(COUNTDOWN_SECONDS * 1000 + 100);
  // Nobody finishes the course: it times out after 6 minutes, then each stage times out.
  advance(6 * 60 * 1000 + 200);
  assert.equal(a.last('room').stage, 'range');
  lobby.handle(a.s, { t: 'score', stage: 'range', score: 40 });
  assert.equal(a.last('room').stage, 'range', 'waits for Bravo');
  advance(100 * 1000 + 200);
  assert.equal(a.last('room').stage, 'map');
  advance(150 * 1000 + 200);
  const res = a.last('room');
  assert.equal(res.state, 'results');
  assert.equal(res.results.find((r) => r.name === 'Bravo').rangeScore, null);
});

test('customization is gated by rank', () => {
  const { lobby, join } = setup();
  const c = join('Rookie', 0);
  lobby.handle(c.s, { t: 'look', uniform: 'navy', beret: 'maroon', badge: 'none' });
  assert.match(c.last('error').msg, /unlocks at Lance Corporal/);
  lobby.handle(c.s, { t: 'look', uniform: 'army', beret: 'maroon', badge: 'none' });
  assert.equal(c.last('profile').profile.uniform, 'army');
});
