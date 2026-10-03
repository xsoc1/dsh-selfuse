import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createServer, request } from 'node:http';
import { once } from 'node:events';
import { createRelay, validateConfig } from './index.mjs';
import { createNativeCookieProvider } from './native-auth.mjs';

const config = { publicUrl: 'https://example.tail123456.ts.net/', authorizationMode: 'tailnet', relayPort: 0 };
const cookie = 'dsh-auth-fixture=v1.fixture.signature';
const headers = { host: 'example.tail123456.ts.net', 'x-forwarded-host': 'example.tail123456.ts.net',
  'x-forwarded-proto': 'https', 'x-forwarded-for': '100.64.1.2', origin: 'https://example.tail123456.ts.net' };
async function query(port, changes = {}, path = '/', body) {
  return await new Promise((resolve, reject) => {
    const req = request({ hostname: '127.0.0.1', port, path, method: body ? 'POST' : 'GET', headers: { ...headers, ...changes } }, res => {
      const chunks = [];
      res.on('data', chunk => chunks.push(chunk));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks).toString() }));
      res.on('error', reject);
    });
    req.on('error', reject); req.end(body);
  });
}

test('tailnet mode is explicit; neither a browser credential nor an owner login is required', async () => {
  assert.equal(validateConfig(config).authorizationMode, 'tailnet');
  assert.throws(() => validateConfig({ ...config, authorizationMode: 'unsafe' }));
  await assert.rejects(createRelay(config, () => 1), /server-side authentication/u);
});

test('tailnet HTTP accepts member and tagged peers; keeps native cookie private and rejects unsafe carriers', async () => {
  let backendCalls = 0;
  let authCalls = 0;
  const backend = createServer((req, res) => {
    backendCalls++;
    assert.ok(req.headers.cookie.endsWith(cookie));
    assert.ok(!req.headers.cookie.includes('v1.bad.bad'));
    res.writeHead(200, { 'set-cookie': [cookie + '; Max-Age=3600; Path=/; HttpOnly; SameSite=Strict', 'ui=fixture; Path=/'] });
    if (req.method === 'POST') req.pipe(res); else res.end('native authorized');
  });
  backend.listen(0, '127.0.0.1'); await once(backend, 'listening');
  const relay = await createRelay(config, () => backend.address().port, async () => { authCalls++; return cookie; });
  try {
    const anonymousBrowser = await query(relay.port);
    assert.equal(anonymousBrowser.status, 200);
    assert.deepEqual(anonymousBrowser.headers['set-cookie'], ['ui=fixture; Path=/; Secure']);
    assert.ok(!anonymousBrowser.body.includes(cookie));
    assert.equal((await query(relay.port, { 'tailscale-user-login': 'different-member@example.test' })).status, 200);
    assert.equal((await query(relay.port, { 'tailscale-user-login': '', 'x-forwarded-for': 'fd7a:115c:a1e0::12' })).status, 200);
    const payload = '中文 ' + 'x'.repeat(128000);
    assert.equal((await query(relay.port, { cookie: 'ui=fixture; dsh-auth-fixture=v1.bad.bad' }, '/api/fixture', payload)).body, payload);
    const before = backendCalls;
    const authBefore = authCalls;
    for (const change of [{ 'x-forwarded-for': '' }, { 'x-forwarded-for': '203.0.113.1' },
      { 'x-forwarded-for': '127.0.0.1' }, { 'x-forwarded-for': '100.128.0.1' },
      { 'x-forwarded-for': 'fd00::1' }, { 'x-forwarded-for': '100.64.1.2, 203.0.113.1' },
      { host: 'evil.test' }, { 'x-forwarded-host': 'evil.test' }, { 'x-forwarded-proto': 'http' },
      { origin: 'https://evil.test' }, { 'tailscale-funnel-request': '?1' }]) {
      assert.equal((await query(relay.port, change)).status, 403);
    }
    assert.equal(backendCalls, before);
    assert.equal(authCalls, authBefore, 'Carrier rejection happens before native authentication');
    const oldLink = await query(relay.port, {}, '/?token=obsolete');
    assert.equal(oldLink.status, 303); assert.equal(oldLink.headers.location, './');
    assert.equal(backendCalls, before, 'Obsolete browser tokens never reach the native backend');
  } finally { await relay.close(); await new Promise(resolve => backend.close(resolve)); }
});

test('tailnet mode fails closed on native authentication failure', async () => {
  const relay = await createRelay(config, () => 1, async () => { throw new Error('Fixture authentication unavailable'); });
  try { assert.equal((await query(relay.port)).status, 503); }
  finally { await relay.close(); }
});

test('tailnet native mux is authenticated on the server without a browser cookie', async () => {
  const backend = createServer();
  backend.on('upgrade', (req, socket) => {
    assert.equal(req.headers.cookie, cookie);
    socket.write('HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: fixture\r\n\r\n');
    socket.pipe(socket);
  });
  backend.listen(0, '127.0.0.1'); await once(backend, 'listening');
  const relay = await createRelay(config, () => backend.address().port, async () => cookie);
  try {
    const result = await new Promise((resolve, reject) => {
      const req = request({ hostname: '127.0.0.1', port: relay.port, path: '/api/remote.mux', headers: { ...headers, connection: 'Upgrade', upgrade: 'fixture' } });
      req.on('upgrade', (_res, socket) => { socket.on('data', data => { socket.destroy(); resolve(data.toString()); }); socket.write('tailnet-mux'); });
      req.on('error', reject); req.end();
    });
    assert.equal(result, 'tailnet-mux');
  } finally { await relay.close(); await new Promise(resolve => backend.close(resolve)); }
});

test('native cookie cache coalesces requests, refreshes before expiry and clears on shutdown', async () => {
  let calls = 0;
  let clock = 0;
  const backend = createServer((req, res) => {
    calls++;
    assert.equal(req.headers.host, headers.host);
    assert.equal(req.url, '/?token=private-fixture');
    res.writeHead(303, { location: './', 'set-cookie': [cookie + '; Max-Age=2; Path=/; HttpOnly; SameSite=Strict'] }); res.end();
  });
  backend.listen(0, '127.0.0.1'); await once(backend, 'listening');
  const auth = createNativeCookieProvider(config.publicUrl, () => backend.address().port, base => base + '?token=private-fixture', () => clock);
  try {
    assert.ok((await Promise.all(Array.from({ length: 10 }, () => auth.get()))).every(value => value === cookie));
    assert.equal(calls, 1);
    clock = 900; assert.equal(await auth.get(), cookie); assert.equal(calls, 1);
    clock = 1000; assert.equal(await auth.get(), cookie); assert.equal(calls, 2);
    auth.close(); await assert.rejects(auth.get(), /closed/u);
  } finally { auth.close(); await new Promise(resolve => backend.close(resolve)); }
});

test('failed native authentication never caches an unauthenticated result', async () => {
  let status = 401;
  const backend = createServer((_req, res) => {
    res.writeHead(status, { location: './', 'set-cookie': [cookie + '; Max-Age=60; Path=/; HttpOnly; SameSite=Strict'] }); res.end();
  });
  backend.listen(0, '127.0.0.1'); await once(backend, 'listening');
  const auth = createNativeCookieProvider(config.publicUrl, () => backend.address().port, base => base + '?token=fixture');
  try { await assert.rejects(auth.get(), /authentication failed/u); status = 303; assert.equal(await auth.get(), cookie); }
  finally { auth.close(); await new Promise(resolve => backend.close(resolve)); }
});
