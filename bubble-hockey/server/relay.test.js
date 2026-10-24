'use strict';

const test = require('node:test');
const assert = require('node:assert');
const WebSocket = require('ws');
const { createRelay, PROTOCOL_VERSION } = require('./relay');

function connect(port) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    ws.inbox = [];
    ws.waiters = [];
    ws.on('message', (data) => {
      const msg = JSON.parse(data.toString());
      const w = ws.waiters.shift();
      if (w) w(msg);
      else ws.inbox.push(msg);
    });
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

function next(ws) {
  if (ws.inbox.length) return Promise.resolve(ws.inbox.shift());
  return new Promise((resolve) => ws.waiters.push(resolve));
}

function send(ws, obj) {
  ws.send(JSON.stringify(obj));
}

async function withRelay(fn) {
  const relay = await createRelay({ port: 0 });
  try {
    await fn(relay);
  } finally {
    await relay.close();
  }
}

async function pair(port) {
  const host = await connect(port);
  send(host, { t: 'create', v: PROTOCOL_VERSION });
  const created = await next(host);
  const guest = await connect(port);
  send(guest, { t: 'join', code: created.code.toLowerCase(), v: PROTOCOL_VERSION });
  return { host, guest, code: created.code };
}

test('host creates a room and gets a 5-character code', () =>
  withRelay(async ({ port }) => {
    const host = await connect(port);
    send(host, { t: 'create', v: PROTOCOL_VERSION });
    const msg = await next(host);
    assert.strictEqual(msg.t, 'created');
    assert.match(msg.code, /^[A-Z2-9]{5}$/);
    host.close();
  }));

test('guest joins by code (case-insensitive) and both are told', () =>
  withRelay(async ({ port }) => {
    const { host, guest, code } = await pair(port);
    assert.deepStrictEqual(await next(guest), { t: 'joined', code });
    assert.deepStrictEqual(await next(host), { t: 'peer_joined' });
    host.close();
    guest.close();
  }));

test('messages are relayed both ways', () =>
  withRelay(async ({ port }) => {
    const { host, guest } = await pair(port);
    await next(guest);
    await next(host);
    send(host, { t: 'msg', d: { k: 'st', n: 1 } });
    assert.deepStrictEqual(await next(guest), { t: 'msg', d: { k: 'st', n: 1 } });
    send(guest, { t: 'msg', d: { k: 'in', r: [1, 2] } });
    assert.deepStrictEqual(await next(host), { t: 'msg', d: { k: 'in', r: [1, 2] } });
    host.close();
    guest.close();
  }));

test('unknown code and full room are rejected', () =>
  withRelay(async ({ port }) => {
    const lost = await connect(port);
    send(lost, { t: 'join', code: 'ZZZZZ', v: PROTOCOL_VERSION });
    assert.deepStrictEqual(await next(lost), { t: 'error', code: 'not_found' });

    const { host, guest, code } = await pair(port);
    await next(guest);
    const third = await connect(port);
    send(third, { t: 'join', code, v: PROTOCOL_VERSION });
    assert.deepStrictEqual(await next(third), { t: 'error', code: 'full' });
    for (const ws of [lost, host, guest, third]) ws.close();
  }));

test('version mismatch is rejected', () =>
  withRelay(async ({ port }) => {
    const ws = await connect(port);
    send(ws, { t: 'create', v: 999 });
    assert.deepStrictEqual(await next(ws), { t: 'error', code: 'version' });
    ws.close();
  }));

test('guest can leave and rejoin the same room', () =>
  withRelay(async ({ port, rooms }) => {
    const { host, guest, code } = await pair(port);
    await next(guest);
    await next(host);
    guest.close();
    assert.deepStrictEqual(await next(host), { t: 'peer_left' });
    assert.ok(rooms.has(code), 'room survives a guest drop');

    const again = await connect(port);
    send(again, { t: 'join', code, v: PROTOCOL_VERSION });
    assert.deepStrictEqual(await next(again), { t: 'joined', code });
    assert.deepStrictEqual(await next(host), { t: 'peer_joined' });
    host.close();
    again.close();
  }));

test('room closes when the host leaves', () =>
  withRelay(async ({ port, rooms }) => {
    const { host, guest, code } = await pair(port);
    await next(guest);
    await next(host);
    host.close();
    assert.deepStrictEqual(await next(guest), { t: 'peer_left' });
    assert.ok(!rooms.has(code), 'room is deleted with its host');
    guest.close();
  }));

test('garbage input gets bad_request instead of a crash', () =>
  withRelay(async ({ port }) => {
    const ws = await connect(port);
    ws.send('not json');
    assert.deepStrictEqual(await next(ws), { t: 'error', code: 'bad_request' });
    send(ws, { t: 'nope' });
    assert.deepStrictEqual(await next(ws), { t: 'error', code: 'bad_request' });
    ws.close();
  }));

test('a flood of messages is cut off', () =>
  withRelay(async ({ port }) => {
    const ws = await connect(port);
    const closed = new Promise((resolve) => ws.on('close', resolve));
    for (let i = 0; i < 400; i++) send(ws, { t: 'msg', d: {} });
    await closed;
    assert.ok(ws.inbox.some((m) => m.code === 'rate_limited'));
  }));
