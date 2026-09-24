// Room lifecycle (waiting -> countdown -> racing -> results), matchmaking,
// guest sessions, bots and race sync. Transport-agnostic: sessions expose send().
import crypto from 'node:crypto';
import {
  ROOM_SIZE, COUNTDOWN_SECONDS, RACE_TIMEOUT_MS, RESULTS_LINGER_MS, RECONNECT_GRACE_MS,
  FINISH_X, OBSTACLE_COUNT, OBSTACLE_PASS_WIDTH, SPRINT_LENGTH, MIN_FINISH_MS,
  DIRECTORATES, ROLES, BOT_NAMES, PLACE_DP, FINISH_BONUS_DP, DNF_DP, obstacleX,
  STAGE_MS, STAGE_MAX_SCORE, STAGE_POINTS, RANGE_STAR_DP,
} from './course.js';

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CHEERS = ['👏', '🔥', '💪', '🙌', '🎖️', '😂', '🚀', '🫡'];
const UNIFORMS = ['army', 'navy', 'air'];
const BERETS = ['maroon', 'black', 'blue', 'green'];
// Fastest legitimate pace (px/s) with generous headroom for leader aura and sprinting.
const MAX_PACE = 700;

const rand = (a, b) => a + Math.random() * (b - a);
const shortId = () => crypto.randomBytes(6).toString('base64url');

export function sanitizeName(raw) {
  const name = String(raw ?? '').replace(/[^\p{L}\p{N} ._-]/gu, '').replace(/\s+/g, ' ').trim().slice(0, 16);
  return name.length >= 2 ? name : null;
}

// Precomputes a bot's whole race as (time, x) keyframes so it can be sampled cheaply each tick.
export function planBot(skill) {
  const frames = [{ t: 0, x: 0, st: 'run' }];
  let t = 0;
  let x = 0;
  for (let i = 0; i < OBSTACLE_COUNT - 1; i++) {
    const level = Math.floor(i / 5);
    const pace = 260 * skill * [1, 0.88, 0.92][level];
    t += ((obstacleX(i) - x) / pace) * 1000;
    x = obstacleX(i);
    frames.push({ t, x, st: 'run' });
    t += (rand(2.6, 6.2) / skill) * 1000;
    frames.push({ t, x, st: `ob${i}` });
    t += 600;
    x += OBSTACLE_PASS_WIDTH;
    frames.push({ t, x, st: 'run' });
  }
  const last = obstacleX(OBSTACLE_COUNT - 1);
  t += ((last - x) / (260 * skill * 0.92)) * 1000;
  frames.push({ t, x: last, st: 'run' });
  t += (SPRINT_LENGTH / (rand(300, 360) * skill)) * 1000;
  frames.push({ t, x: FINISH_X, st: 'ob14' });
  return { frames, finishMs: Math.round(t) };
}

export function sampleBot(plan, elapsed) {
  const f = plan.frames;
  if (elapsed >= plan.finishMs) return { p: 1, st: 'done' };
  for (let i = 1; i < f.length; i++) {
    if (elapsed <= f[i].t) {
      const a = f[i - 1];
      const b = f[i];
      const k = b.t === a.t ? 1 : (elapsed - a.t) / (b.t - a.t);
      return { p: (a.x + (b.x - a.x) * k) / FINISH_X, st: b.st };
    }
  }
  return { p: 1, st: 'done' };
}

// Better cadets (higher skill 0.82..1.12) score more, with some luck:
// range ~45-95 of 100, map ~400-950 of 1000. Mirrored in client/scripts/course.gd.
export function botStageScore(skill, stage) {
  const k = (skill - 0.82) / 0.3;
  if (stage === 'range') return Math.round(Math.max(20, Math.min(98, 45 + k * 45 + rand(-10, 10))));
  return Math.round(Math.max(150, Math.min(980, 400 + k * 500 + rand(-120, 120))) / 10) * 10;
}

// Bonus Drill Points for the Level 2 qualification stars.
export function rangeStarDp(score) {
  for (const [min, dp] of RANGE_STAR_DP) if ((score ?? 0) >= min) return dp;
  return 0;
}

class Room {
  constructor(code, isPublic) {
    this.code = code;
    this.isPublic = isPublic;
    this.state = 'waiting';
    this.hostId = null;
    this.racers = new Map(); // id -> racer (humans and bots)
    this.spectators = new Set(); // sessions
    this.rolesMode = false;
    this.countdownEndsAt = 0;
    this.startedAt = 0;
    this.results = null;
    this.resultsAt = 0;
    this.createdAt = Date.now();
  }

  humans() { return [...this.racers.values()].filter((r) => !r.bot); }
  sessions() {
    return [...this.humans().map((r) => r.session), ...this.spectators].filter((s) => s && s.room === this);
  }
  broadcast(msg) { for (const s of this.sessions()) s.send(msg); }
}

export class Lobby {
  constructor(store, { now = () => Date.now() } = {}) {
    this.store = store;
    this.now = now;
    this.rooms = new Map();
    this.sessions = new Map(); // id -> session
    this.byToken = new Map(); // token -> session
  }

  // ---- connection lifecycle -------------------------------------------------

  connect(send) {
    return { id: null, send, room: null, hello: false, lastCheer: 0, closedAt: 0 };
  }

  // `send` identifies the transport that closed; a session already resumed on a
  // newer transport must not be torn down by its old socket closing late.
  // The cadet keeps their slot for RECONNECT_GRACE_MS (app sent to background).
  disconnect(session, send) {
    if (!session.hello || session.send !== send) return;
    session.closedAt = this.now();
    session.send = () => {};
    const room = session.room;
    if (room) {
      const racer = room.racers.get(session.id);
      if (racer) racer.connected = false;
      this.pushRoom(room);
    }
  }

  handle(session, msg) {
    if (!msg || typeof msg.t !== 'string') return;
    if (msg.t !== 'hello' && !session.hello) return session.send({ t: 'error', msg: 'Say hello first' });
    const fn = {
      hello: this.onHello, create: this.onCreate, join: this.onJoin, quick: this.onQuick,
      leave: this.onLeave, start: this.onStart, roles: this.onRoles, progress: this.onProgress,
      finish: this.onFinish, cheer: this.onCheer, look: this.onLook, board: this.onBoard,
      rematch: this.onRematch, ping: this.onPing, score: this.onScore,
    }[msg.t];
    return fn ? fn.call(this, session, msg) : undefined;
  }

  // Returns the session the transport should use from now on (may be a resumed one).
  onHello(session, msg) {
    if (session.hello) {
      return session.send({ t: 'welcome', id: session.id, token: session.token, profile: this.store.profile(session.deviceId), resumed: !!session.room });
    }
    const deviceId = String(msg.deviceId ?? '');
    if (!/^[A-Za-z0-9-]{16,64}$/.test(deviceId)) return session.send({ t: 'error', msg: 'Bad device id' });
    const name = sanitizeName(msg.name);
    if (!name) return session.send({ t: 'error', msg: 'Name must be 2-16 letters or numbers' });
    const directorate = DIRECTORATES.includes(msg.directorate) ? msg.directorate : DIRECTORATES[2];

    // Resume a session that dropped (app went to background, network switch).
    const prev = this.byToken.get(String(msg.token ?? ''));
    if (prev && prev.deviceId === deviceId && prev !== session) {
      prev.send({ t: 'error', msg: 'Signed in on another connection' });
      prev.send = session.send;
      prev.closedAt = 0;
      session.resumed = prev;
      const racer = prev.room?.racers.get(prev.id);
      if (racer) racer.connected = true;
      prev.send({ t: 'welcome', id: prev.id, token: prev.token, profile: this.store.profile(deviceId), resumed: !!prev.room });
      if (prev.room) this.pushRoom(prev.room);
      return prev;
    }

    const profile = this.store.upsert(deviceId, name, directorate);
    Object.assign(session, {
      id: shortId(), token: crypto.randomBytes(18).toString('base64url'), deviceId, name, directorate, hello: true,
    });
    this.sessions.set(session.id, session);
    this.byToken.set(session.token, session);
    session.send({ t: 'welcome', id: session.id, token: session.token, profile, resumed: false });
    return session;
  }

  onCreate(session, msg) {
    this.leaveRoom(session);
    const room = new Room(this.newCode(), false);
    room.rolesMode = !!msg.roles;
    this.rooms.set(room.code, room);
    this.enterRoom(session, room);
  }

  onJoin(session, msg) {
    const code = String(msg.code ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '').replace(/^NCC(?=.{4}$)/, '');
    const room = this.rooms.get(code);
    if (!room) return session.send({ t: 'error', msg: `No parade room #${code}` });
    if (session.room === room) return this.pushRoom(room);
    this.leaveRoom(session);
    this.enterRoom(session, room);
  }

  onQuick(session) {
    this.leaveRoom(session);
    let best = null;
    for (const room of this.rooms.values()) {
      if (!room.isPublic || room.state !== 'waiting' || room.racers.size >= ROOM_SIZE) continue;
      if (!best || room.racers.size > best.racers.size) best = room;
    }
    if (!best) {
      best = new Room(this.newCode(), true);
      this.rooms.set(best.code, best);
    }
    this.enterRoom(session, best);
  }

  onLeave(session) {
    this.leaveRoom(session);
    session.send({ t: 'left' });
  }

  // Host starts early: empty slots are filled with bot cadets.
  onStart(session) {
    const room = session.room;
    if (!room || room.hostId !== session.id || room.state !== 'waiting') return;
    let n = 0;
    const used = new Set([...room.racers.values()].map((r) => r.name));
    const names = BOT_NAMES.filter((b) => !used.has(b)).sort(() => Math.random() - 0.5);
    while (room.racers.size < ROOM_SIZE) {
      const id = `bot_${shortId()}`;
      room.racers.set(id, this.newRacer(id, {
        name: names[n++ % names.length],
        directorate: DIRECTORATES[Math.floor(Math.random() * DIRECTORATES.length)],
        uniform: UNIFORMS[Math.floor(Math.random() * 3)],
        beret: BERETS[Math.floor(Math.random() * 4)],
        badge: 'none',
      }, true));
    }
    this.startCountdown(room);
  }

  onRoles(session, msg) {
    const room = session.room;
    if (!room || room.hostId !== session.id || room.state !== 'waiting') return;
    room.rolesMode = !!msg.on;
    this.pushRoom(room);
  }

  onProgress(session, msg) {
    const room = session.room;
    const racer = room?.racers.get(session.id);
    if (!racer || room.state !== 'racing' || room.stage !== 'course' || racer.finishMs != null || racer.dnf) return;
    const p = Number(msg.p);
    if (!Number.isFinite(p)) return;
    const now = this.now();
    const maxStep = ((now - racer.lastProgressAt) / 1000) * (MAX_PACE / FINISH_X) + 0.01;
    racer.p = Math.min(1, Math.max(racer.p, Math.min(p, racer.p + maxStep)));
    racer.lastProgressAt = now;
    racer.st = String(msg.st ?? 'run').slice(0, 8);
  }

  onFinish(session) {
    const room = session.room;
    const racer = room?.racers.get(session.id);
    if (!racer || room.state !== 'racing' || room.stage !== 'course' || racer.finishMs != null || racer.dnf) return;
    const elapsed = this.now() - room.startedAt;
    if (racer.p < 0.97 || elapsed < MIN_FINISH_MS) {
      return session.send({ t: 'error', msg: 'Finish rejected: course not completed' });
    }
    racer.p = 1;
    racer.st = 'done';
    racer.finishMs = elapsed;
    this.announceFinish(room, racer);
    this.maybeFinishRace(room);
  }

  onCheer(session, msg) {
    const room = session.room;
    const now = this.now();
    if (!room || !CHEERS.includes(msg.e) || now - session.lastCheer < 1200) return;
    session.lastCheer = now;
    room.broadcast({ t: 'cheer', from: session.name, e: msg.e });
  }

  onLook(session, msg) {
    const res = this.store.setLook(session.deviceId, {
      uniform: String(msg.uniform), beret: String(msg.beret), badge: String(msg.badge),
    });
    if (!res.ok) return session.send({ t: 'error', msg: res.error });
    const racer = session.room?.racers.get(session.id);
    if (racer && session.room.state === 'waiting') {
      Object.assign(racer, { uniform: res.profile.uniform, beret: res.profile.beret, badge: res.profile.badge });
      this.pushRoom(session.room);
    }
    session.send({ t: 'profile', profile: res.profile });
  }

  onBoard(session, msg) {
    const dir = DIRECTORATES.includes(msg.dir) ? msg.dir : null;
    session.send({ t: 'board', ...this.store.leaderboard(dir) });
  }

  onRematch(session) {
    const room = session.room;
    if (!room || room.hostId !== session.id || room.state !== 'results') return;
    this.resetRoom(room);
  }

  onPing(session, msg) { session.send({ t: 'pong', c: msg.c ?? 0 }); }

  // Level 2 / 3 result from a client (scores are played locally on the device).
  onScore(session, msg) {
    const room = session.room;
    const racer = room?.racers.get(session.id);
    if (!racer || room.state !== 'racing' || room.stage === 'course' || msg.stage !== room.stage || racer.stageDone) return;
    const score = Math.max(0, Math.min(STAGE_MAX_SCORE[room.stage], Math.round(Number(msg.score) || 0)));
    this.submitStage(room, racer, score);
    this.maybeFinishStage(room);
  }

  // ---- room helpers -------------------------------------------------------

  newCode() {
    for (;;) {
      let code = '';
      for (let i = 0; i < 4; i++) code += CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)];
      if (!this.rooms.has(code)) return code;
    }
  }

  newRacer(id, who, bot = false, session = null) {
    const skill = rand(0.82, 1.12);
    return {
      id, bot, session, connected: true, deviceId: who.deviceId ?? null, skill,
      name: who.name, directorate: who.directorate,
      uniform: who.uniform ?? 'army', beret: who.beret ?? 'maroon', badge: who.badge ?? 'none',
      role: 'cadet', p: 0, st: 'wait', finishMs: null, dnf: false, left: false, lastProgressAt: 0,
      plan: bot ? planBot(skill) : null,
      ...this.freshScores(),
    };
  }

  freshScores() {
    return { coursePlace: null, rangeScore: null, mapScore: null, points: 0, stageDone: false, botDoneAt: 0, botScore: 0 };
  }

  enterRoom(session, room) {
    session.room = room;
    if (room.state === 'waiting' && room.racers.size < ROOM_SIZE) {
      const profile = this.store.profile(session.deviceId);
      room.racers.set(session.id, this.newRacer(session.id, { ...session, ...profile }, false, session));
      if (!room.hostId) room.hostId = session.id;
      this.pushRoom(room);
      if (room.racers.size === ROOM_SIZE) this.startCountdown(room);
    } else {
      room.spectators.add(session);
      this.pushRoom(room);
    }
  }

  leaveRoom(session) {
    const room = session.room;
    if (!room) return;
    session.room = null;
    room.spectators.delete(session);
    const racer = room.racers.get(session.id);
    if (racer) {
      if (room.state === 'racing') {
        racer.connected = false;
        racer.session = null;
        racer.left = true;
        if (room.stage === 'course') {
          if (racer.finishMs == null) racer.dnf = true;
          this.maybeFinishRace(room);
        } else {
          this.maybeFinishStage(room);
        }
      } else {
        room.racers.delete(session.id);
        if (room.state === 'countdown' && room.humans().length > 0) {
          // Someone dropped during the countdown: go back to waiting (bots stay only if host restarts).
          for (const r of [...room.racers.values()]) if (r.bot) room.racers.delete(r.id);
          room.state = 'waiting';
        }
      }
    }
    if (room.hostId === session.id) {
      const next = room.humans().find((r) => r.session && r.connected);
      room.hostId = next ? next.id : null;
    }
    if (room.sessions().length === 0 && !room.humans().some((r) => r.session)) this.rooms.delete(room.code);
    else this.pushRoom(room);
  }

  startCountdown(room) {
    room.state = 'countdown';
    room.countdownEndsAt = this.now() + COUNTDOWN_SECONDS * 1000;
    this.pushRoom(room);
  }

  startRace(room) {
    room.state = 'racing';
    room.stage = 'course';
    room.startedAt = this.now();
    if (room.rolesMode) {
      const ids = [...room.racers.keys()].sort(() => Math.random() - 0.5);
      ids.forEach((id, i) => { room.racers.get(id).role = ['leader', 'scout', 'scout', 'support', 'support'][i] ?? 'cadet'; });
    }
    for (const r of room.racers.values()) {
      Object.assign(r, { p: 0, st: 'run', finishMs: null, dnf: false, left: false, lastProgressAt: room.startedAt, ...this.freshScores() });
    }
    this.pushRoom(room);
    room.broadcast({ t: 'go' });
  }

  announceFinish(room, racer) {
    const place = [...room.racers.values()].filter((r) => r.finishMs != null).length;
    room.broadcast({ t: 'finished', id: racer.id, name: racer.name, ms: racer.finishMs, place });
  }

  // ---- Level 1: obstacle course ---------------------------------------------

  maybeFinishRace(room) {
    if (room.state !== 'racing' || room.stage !== 'course') return;
    const elapsed = this.now() - room.startedAt;
    const pending = room.humans().some((r) => r.finishMs == null && !r.dnf);
    if (pending && elapsed < RACE_TIMEOUT_MS) return;
    for (const r of room.humans()) if (r.finishMs == null) r.dnf = true;
    this.finishCourse(room);
  }

  finishCourse(room) {
    const all = [...room.racers.values()];
    // Bots always complete their planned run, even if humans finished first.
    for (const r of all) if (r.bot && r.finishMs == null) r.finishMs = r.plan.finishMs;
    all.sort((a, b) => (a.dnf - b.dnf) || ((a.finishMs ?? Infinity) - (b.finishMs ?? Infinity)));
    all.forEach((r, i) => {
      r.coursePlace = r.dnf ? null : i + 1;
      r.points += r.dnf ? 0 : STAGE_POINTS[i];
    });
    this.startStage(room, 'range');
  }

  // ---- Level 2 (range) and Level 3 (map): played on each device, scores submitted ---

  startStage(room, stage) {
    const now = this.now();
    room.stage = stage;
    room.stageSeed = crypto.randomInt(1, 2 ** 31 - 1);
    room.stageEndsAt = now + STAGE_MS[stage];
    const [lo, hi] = stage === 'range' ? [90, 150] : [100, 180];
    for (const r of room.racers.values()) {
      r.stageDone = false;
      if (r.bot) {
        r.botScore = botStageScore(r.skill, stage);
        r.botDoneAt = now + rand(lo, hi) * 1000;
      }
    }
    this.pushRoom(room);
    room.broadcast({ t: 'stage', stage, seed: room.stageSeed });
  }

  submitStage(room, racer, score) {
    racer[`${room.stage}Score`] = score;
    racer.stageDone = true;
    room.broadcast({ t: 'stagedone', id: racer.id, name: racer.name, stage: room.stage, score });
    this.pushRoom(room);
  }

  maybeFinishStage(room) {
    if (room.state !== 'racing' || room.stage === 'course') return;
    const pending = room.humans().some((r) => !r.stageDone && !r.left);
    if (pending && this.now() < room.stageEndsAt) return;
    const key = `${room.stage}Score`;
    for (const r of room.racers.values()) {
      if (r.bot && !r.stageDone) { r[key] = r.botScore; r.stageDone = true; }
    }
    [...room.racers.values()]
      .filter((r) => r[key] != null)
      .sort((a, b) => b[key] - a[key])
      .forEach((r, i) => { r.points += STAGE_POINTS[i]; });
    if (room.stage === 'range') this.startStage(room, 'map');
    else this.finishMatch(room);
  }

  tickStage(room, now) {
    for (const r of room.racers.values()) {
      if (r.bot && !r.stageDone && now >= r.botDoneAt) this.submitStage(room, r, r.botScore);
    }
    this.maybeFinishStage(room);
  }

  // ---- final camp results -------------------------------------------------------

  finishMatch(room) {
    room.state = 'results';
    room.resultsAt = this.now();
    const all = [...room.racers.values()];
    const humansCount = all.filter((r) => !r.bot).length;
    all.sort((a, b) => (b.points - a.points) || ((a.coursePlace ?? 99) - (b.coursePlace ?? 99)));
    // Solo-with-bots matches pay half so nobody farms DP alone.
    const factor = humansCount >= 2 ? 1 : 0.5;
    room.results = all.map((r, i) => {
      const row = {
        id: r.id, name: r.name, directorate: r.directorate, bot: r.bot, role: r.role,
        place: i + 1, ms: r.dnf ? null : r.finishMs, coursePlace: r.coursePlace,
        rangeScore: r.rangeScore, mapScore: r.mapScore, points: r.points, dp: 0,
      };
      if (!r.bot) {
        row.starDp = r.left ? 0 : rangeStarDp(r.rangeScore);
        row.dp = Math.round((r.left ? DNF_DP : PLACE_DP[i] + FINISH_BONUS_DP + row.starDp) * factor);
        const profile = this.store.recordRace(r.deviceId, {
          dp: row.dp, won: row.place === 1, timeMs: row.ms,
        });
        if (r.session?.room === room) r.session.send({ t: 'profile', profile });
      }
      return row;
    });
    this.pushRoom(room);
  }

  resetRoom(room) {
    for (const r of [...room.racers.values()]) {
      if (r.bot || !r.session || r.session.room !== room) room.racers.delete(r.id);
    }
    room.state = 'waiting';
    room.results = null;
    for (const r of room.racers.values()) Object.assign(r, { p: 0, st: 'wait', finishMs: null, dnf: false, left: false, role: 'cadet', ...this.freshScores() });
    // Promote spectators into free slots.
    for (const s of [...room.spectators]) {
      if (room.racers.size >= ROOM_SIZE) break;
      room.spectators.delete(s);
      const profile = this.store.profile(s.deviceId);
      room.racers.set(s.id, this.newRacer(s.id, { ...s, ...profile }, false, s));
    }
    if (!room.racers.has(room.hostId)) room.hostId = room.humans()[0]?.id ?? null;
    this.pushRoom(room);
    if (room.racers.size === ROOM_SIZE) this.startCountdown(room);
  }

  roomView(room) {
    const now = this.now();
    return {
      t: 'room',
      code: room.code,
      isPublic: room.isPublic,
      state: room.state,
      host: room.hostId,
      rolesMode: room.rolesMode,
      size: ROOM_SIZE,
      countdownMs: room.state === 'countdown' ? Math.max(0, room.countdownEndsAt - now) : 0,
      elapsedMs: room.state === 'racing' ? now - room.startedAt : 0,
      stage: room.state === 'racing' ? room.stage : null,
      stageSeed: room.stageSeed ?? 0,
      stageMsLeft: room.state === 'racing' && room.stage !== 'course' ? Math.max(0, room.stageEndsAt - now) : 0,
      spectators: room.spectators.size,
      players: [...room.racers.values()].map((r) => ({
        id: r.id, name: r.name, directorate: r.directorate, bot: r.bot, connected: r.connected,
        uniform: r.uniform, beret: r.beret, badge: r.badge, role: r.role,
        p: r.p, st: r.st, finishMs: r.finishMs, dnf: r.dnf,
        coursePlace: r.coursePlace, rangeScore: r.rangeScore, mapScore: r.mapScore,
        points: r.points, stageDone: r.stageDone,
      })),
      results: room.results,
    };
  }

  pushRoom(room) {
    const view = this.roomView(room);
    for (const s of room.sessions()) s.send({ ...view, spectating: room.spectators.has(s) });
  }

  // ---- clock ----------------------------------------------------------------

  // Called ~10x per second by the server.
  tick() {
    const now = this.now();
    for (const room of this.rooms.values()) {
      if (room.state === 'countdown' && now >= room.countdownEndsAt) this.startRace(room);
      else if (room.state === 'racing' && room.stage === 'course') this.tickRace(room, now);
      else if (room.state === 'racing') this.tickStage(room, now);
      else if (room.state === 'results' && now - room.resultsAt > RESULTS_LINGER_MS) this.resetRoom(room);
    }
  }

  tickRace(room, now) {
    const elapsed = now - room.startedAt;
    for (const r of room.racers.values()) {
      if (!r.bot || r.finishMs != null) continue;
      const s = sampleBot(r.plan, elapsed);
      r.p = s.p;
      r.st = s.st;
      if (s.st === 'done') {
        r.finishMs = r.plan.finishMs;
        this.announceFinish(room, r);
      }
    }
    room.broadcast({
      t: 'snap',
      ms: elapsed,
      pl: [...room.racers.values()].map((r) => [r.id, Math.round(r.p * 10000) / 10000, r.st]),
    });
    this.maybeFinishRace(room);
  }

  // Drops sessions whose reconnect grace expired. Called every few seconds.
  sweep() {
    const now = this.now();
    for (const s of this.sessions.values()) {
      if (!s.closedAt || now - s.closedAt < RECONNECT_GRACE_MS) continue;
      this.leaveRoom(s);
      this.sessions.delete(s.id);
      this.byToken.delete(s.token);
    }
    for (const room of this.rooms.values()) {
      if (room.sessions().length === 0 && now - room.createdAt > RECONNECT_GRACE_MS) this.rooms.delete(room.code);
    }
  }
}

export { CHEERS, ROLES };
