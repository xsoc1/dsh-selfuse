/** Read-only acceptance of the running official Desktop and real private HTTPS entry. */
import assert from 'node:assert/strict';
import { readFile, writeFile, unlink } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import { request as httpsRequest } from 'node:https';
import { request as httpRequest } from 'node:http';
import { verifyDesktopPlugins, expectedHosts, expectedClients } from './verify-desktop-plugins.mjs';

const root = 'F:/Apps/DeepSeekHarnessRemote';
await unlink(root + '/live-acceptance.json').catch(error => { if (error.code !== 'ENOENT') throw error; });
const state = JSON.parse(await readFile(root + '/state/connection.json', 'utf8'));
const tailnetMode = state.authorizationMode === 'tailnet';
const report = { pid: state.pid, targetPort: state.targetPort, relayPort: state.relayPort, checks: [],
  startedAt: new Date().toISOString(),
  limitations: ['Read-only live acceptance, no new sessions or model calls; actual Safari/iPad/phone confirmation still required.'] };
const check = (name, value = true) => { assert.ok(value, name); report.checks.push(name); };
if (!tailnetMode) {
  const local = new URL(state.loginUrl);
  local.protocol = 'http:'; local.host = '127.0.0.1:' + state.targetPort;
  report.localPlugins = await verifyDesktopPlugins(local.href);
  check('Existing nine Host and five Client packages still activate and serve');
} else {
  check('Tailnet state has no browser launch credential', state.loginUrl === undefined);
  const local = 'http://127.0.0.1:' + state.targetPort;
  const localRoot = await fetch(local, { signal: AbortSignal.timeout(15000) });
  check('Native loopback index still requires native browser authentication', localRoot.status === 401);
  const localRpc = await fetch(local + '/api/pluginInventory/list', { method: 'POST', headers: { 'content-type': 'application/json', origin: local }, body: '{}', signal: AbortSignal.timeout(15000) });
  check('Native loopback RPC remains unauthorized without credentials', localRpc.status === 401);
  const localMux = await new Promise((resolve, reject) => {
    const request = httpRequest({ hostname: '127.0.0.1', port: state.targetPort, path: '/api/remote.mux', headers: {
      connection: 'Upgrade', upgrade: 'websocket', 'sec-websocket-version': '13',
      'sec-websocket-key': Buffer.alloc(16, 2).toString('base64'), origin: local } }, response => { response.resume(); resolve(response.statusCode); });
    request.on('upgrade', (_response, socket) => { socket.destroy(); resolve(101); });
    request.setTimeout(15000, () => request.destroy(new Error('Local mux check timeout')));
    request.on('error', reject); request.end();
  });
  check('Native loopback mux remains unauthorized without credentials', localMux === 401);
}
const anonymous = await fetch(state.publicUrl, { signal: AbortSignal.timeout(15000) });
check(tailnetMode ? 'Real private HTTPS opens without a browser credential' : 'Real HTTPS anonymous index remains 401', anonymous.status === (tailnetMode ? 200 : 401));
const anonymousRpc = await fetch(new URL('/api/pluginInventory/list', state.publicUrl), { method: 'POST',
  headers: { 'content-type': 'application/json', origin: new URL(state.publicUrl).origin },
  body: JSON.stringify({ type: 'client-request', rpcId: randomUUID(), method: 'pluginInventory/list', payload: { args: {} } }), signal: AbortSignal.timeout(15000) });
check(tailnetMode ? 'Tailnet RPC works without a browser cookie' : 'Real HTTPS anonymous native RPC rejected', anonymousRpc.status === (tailnetMode ? 200 : 401));
const unauthorizedMux = await new Promise((resolve, reject) => {
  const request = httpsRequest(new URL('/api/remote.mux', state.publicUrl), { headers: { connection: 'Upgrade', upgrade: 'websocket',
    'sec-websocket-version': '13', 'sec-websocket-key': Buffer.alloc(16, 1).toString('base64'), origin: new URL(state.publicUrl).origin } }, response => {
    response.resume(); resolve(response.statusCode);
  });
  request.on('upgrade', (_response, socket) => { socket.destroy(); resolve(101); });
  request.setTimeout(15000, () => request.destroy(new Error('Anonymous mux check timeout')));
  request.on('error', reject); request.end();
});
check(tailnetMode ? 'Tailnet native mux opens without a browser cookie' : 'Real HTTPS anonymous native mux rejected', unauthorizedMux === (tailnetMode ? 101 : 401));
let cookie = '';
if (!tailnetMode) {
  const login = await fetch(state.loginUrl, { redirect: 'manual', signal: AbortSignal.timeout(15000) });
  check('Real HTTPS native credential exchange is 303', login.status === 303);
  const cookies = login.headers.getSetCookie();
  check('Remote cookie is Secure, HttpOnly and SameSite Strict', cookies.length > 0 && cookies.every(row => /; Secure/iu.test(row) && /HttpOnly/iu.test(row) && /SameSite=Strict/iu.test(row)));
  cookie = cookies.map(row => row.split(';')[0]).join('; ');
} else {
  check('Native signed cookie is not returned to tailnet browsers', !anonymous.headers.getSetCookie().some(row => /^dsh-auth-/u.test(row)));
  const stale = await fetch(state.publicUrl, { headers: { cookie: 'dsh-auth-stale=v1.bad.bad' }, signal: AbortSignal.timeout(15000) });
  check('A stale browser credential cannot break tailnet admission', stale.status === 200);
}
const rpc = async (method, args, origin = new URL(state.publicUrl).origin) => {
  const response = await fetch(new URL('/api/' + method, state.publicUrl), { method: 'POST',
    headers: { 'content-type': 'application/json', cookie, origin }, signal: AbortSignal.timeout(15000),
    body: JSON.stringify({ type: 'client-request', rpcId: randomUUID(), method, payload: { args } }) });
  if (origin !== new URL(state.publicUrl).origin) return response;
  assert.equal(response.status, 200);
  const envelope = await response.json();
  assert.equal(envelope.result?.ok, true);
  return envelope.result.value;
};
const inventory = await rpc('pluginInventory/list', {});
if (tailnetMode) check('Existing nine Host and five Client inventory entries remain present', expectedHosts.every(name => inventory.entries.some(row => row.moduleName === name && row.fiberPhase === 'active')));
const remote = inventory.entries.filter(row => row.moduleName === '@dsh-selfuse/desktop-remote');
check('Same live Host owns exactly one active remote extension', remote.length === 1 && remote[0].enabled && remote[0].fiberPhase === 'active');
for (const name of expectedHosts) {
  const rows = inventory.entries.filter(row => row.moduleName === name);
  check('Remote Host activation: ' + name, rows.length === 1 && rows[0].fiberPhase === 'active');
}
const rejected = await rpc('pluginInventory/list', {}, 'https://foreign.example.test');
check('Foreign Origin blocked on real HTTPS before native RPC', rejected.status === 403);
const sessions = await rpc('session/list', { _request: {} });
report.sessionCount = sessions.items.length;
check('Remote reads the existing Desktop session catalog', Array.isArray(sessions.items));
const html = await fetch(state.publicUrl, { headers: { cookie }, signal: AbortSignal.timeout(15000) });
assert.equal(html.status, 200);
const graph = JSON.parse((await html.text()).match(/globalThis\["__DSH_BOOT__"\]\s*=\s*(\{[^<]+?\})<\/script>/)?.[1]);
for (const name of expectedClients) {
  const row = graph.entries.find(entry => entry.id === name);
  assert.ok(row);
  const resource = new URL(row.url, state.publicUrl);
  check('Remote Client registration remains same-origin: ' + name, resource.origin === new URL(state.publicUrl).origin);
  const response = await fetch(resource, { headers: { cookie }, signal: AbortSignal.timeout(15000) });
  check('Remote serves Client bundle: ' + name, response.status === 200 && (await response.text()).includes('__ModuleLoader__'));
}
const require = createRequire(import.meta.url);
const { chromium } = require('//wsl.localhost/Ubuntu/home/huangzy/tools/deepseek-harness-upgrade-20260929/node_modules/.pnpm/playwright-core@1.61.1/node_modules/playwright-core/index.js');
const browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
report.browsers = [];
try {
  for (const [label, viewport] of [['ipad', { width: 1024, height: 768 }], ['phone', { width: 390, height: 844 }]]) {
    const context = await browser.newContext({ locale: 'zh-CN', viewport, isMobile: true, hasTouch: true });
    const errors = [];
    await context.addInitScript(() => {
      const NativeWebSocket = globalThis.WebSocket;
      globalThis.__remoteAcceptanceSockets = [];
      globalThis.WebSocket = class extends NativeWebSocket {
        constructor(...args) { super(...args); globalThis.__remoteAcceptanceSockets.push(this); }
      };
    });
    const page = await context.newPage();
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(tailnetMode ? state.publicUrl : state.loginUrl, { waitUntil: 'load', timeout: 45000 });
    await page.waitForFunction(() => globalThis.__remoteAcceptanceSockets.some(socket => socket.url.includes('/api/remote.mux') && socket.readyState === WebSocket.OPEN), undefined, { timeout: 20000 });
    check(label + ': authenticated native mux opens through real private HTTPS');
    const initialCount = await page.evaluate(() => globalThis.__remoteAcceptanceSockets.length);
    await new Promise(resolve => setTimeout(resolve, 15000));
    check(label + ': idle mux remains open without a reconnect loop for 15 seconds', await page.evaluate(count =>
      globalThis.__remoteAcceptanceSockets.length === count && globalThis.__remoteAcceptanceSockets.some(socket => socket.readyState === WebSocket.OPEN), initialCount));
    await page.evaluate(() => globalThis.__remoteAcceptanceSockets.filter(socket => socket.readyState === WebSocket.OPEN).forEach(socket => socket.close(4001, 'Read-only acceptance')));
    await page.waitForFunction(() => globalThis.__remoteAcceptanceSockets.length > 1 && globalThis.__remoteAcceptanceSockets.some(socket => socket.readyState === WebSocket.OPEN), undefined, { timeout: 20000 });
    check(label + ': real HTTPS mux automatically reconnects');
    await page.reload({ waitUntil: 'load' });
    check(label + (tailnetMode ? ': plain entry survives refresh without browser authentication' : ': cookie survives refresh with token removed'), !page.url().includes('token='));
    if (tailnetMode) check(label + ': no native credential stored in browser', !(await context.cookies(state.publicUrl)).some(row => row.name.startsWith('dsh-auth-')));
    check(label + ': browser page has no uncaught error', errors.length === 0);
    await page.screenshot({ path: root + '/' + label + '-live.png' });
    report.browsers.push({ label, errors });
    await context.close();
  }
  report.passed = true;
  report.completedAt = new Date().toISOString();
} catch (error) {
  report.passed = false;
  report.failure = String(error.stack ?? error);
  throw error;
} finally {
  await browser.close();
  await writeFile(root + '/live-acceptance.json', JSON.stringify(report, null, 2));
}
console.log(JSON.stringify(report, null, 2));
