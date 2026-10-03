/** Same-Host transport only: native DSH owns authentication, UI, RPC and sessions. */
import assert from 'node:assert/strict';
import { createServer, request as httpRequest } from 'node:http';
import { writeFile, rename, unlink, stat } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { isIP } from 'node:net';
import { createNativeCookieProvider } from './native-auth.mjs';

export const name = 'desktop-remote';
export const inject = ['webServer', 'connection', 'profileContext'];
const hopHeaders = new Set(['connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization',
  'te', 'trailer', 'transfer-encoding', 'upgrade']);

export function validateConfig(config) {
  assert.ok(config && typeof config === 'object');
  const url = new URL(config.publicUrl);
  assert.equal(url.protocol, 'https:');
  assert.equal(url.port, '');
  assert.equal(url.pathname, '/');
  assert.ok(!url.search && !url.hash && !url.username && !url.password);
  assert.match(url.hostname, /^[a-z0-9-]+\.tail[a-z0-9]+\.ts\.net$/u);
  const authorizationMode = config.authorizationMode ?? 'owner-browser';
  assert.ok(['owner-browser', 'tailnet'].includes(authorizationMode), 'Unknown remote authorization mode');
  if (authorizationMode === 'owner-browser') assert.ok(typeof config.ownerLogin === 'string' && config.ownerLogin.length > 0
    && !/[\r\n]/u.test(config.ownerLogin), 'One exact Tailscale user identity is required');
  assert.ok(Number.isInteger(config.relayPort) && config.relayPort >= 0 && config.relayPort <= 65535);
  if (config.stateDirectory !== undefined) assert.ok(isAbsolute(config.stateDirectory));
  return { ...config, authorizationMode, publicUrl: url.href, authority: url.host };
}

/** Serve 1.102.4 overwrites X-Forwarded-For with the actual encrypted peer address. */
function isTailnetAddress(value) {
  if (typeof value !== 'string') return false;
  if (isIP(value) === 4) {
    const octets = value.split('.').map(Number);
    return octets[0] === 100 && octets[1] >= 64 && octets[1] <= 127;
  }
  return isIP(value) === 6 && value.toLowerCase().startsWith('fd7a:115c:a1e0:');
}

/** Tailscale Serve supplies identity and preserves Host. No LAN listener or Funnel. */
export function admitted(request, config) {
  const headers = request.headers;
  return ['127.0.0.1', '::ffff:127.0.0.1'].includes(request.socket.remoteAddress)
    && headers.host === config.authority
    && headers['x-forwarded-host'] === config.authority
    && headers['x-forwarded-proto'] === 'https'
    && (config.authorizationMode === 'tailnet' ? isTailnetAddress(headers['x-forwarded-for'])
      : headers['tailscale-user-login'] === config.ownerLogin)
    && headers['tailscale-funnel-request'] === undefined
    && (headers.origin === undefined || headers.origin === 'https://' + config.authority)
    && typeof request.url === 'string' && request.url.startsWith('/') && !request.url.startsWith('//');
}

function cleanHeaders(headers, upgraded = false) {
  const drop = new Set([...hopHeaders, ...String(headers.connection ?? '').toLowerCase().split(',').map(row => row.trim())]);
  return Object.fromEntries(Object.entries(headers).filter(([key]) => upgraded
    ? !['proxy-authenticate', 'proxy-authorization'].includes(key) : !drop.has(key)));
}

function secureCookies(headers) {
  if (!headers['set-cookie']) return headers;
  return { ...headers, 'set-cookie': headers['set-cookie'].map(value =>
    /(?:^|;)\s*secure(?:;|$)/iu.test(value) ? value : value + '; Secure') };
}

/** Keep Strict cookies: commit the validated login document before a clean navigation. */
function isNativeBrowserLogin(request, incoming, config) {
  const url = new URL(request.url, config.publicUrl);
  return request.method === 'GET'
    && request.headers['sec-fetch-mode'] === 'navigate'
    && request.headers['sec-fetch-dest'] === 'document'
    && url.pathname === '/' && url.searchParams.getAll('token').length === 1
    && incoming.statusCode === 303 && incoming.headers.location === './'
    && incoming.headers['set-cookie']?.some(cookie => /^dsh-auth-[A-Za-z0-9_-]+=v1\./u.test(cookie)
      && /;\s*HttpOnly(?:;|$)/iu.test(cookie) && /;\s*SameSite=Strict(?:;|$)/iu.test(cookie));
}

function sendLoginDocument(response, incoming) {
  const nonce = randomBytes(18).toString('base64');
  const body = Buffer.from(`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>DeepSeek Harness 登录</title><body><p>登录已验证，正在打开 DeepSeek Harness…</p><a href="./">继续进入</a><script nonce="${nonce}">history.replaceState(null,"","./");location.replace("./")</script></body></html>`);
  const headers = secureCookies(cleanHeaders(incoming.headers));
  for (const key of ['location', 'content-length', 'content-type', 'content-encoding', 'etag', 'last-modified']) delete headers[key];
  response.writeHead(200, { ...headers, 'content-type': 'text/html; charset=utf-8', 'content-length': body.length,
    'cache-control': 'no-store', 'referrer-policy': 'no-referrer', 'x-content-type-options': 'nosniff',
    'content-security-policy': `default-src 'none'; script-src 'nonce-${nonce}'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'` });
  response.end(body);
  incoming.resume();
}

/** Stream both HTTP and native mux upgrades without buffering conversation bodies. */
export async function createRelay(rawConfig, getTargetPort, getNativeCookie) {
  const config = validateConfig(rawConfig);
  if (config.authorizationMode === 'tailnet') assert.equal(typeof getNativeCookie, 'function', 'Tailnet mode requires native server-side authentication');
  const sockets = new Set();
  const upstreams = new Set();
  const track = socket => { sockets.add(socket); socket.once('close', () => sockets.delete(socket)); };
  let closing = false;
  async function upstreamOptions(request, upgraded = false) {
    const port = getTargetPort();
    assert.ok(Number.isInteger(port) && port > 0 && port <= 65535, 'Desktop Web Host is not listening');
    const headers = cleanHeaders(request.headers, upgraded);
    if (config.authorizationMode === 'tailnet') {
      const cookie = await getNativeCookie();
      assert.ok(/^dsh-auth-[A-Za-z0-9_-]+=v1\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/u.test(cookie), 'Invalid native cookie shape');
      const others = String(headers.cookie ?? '').split(';').map(row => row.trim()).filter(row => row && !/^dsh-auth-/u.test(row));
      headers.cookie = [...others, cookie].join('; ');
    }
    assert.ok(!closing, 'Relay is closing');
    return { hostname: '127.0.0.1', port, method: request.method, path: request.url, headers, agent: false };
  }
  function responseHeaders(headers, upgraded = false) {
    const output = secureCookies(cleanHeaders(headers, upgraded));
    if (config.authorizationMode === 'tailnet' && output['set-cookie']) {
      output['set-cookie'] = output['set-cookie'].filter(cookie => !/^dsh-auth-/u.test(cookie));
      if (!output['set-cookie'].length) delete output['set-cookie'];
    }
    return output;
  }
  const server = createServer(async (request, response) => {
    if (!admitted(request, config)) { response.writeHead(403, { 'cache-control': 'no-store' }); response.end(); return; }
    const url = new URL(request.url, config.publicUrl);
    if (config.authorizationMode === 'tailnet' && request.method === 'GET' && url.pathname === '/' && url.searchParams.has('token')) {
      response.writeHead(303, { location: './', 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' }); response.end(); return;
    }
    let upstream;
    try { upstream = httpRequest(await upstreamOptions(request)); }
    catch { response.writeHead(503); response.end(); return; }
    upstreams.add(upstream);
    upstream.once('close', () => upstreams.delete(upstream));
    upstream.once('response', incoming => {
      if (config.authorizationMode === 'owner-browser' && isNativeBrowserLogin(request, incoming, config)) { sendLoginDocument(response, incoming); return; }
      response.writeHead(incoming.statusCode, responseHeaders(incoming.headers));
      incoming.once('error', () => response.destroy());
      incoming.pipe(response);
    });
    upstream.once('error', () => {
      if (!response.headersSent) { response.writeHead(502); response.end(); } else response.destroy();
    });
    request.once('aborted', () => upstream.destroy());
    request.once('error', () => upstream.destroy());
    response.once('close', () => { if (!response.writableFinished) upstream.destroy(); });
    request.pipe(upstream);
  });
  server.on('connection', track);
  server.on('upgrade', async (request, socket, head) => {
    socket.on('error', () => socket.destroy());
    if (!admitted(request, config) || new URL(request.url, config.publicUrl).pathname !== '/api/remote.mux') {
      socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n'); return;
    }
    let upstream;
    try { upstream = httpRequest(await upstreamOptions(request, true)); }
    catch { socket.end('HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n'); return; }
    upstreams.add(upstream);
    upstream.once('close', () => upstreams.delete(upstream));
    socket.once('close', () => upstream.destroy());
    upstream.once('error', () => socket.destroy());
    upstream.once('response', response => {
      socket.end(`HTTP/1.1 ${response.statusCode} Rejected\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
      response.resume();
    });
    upstream.once('upgrade', (response, targetSocket, targetHead) => {
      track(targetSocket);
      targetSocket.on('error', () => socket.destroy());
      socket.once('close', () => targetSocket.destroy());
      targetSocket.once('close', () => socket.destroy());
      const lines = Object.entries(responseHeaders(response.headers, true)).flatMap(([key, value]) =>
        (Array.isArray(value) ? value : [value]).map(row => `${key}: ${row}`));
      socket.write(`HTTP/1.1 101 Switching Protocols\r\n${lines.join('\r\n')}\r\n\r\n`);
      if (targetHead.length) socket.write(targetHead);
      if (head.length) targetSocket.write(head);
      socket.pipe(targetSocket); targetSocket.pipe(socket);
    });
    upstream.end();
  });
  server.on('clientError', (_error, socket) => socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'));
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(config.relayPort, '127.0.0.1', () => { server.removeListener('error', reject); resolve(); });
  });
  // Runtime socket errors are local failures, never console-log launch credentials.
  server.on('error', () => { for (const socket of sockets) socket.destroy(); });
  return { port: server.address().port, async close() {
    closing = true;
    const closed = new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    for (const upstream of upstreams) upstream.destroy();
    for (const socket of sockets) socket.destroy();
    await closed;
  } };
}

export async function apply(ctx, rawConfig) {
  assert.equal(ctx.profileContext.name, 'desktop', 'Only the official Desktop Host owns this extension');
  const config = validateConfig(rawConfig);
  assert.ok(config.stateDirectory, 'Installer-protected stateDirectory is required');
  assert.ok((await stat(config.stateDirectory)).isDirectory(), 'Create and protect stateDirectory before boot');
  const nativeAuth = config.authorizationMode === 'tailnet' ? createNativeCookieProvider(config.publicUrl,
    () => ctx.webServer.port, base => ctx.connection.authenticatedUrl(base)) : undefined;
  let relay;
  try {
    relay = await createRelay(config, () => ctx.webServer.port, nativeAuth ? () => nativeAuth.get() : undefined);
  } catch (error) { nativeAuth?.close(); throw error; }
  ctx.effect(() => async () => {
    nativeAuth?.close();
    await relay.close();
    for (const file of ['connection.json', 'connect.html']) {
      await unlink(join(config.stateDirectory, file)).catch(error => { if (error.code !== 'ENOENT') throw error; });
    }
  }, 'private Desktop remote relay');
  const state = { pid: process.pid, relayPort: relay.port, targetPort: ctx.webServer.port,
    publicUrl: config.publicUrl, authorizationMode: config.authorizationMode, startedAt: new Date().toISOString(), status: 'running',
    ...(config.authorizationMode === 'owner-browser' ? { loginUrl: ctx.connection.authenticatedUrl(config.publicUrl) } : {}) };
  const filename = join(config.stateDirectory, 'connection.json');
  const temp = filename + '.' + process.pid + '.tmp';
  await writeFile(temp, JSON.stringify(state, null, 2) + '\n', { mode: 0o600 });
  await rename(temp, filename);
  const escape = value => value.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');
  const entry = config.authorizationMode === 'tailnet' ? config.publicUrl : state.loginUrl;
  const instructions = config.authorizationMode === 'tailnet'
    ? '<p>手机 / iPad 连接此 tailnet 后直接打开下方固定地址，无需登录二维码或浏览器凭据。Tailnet 中获网络规则许可且能访问入口的设备，拥有此 DSH 的现有文件、命令和模型权限；不提供用户间隔离。</p>'
    : '<p>iPad / 手机先连接本人的 Tailscale，再打开下面的完整登录链接。它含本次启动凭据，只发给自己的设备，不公开分享。</p>';
  await writeFile(join(config.stateDirectory, 'connect.html'), `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>DSH 私有连接</title>
<meta name="viewport" content="width=device-width,initial-scale=1"><style>body{font:18px system-ui;max-width:720px;margin:4em auto;padding:20px;overflow-wrap:anywhere}a{display:block;padding:20px;border:1px solid;border-radius:12px}</style>
<h1>DeepSeek Harness 专用远程入口</h1>${instructions}
<a href="${escape(entry)}">${escape(entry)}</a><p>可收藏的固定地址：${escape(config.publicUrl)}。</p>
<p>电脑上的官方 Desktop 必须保持运行。两端访问同一 Host 与会话，不提供整机画面控制。运行中的 DSH 文件和命令权限仍然可用。</p></html>`, { mode: 0o600 });
}
