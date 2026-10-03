/** Read-only foreground connection probe. Saves counts/codes, never session or frame payloads. */
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { randomUUID } from 'node:crypto';

const root = 'F:/Apps/DeepSeekHarnessRemote';
const seconds = Number(process.argv.find(arg => arg.startsWith('--seconds='))?.split('=')[1] ?? 90);
assert.ok(Number.isInteger(seconds) && seconds >= 10 && seconds <= 600);
const state = JSON.parse(await readFile(root + '/state/connection.json', 'utf8'));
assert.equal(state.authorizationMode, 'tailnet');
const report = { pid: state.pid, seconds, startedAt: new Date().toISOString(), clients: [], probes: [], passed: false,
  limitations: ['PC-side foreground Chromium, not actual mobile radio/VPN/Safari; no sessions or model calls.'] };
const filename = root + '/stability-' + Date.now() + '.json';
const require = createRequire(import.meta.url);
const { chromium } = require('//wsl.localhost/Ubuntu/home/huangzy/tools/deepseek-harness-upgrade-20260929/node_modules/.pnpm/playwright-core@1.61.1/node_modules/playwright-core/index.js');
let browser;
let probeTimer;
let probing = false;
try {
  const initial = await fetch(state.publicUrl, { signal: AbortSignal.timeout(8000) });
  assert.equal(initial.status, 200, 'Remote entry unavailable before observation');
  await initial.arrayBuffer();
  browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
  const pages = [];
  for (const [label, viewport] of [['ipad', { width: 1024, height: 768 }], ['phone', { width: 390, height: 844 }]]) {
    const context = await browser.newContext({ locale: 'zh-CN', viewport, isMobile: true, hasTouch: true });
    await context.addInitScript(() => {
      const NativeWebSocket = globalThis.WebSocket;
      globalThis.__connectionProbe = { events: [], sockets: [], observing: false };
      globalThis.WebSocket = class extends NativeWebSocket {
        constructor(...args) {
          super(...args);
          const probe = globalThis.__connectionProbe;
          if (new URL(this.url).pathname !== '/api/remote.mux') return;
          const id = probe.sockets.push(this) - 1;
          const record = (type, extra = {}) => probe.events.push({ id, type, ms: Math.round(performance.now()), observed: probe.observing, ...extra });
          record('construct');
          this.addEventListener('open', () => record('open'));
          this.addEventListener('error', () => record('error'));
          this.addEventListener('close', event => record('close', { code: event.code, clean: event.wasClean }));
        }
      };
    });
    const page = await context.newPage();
    const client = { label, pageErrors: 0, failedRequests: 0 };
    report.clients.push(client);
    page.on('pageerror', () => client.pageErrors++);
    page.on('requestfailed', () => client.failedRequests++);
    const response = await page.goto(state.publicUrl, { waitUntil: 'load', timeout: 45000 });
    assert.equal(response.status(), 200);
    await page.waitForFunction(() => globalThis.__connectionProbe.sockets.some(socket => socket.readyState === WebSocket.OPEN), undefined, { timeout: 20000 });
    await page.evaluate(() => { globalThis.__connectionProbe.observing = true; });
    pages.push({ page, client });
  }
  const probe = async () => {
    if (probing) return;
    probing = true;
    const started = performance.now();
    try {
      const response = await fetch(new URL('/api/pluginInventory/list', state.publicUrl), { method: 'POST',
        headers: { 'content-type': 'application/json', origin: new URL(state.publicUrl).origin },
        body: JSON.stringify({ type: 'client-request', rpcId: randomUUID(), method: 'pluginInventory/list', payload: { args: {} } }),
        signal: AbortSignal.timeout(8000) });
      const envelope = await response.json();
      report.probes.push({ ms: Math.round(performance.now() - started), status: response.status, ok: envelope.result?.ok === true });
    } catch (error) {
      report.probes.push({ ms: Math.round(performance.now() - started), error: error.cause?.code ?? error.name });
    } finally { probing = false; }
  };
  await probe();
  probeTimer = setInterval(probe, 10000);
  for (let elapsed = 0; elapsed < seconds; elapsed += 15) {
    await new Promise(resolve => setTimeout(resolve, Math.min(15, seconds - elapsed) * 1000));
    console.log(JSON.stringify({ observedSeconds: Math.min(elapsed + 15, seconds), clients: await Promise.all(pages.map(async ({ page, client }) => ({
      label: client.label, events: (await page.evaluate(() => globalThis.__connectionProbe.events)).filter(event => event.observed) }))) }));
  }
  clearInterval(probeTimer);
  await probe();
  for (const { page, client } of pages) {
    Object.assign(client, await page.evaluate(() => ({ events: globalThis.__connectionProbe.events,
      openCount: globalThis.__connectionProbe.sockets.filter(socket => socket.readyState === WebSocket.OPEN).length })));
  }
  const latest = JSON.parse(await readFile(root + '/state/connection.json', 'utf8'));
  assert.equal(latest.pid, state.pid, 'Desktop Host changed during observation');
  assert.ok(report.probes.length > 1 && report.probes.every(probe => probe.ok), 'Read-only RPC probe failed');
  for (const client of report.clients) {
    assert.equal(client.openCount, 1, client.label + ': native mux must remain open');
    assert.equal(client.events.filter(event => event.observed && event.type === 'close').length, 0, client.label + ': unexpected foreground reconnect');
    assert.equal(client.pageErrors, 0, client.label + ': uncaught page error');
  }
  report.passed = true;
} catch (error) {
  report.failure = error instanceof assert.AssertionError ? error.message : (error.cause?.code ?? error.name);
  process.exitCode = 1;
} finally {
  clearInterval(probeTimer);
  await browser?.close();
  report.completedAt = new Date().toISOString();
  await writeFile(filename, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ report: filename, ...report }));
}
