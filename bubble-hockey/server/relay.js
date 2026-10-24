// Room-code relay for Bubble Hockey online play.
//
// Pairs two players by a short code and forwards their messages. It runs no
// game logic: the host's game is the authority. Rooms live in memory only.

'use strict';

const http = require('http');
const { WebSocketServer } = require('ws');

const PROTOCOL_VERSION = 1;
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 5;
const MAX_MESSAGE_BYTES = 8 * 1024;
const MAX_ROOMS = 5000;
const ROOM_IDLE_MS = 10 * 60 * 1000;
const HEARTBEAT_MS = 30 * 1000;
// Token bucket per connection: the game sends ~50 messages a second.
const RATE_PER_SEC = 120;
const RATE_BURST = 240;

function createRelay({ port = 0, roomIdleMs = ROOM_IDLE_MS, heartbeatMs = HEARTBEAT_MS } = {}) {
  const rooms = new Map(); // code -> { host, guest, lastActive }

  const server = http.createServer((req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true, rooms: rooms.size }));
      return;
    }
    res.writeHead(404);
    res.end();
  });

  const wss = new WebSocketServer({ server, maxPayload: MAX_MESSAGE_BYTES });

  function send(ws, obj) {
    if (ws && ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
  }

  function newCode() {
    for (let attempt = 0; attempt < 50; attempt++) {
      let code = '';
      for (let i = 0; i < CODE_LENGTH; i++) {
        code += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
      }
      if (!rooms.has(code)) return code;
    }
    return null;
  }

  function peerOf(ws) {
    const room = ws.room && rooms.get(ws.room);
    if (!room) return null;
    return room.host === ws ? room.guest : room.host;
  }

  function leaveRoom(ws) {
    const room = ws.room && rooms.get(ws.room);
    if (!room) return;
    const code = ws.room;
    ws.room = null;
    if (room.host === ws) {
      // The host owns the match, so the room ends with them.
      rooms.delete(code);
      if (room.guest) {
        room.guest.room = null;
        send(room.guest, { t: 'peer_left' });
      }
    } else if (room.guest === ws) {
      // Keep the room so the guest can rejoin with the same code.
      room.guest = null;
      room.lastActive = Date.now();
      send(room.host, { t: 'peer_left' });
    }
  }

  function handle(ws, msg) {
    const room = ws.room && rooms.get(ws.room);
    if (room) room.lastActive = Date.now();

    switch (msg.t) {
      case 'create': {
        if (msg.v !== PROTOCOL_VERSION) return send(ws, { t: 'error', code: 'version' });
        if (ws.room) return send(ws, { t: 'error', code: 'bad_request' });
        if (rooms.size >= MAX_ROOMS) return send(ws, { t: 'error', code: 'busy' });
        const code = newCode();
        if (!code) return send(ws, { t: 'error', code: 'busy' });
        rooms.set(code, { host: ws, guest: null, lastActive: Date.now() });
        ws.room = code;
        return send(ws, { t: 'created', code });
      }
      case 'join': {
        if (msg.v !== PROTOCOL_VERSION) return send(ws, { t: 'error', code: 'version' });
        if (ws.room) return send(ws, { t: 'error', code: 'bad_request' });
        const code = typeof msg.code === 'string' ? msg.code.trim().toUpperCase() : '';
        const target = rooms.get(code);
        if (!target) return send(ws, { t: 'error', code: 'not_found' });
        if (target.guest) return send(ws, { t: 'error', code: 'full' });
        target.guest = ws;
        target.lastActive = Date.now();
        ws.room = code;
        send(ws, { t: 'joined', code });
        return send(target.host, { t: 'peer_joined' });
      }
      case 'msg':
        return send(peerOf(ws), { t: 'msg', d: msg.d });
      case 'leave':
        return leaveRoom(ws);
      default:
        return send(ws, { t: 'error', code: 'bad_request' });
    }
  }

  wss.on('connection', (ws) => {
    ws.room = null;
    ws.alive = true;
    ws.tokens = RATE_BURST;
    ws.lastRefill = Date.now();

    ws.on('pong', () => { ws.alive = true; });

    ws.on('message', (data, isBinary) => {
      const now = Date.now();
      ws.tokens = Math.min(RATE_BURST, ws.tokens + ((now - ws.lastRefill) / 1000) * RATE_PER_SEC);
      ws.lastRefill = now;
      if (ws.tokens < 1) {
        send(ws, { t: 'error', code: 'rate_limited' });
        ws.close(1008, 'rate limited');
        return;
      }
      ws.tokens -= 1;

      if (isBinary) return send(ws, { t: 'error', code: 'bad_request' });
      let msg;
      try {
        msg = JSON.parse(data.toString());
      } catch {
        return send(ws, { t: 'error', code: 'bad_request' });
      }
      if (!msg || typeof msg !== 'object') return send(ws, { t: 'error', code: 'bad_request' });
      handle(ws, msg);
    });

    ws.on('close', () => leaveRoom(ws));
    ws.on('error', () => {});
  });

  const timer = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.alive) {
        ws.terminate();
        continue;
      }
      ws.alive = false;
      ws.ping();
    }
    const now = Date.now();
    for (const [code, room] of rooms) {
      if (now - room.lastActive > roomIdleMs) {
        rooms.delete(code);
        for (const ws of [room.host, room.guest]) {
          if (ws) {
            ws.room = null;
            ws.close(1000, 'room expired');
          }
        }
      }
    }
  }, heartbeatMs);

  return new Promise((resolve) => {
    server.listen(port, () => {
      resolve({
        port: server.address().port,
        rooms,
        close: () => new Promise((done) => {
          clearInterval(timer);
          for (const ws of wss.clients) ws.terminate();
          wss.close(() => server.close(() => done()));
        }),
      });
    });
  });
}

module.exports = { createRelay, PROTOCOL_VERSION };

if (require.main === module) {
  const port = Number(process.env.PORT) || 8787;
  createRelay({ port }).then(({ port: p }) => {
    console.log(`Bubble Hockey relay listening on :${p}`);
  });
}
