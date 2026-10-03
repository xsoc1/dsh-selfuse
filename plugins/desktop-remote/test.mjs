import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createServer, request } from 'node:http';
import { once } from 'node:events';
import { createRelay, validateConfig } from './index.mjs';

const config = { publicUrl: 'https://example.tail123456.ts.net/', ownerLogin: 'owner@example.test', relayPort: 0 };
const headers = { host: 'example.tail123456.ts.net', 'x-forwarded-host': 'example.tail123456.ts.net',
  'x-forwarded-proto': 'https', 'tailscale-user-login': config.ownerLogin, origin: 'https://example.tail123456.ts.net' };
async function fetchRelay(port, replacements = {}, path = '/', body) {
  return await new Promise((resolve, reject) => {
    const outgoing = request({ hostname: '127.0.0.1', port, path, method: body ? 'POST' : 'GET', headers: { ...headers, ...replacements } }, response => {
      const rows = [];
      response.on('data', value => rows.push(value));
      response.on('end', () => resolve({ status: response.statusCode, headers: response.headers, body: Buffer.concat(rows).toString() }));
    });
    outgoing.on('error', reject); outgoing.end(body);
  });
}
test('reject invalid authority, URL and port configuration', () => {
  for (const change of [{ publicUrl: 'http://example.tail123456.ts.net/' }, { publicUrl: 'https://example.com/' },
    { publicUrl: config.publicUrl + '?token=bad' }, { publicUrl: config.publicUrl + 'prefix/' },
    { ownerLogin: '' }, { relayPort: -1 }, { relayPort: 65536 }]) assert.throws(() => validateConfig({ ...config, ...change }));
});
test('stream native HTTP preserving Host/Origin, add Secure, gate identity and lifecycle', async () => {
  let calls = 0;
  const backend = createServer((req, res) => {
    calls++;
    assert.equal(req.headers.host, headers.host); assert.equal(req.headers.origin, headers.origin);
    res.setHeader('set-cookie', ['native=fixture; Path=/; HttpOnly; SameSite=Strict']);
    req.pipe(res);
  });
  backend.listen(0, '127.0.0.1'); await once(backend, 'listening');
  const relay = await createRelay(config, () => backend.address().port);
  try {
    const payload = '中文 streaming ' + 'x'.repeat(512000);
    const result = await fetchRelay(relay.port, {}, '/', payload);
    assert.equal(result.status, 200); assert.equal(result.body, payload);
    assert.match(result.headers['set-cookie'][0], /; Secure$/u);
    for (const replacement of [{ host: 'foreign.test' }, { 'x-forwarded-proto': 'http' },
      { 'x-forwarded-host': 'foreign.test' }, { 'tailscale-user-login': 'other@example.test' },
      { 'tailscale-user-login': '' }, { 'tailscale-funnel-request': '?1' }, { origin: 'https://foreign.test' }]) {
      assert.equal((await fetchRelay(relay.port, replacement)).status, 403);
    }
    assert.equal((await fetchRelay(relay.port, {}, '//foreign.test')).status, 403);
    assert.equal(calls, 1, 'Rejected requests never reach native backend');
  } finally { await relay.close(); await new Promise(resolve => backend.close(resolve)); }
  await assert.rejects(fetchRelay(relay.port), /ECONNREFUSED|ECONNRESET/u);
});
test('native mux upgrade forwards head and bidirectional bytes; rejects other upgrade path', async () => {
  const backend = createServer();
  backend.on('upgrade', (req, socket, head) => {
    assert.equal(req.headers.host, headers.host);
    socket.write('HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: fixture\r\n\r\n');
    if (head.length) socket.write(head);
    socket.pipe(socket);
  });
  backend.listen(0, '127.0.0.1'); await once(backend, 'listening');
  const relay = await createRelay(config, () => backend.address().port);
  try {
    const response = await new Promise((resolve, reject) => {
      const outgoing = request({ hostname: '127.0.0.1', port: relay.port, path: '/api/remote.mux',
        headers: { ...headers, connection: 'Upgrade', upgrade: 'fixture' } });
      outgoing.on('upgrade', (res, socket) => {
        assert.equal(res.statusCode, 101);
        socket.on('data', data => { socket.destroy(); resolve(data.toString()); }); socket.write('mux-bidirectional');
      });
      outgoing.on('error', reject); outgoing.end();
    });
    assert.equal(response, 'mux-bidirectional');
    const status = await new Promise((resolve, reject) => {
      const outgoing = request({ hostname: '127.0.0.1', port: relay.port, path: '/other',
        headers: { ...headers, connection: 'Upgrade', upgrade: 'fixture' } }, res => { res.resume(); resolve(res.statusCode); });
      outgoing.on('error', reject); outgoing.end();
    });
    assert.equal(status, 403);
  } finally { await relay.close(); await new Promise(resolve => backend.close(resolve)); }
});

test('commit a valid native login document before redirecting; keep Strict auth and other redirects', async () => {
  const privateToken = 'fixture-private-token-not-for-html';
  const nativeCookie = 'dsh-auth-fixture=v1.fixture.signature; Path=/; HttpOnly; SameSite=Strict';
  const backend = createServer((req, res) => {
    if (req.url === '/?token=' + privateToken) {
      res.writeHead(303, { location: './', 'set-cookie': [nativeCookie], 'content-length': '0' });
    } else if (req.url === '/other') {
      res.writeHead(303, { location: './' });
    } else { res.writeHead(401); }
    res.end();
  });
  backend.listen(0, '127.0.0.1'); await once(backend, 'listening');
  const relay = await createRelay(config, () => backend.address().port);
  try {
    const documentHeaders = { 'sec-fetch-mode': 'navigate', 'sec-fetch-dest': 'document' };
    const result = await fetchRelay(relay.port, documentHeaders, '/?token=' + privateToken);
    assert.equal(result.status, 200, 'Browser login must commit a same-origin document before the clean navigation');
    assert.equal(result.headers.location, undefined);
    assert.equal(result.headers['cache-control'], 'no-store');
    assert.equal(result.headers['referrer-policy'], 'no-referrer');
    assert.equal(result.headers['set-cookie'][0], nativeCookie + '; Secure');
    assert.match(result.headers['content-security-policy'], /default-src 'none'/u);
    assert.match(result.headers['content-security-policy'], /frame-ancestors 'none'/u);
    const nonce = result.body.match(/<script nonce="([A-Za-z0-9+/=]+)">/u)?.[1];
    assert.ok(nonce);
    assert.ok(result.headers['content-security-policy'].includes("'nonce-" + nonce + "'"));
    assert.match(result.body, /location\.replace\("\.\/"\)/u);
    assert.ok(!result.body.includes(privateToken), 'Bridge never repeats the launch credential');
    assert.ok(!result.body.includes('signature'), 'HttpOnly cookie must not leak into the document');
    assert.equal((await fetchRelay(relay.port, {}, '/?token=' + privateToken)).status, 303, 'Non-navigation login keeps the native 303 contract');
    assert.equal((await fetchRelay(relay.port, documentHeaders, '/?token=bad')).status, 401);
    assert.equal((await fetchRelay(relay.port, documentHeaders, '/')).status, 401);
    assert.equal((await fetchRelay(relay.port, documentHeaders, '/other')).status, 303);
    assert.equal((await fetchRelay(relay.port, { ...documentHeaders, 'tailscale-user-login': 'other@example.test' }, '/?token=' + privateToken)).status, 403);
  } finally { await relay.close(); await new Promise(resolve => backend.close(resolve)); }
});
