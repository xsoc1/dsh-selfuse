/** Isolated, official Desktop-composition HTTP-client acceptance; never uses the live profile. */
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const evidenceRoot = 'F:/tools/dsh-remote-validation-20261003';
const anchor = 'F:/Apps/DeepSeekHarness/resources/app.asar/dsh/node_modules/@deepseek-ai/dsh/package.json';
const browserEnvironment = { ...process.env };
const liveProfile = 'C:/Users/HuangZY/.dsh/profiles/desktop';
const protectedFiles = ['package.json', 'cordis.patch.yml', 'cordis.yml', 'pnpm-workspace.yaml', 'pnpm-lock.yaml'];
async function profileDigests() {
  return Object.fromEntries(await Promise.all(protectedFiles.map(async file => {
    try { return [file, createHash('sha256').update(await readFile(join(liveProfile, file))).digest('hex')]; }
    catch (error) { if (error.code === 'ENOENT') return [file, null]; throw error; }
  })));
}
const before = await profileDigests();
assert.equal(process.platform, 'win32');
assert.equal(process.env.ELECTRON_RUN_AS_NODE, '1', 'Run with the installed Electron in Node mode');
await mkdir(evidenceRoot, { recursive: true });
const fixture = await mkdtemp(join(evidenceRoot, 'desktop-seam-'));
const principal = spawnSync('whoami.exe', [], { encoding: 'utf8', windowsHide: true });
assert.equal(principal.status, 0);
const acl = spawnSync('icacls.exe', [fixture, '/inheritance:r', '/grant:r',
  `${principal.stdout.trim()}:(OI)(CI)F`, '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F'],
{ encoding: 'utf8', windowsHide: true });
assert.equal(acl.status, 0, 'Fixture ACL must be restricted before generating launch credentials');
const home = join(fixture, 'home');
const workspace = join(fixture, 'workspace');
const user = join(fixture, 'user');
await Promise.all([home, workspace, user, join(user, 'Roaming'), join(user, 'Local')].map(dir => mkdir(dir, { recursive: true })));
for (const key of Object.keys(process.env)) {
  if (/API.?KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL/i.test(key)) delete process.env[key];
}
Object.assign(process.env, { DSH_HOME: home, USERPROFILE: user, APPDATA: join(user, 'Roaming'),
  LOCALAPPDATA: join(user, 'Local'), DSH_TELEMETRY_DISABLED: '1', DSH_CLIENT_VERSION: '0.2.0-rc.2' });
process.chdir(workspace);
const require = createRequire(anchor);
const relayMode = process.argv.includes('--tailscale-relay');
let relayConfig;
let serveOwned = false;
const tailscale = (args) => {
  const result = spawnSync('C:/Program Files/Tailscale/tailscale.exe', args, { encoding: 'utf8', windowsHide: true, timeout: 30000 });
  assert.equal(result.status, 0, `Tailscale command failed: ${args.slice(0, 2).join(' ')}`);
  return result.stdout;
};
const { initProfile, PROFILE_TEMPLATES, loadProfileDirectory } = await import(pathToFileURL(require.resolve('@deepseek-ai/dsh-app-boot')).href);
const { runProfile } = await import(pathToFileURL(require.resolve('@deepseek-ai/dsh/profile-boot')).href);
const { createLaunchEnvironmentSnapshot } = await import(pathToFileURL(require.resolve('@deepseek-ai/dsh-launch-environment')).href);
const { LlmAdapter, isAgentLoopRequest } = await import(pathToFileURL(require.resolve('@deepseek-ai/dsh-llm')).href);
const profile = join(home, 'profiles', 'desktop');
initProfile(profile, PROFILE_TEMPLATES.web.bundles);
if (relayMode) {
  assert.deepEqual(JSON.parse(tailscale(['serve', 'status', '--json'])), {}, 'Never overwrite existing Serve configuration');
  const tail = JSON.parse(tailscale(['status', '--json']));
  assert.equal(tail.BackendState, 'Running');
  const publicUrl = 'https://' + tail.Self.DNSName.replace(/\.$/u, '') + '/';
  const stateDirectory = join(fixture, 'remote-state');
  await mkdir(stateDirectory);
  relayConfig = { publicUrl, ownerLogin: tail.User[String(tail.Self.UserID)]?.LoginName, relayPort: 17893, stateDirectory };
  assert.ok(relayConfig.ownerLogin);
  const yaml = require('yaml');
  const patchPath = join(profile, 'cordis.patch.yml');
  const patch = yaml.parse(await readFile(patchPath, 'utf8')) ?? [];
  patch.push({ id: 'connection', config: { trustedHosts: [new URL(publicUrl).host] } });
  patch.push({ insert: [{ id: 'desktop-remote', name: pathToFileURL(join(import.meta.dirname, '../plugins/desktop-remote/index.mjs')).href, config: relayConfig }] });
  await writeFile(patchPath, yaml.stringify(patch));
}
const result = { fixture, installedVersion: JSON.parse(await readFile(anchor, 'utf8')).version,
  composition: 'Official fresh Desktop bundles with profileContext.name=desktop; not an Electron-window test',
  checks: [], limitations: [relayMode ? 'Isolated Desktop composition through real Tailscale HTTPS; no live profile, Electron window, real model or Safari.' : 'No live Desktop profile, IPC token, external listener, Tailscale, real model or Safari access.'] };
const check = (name, value = true) => { assert.ok(value, name); result.checks.push(name); };
let app;
let browser;
let finishFixtureStream;
const fixtureStreamGate = new Promise(resolve => { finishFixtureStream = resolve; });
const deadline = setTimeout(() => { console.error('FIXTURE_TIMEOUT'); process.exit(3); }, 180000);
try {
  app = await runProfile({ environment: createLaunchEnvironmentSnapshot([{ source: 'process', values: { ...process.env } }]),
    profile: 'desktop', resolvedProfile: { profile: loadProfileDirectory('dsh', profile, anchor), installAnchor: anchor },
    patchFiles: [], args: ['--no-open', '--port', '0'] });
  await app.ctx.loader.await();
  if (relayMode) {
    const state = JSON.parse(await readFile(join(relayConfig.stateDirectory, 'connection.json'), 'utf8'));
    check('Cordis Host extension follows the actual dynamic Desktop port', state.targetPort === app.ctx.webServer.port && state.relayPort === relayConfig.relayPort);
    tailscale(['serve', '--bg', '--https=443', '--yes', 'http://127.0.0.1:17893']);
    serveOwned = true;
    const anonymousRemote = await fetch(relayConfig.publicUrl, { signal: AbortSignal.timeout(15000) });
    check('Real Tailscale identity admission passes; native anonymous access is rejected', anonymousRemote.status === 401);
    const remoteLogin = await fetch(app.ctx.connection.authenticatedUrl(relayConfig.publicUrl), { redirect: 'manual', signal: AbortSignal.timeout(15000) });
    check('Real HTTPS uses native login exchange with Secure cookie', remoteLogin.status === 303 && remoteLogin.headers.getSetCookie().some(value => /; Secure/iu.test(value)));
  }
  class FixtureAdapter extends LlmAdapter {
    listModels(provider) { return Promise.resolve([{ provider, id: 'local-only', name: 'Local-only fixture' }]); }
    async *stream(options) {
      if (!isAgentLoopRequest(options)) {
        yield { type: 'block-start', index: 0, blockType: 'text' };
        yield { type: 'text-delta', index: 0, text: 'Local fixture' };
        yield { type: 'block-end', index: 0, block: { type: 'text', text: 'Local fixture' } };
        yield { type: 'finish', reason: { kind: 'stop' } };
        return;
      }
      result.localModelCalls = (result.localModelCalls ?? 0) + 1;
      yield { type: 'block-start', index: 0, blockType: 'reasoning' };
      yield { type: 'reasoning-delta', index: 0, text: '本地流式检查正在思考 DSH-FIXTURE-REASONING' };
      await fixtureStreamGate;
      options.signal?.throwIfAborted();
      yield { type: 'block-end', index: 0, block: { type: 'reasoning', text: '本地流式检查正在思考 DSH-FIXTURE-REASONING' } };
      yield { type: 'block-start', index: 1, blockType: 'text' };
      yield { type: 'text-delta', index: 1, text: '本地流式检查已完成 DSH-FIXTURE-COMPLETED' };
      yield { type: 'block-end', index: 1, block: { type: 'text', text: '本地流式检查已完成 DSH-FIXTURE-COMPLETED' } };
      yield { type: 'finish', reason: { kind: 'stop' } };
    }
  }
  app.ctx.llm.registerAdapter(['dsh-local-validation'], new FixtureAdapter());
  check('Official Desktop profile identity', app.ctx.profileContext.name === 'desktop');
  const origin = `http://127.0.0.1:${app.ctx.webServer.port}`;
  const anonymous = await fetch(origin, { signal: AbortSignal.timeout(10000) });
  check('Anonymous root rejected', anonymous.status === 401);
  const loginAddress = app.ctx.connection.authenticatedUrl(origin + '/');
  const login = await fetch(loginAddress, { redirect: 'manual', signal: AbortSignal.timeout(10000) });
  check('Public Host API native authentication exchange', login.status === 303 || login.status === 200);
  const setCookies = login.headers.getSetCookie();
  check('Native cookie is HttpOnly and SameSite Strict', setCookies.some(row => /HttpOnly/i.test(row) && /SameSite=Strict/i.test(row)));
  const cookie = setCookies.map(row => row.split(';')[0]).join('; ');
  const rpc = async (method, args, overrides = {}) => {
    const response = await fetch(`${origin}/api/${method}`, { method: 'POST',
      headers: { 'content-type': 'application/json', cookie, origin, ...overrides },
      body: JSON.stringify({ type: 'client-request', rpcId: randomUUID(), method, payload: { args } }),
      signal: AbortSignal.timeout(15000) });
    const body = await response.json();
    assert.equal(response.status, 200, `RPC HTTP status: ${method}`);
    assert.equal(body.result?.ok, true, `RPC native result: ${method}: ${JSON.stringify(body.result?.error)}`);
    return body.result.value;
  };
  const inventory = await rpc('pluginInventory/list', {});
  check('Authenticated native RPC', Array.isArray(inventory.entries));
  const badOrigin = await fetch(`${origin}/api/pluginInventory/list`, { method: 'POST',
    headers: { 'content-type': 'application/json', cookie, origin: 'https://untrusted.example.test' },
    body: JSON.stringify({ type: 'client-request', rpcId: randomUUID(), method: 'pluginInventory/list', payload: { args: {} } }) });
  check('Authenticated RPC with foreign Origin rejected', badOrigin.status === 403 || badOrigin.status === 401);
  const { chromium } = require('//wsl.localhost/Ubuntu/home/huangzy/tools/deepseek-harness-upgrade-20260929/node_modules/.pnpm/playwright-core@1.61.1/node_modules/playwright-core/index.js');
  browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, env: browserEnvironment });
  const observations = [];
  result.observations = observations;
  const pages = [];
  for (const [label, viewport] of [['desktop-browser', { width: 1680, height: 1050 }], ['ipad-browser', { width: 1024, height: 768 }]]) {
    const context = await browser.newContext({ locale: 'zh-CN', viewport, isMobile: label === 'ipad-browser', hasTouch: label === 'ipad-browser' });
    await context.addInitScript(() => {
      const NativeWebSocket = globalThis.WebSocket;
      globalThis.__fixtureSockets = [];
      globalThis.WebSocket = class extends NativeWebSocket {
        constructor(...args) { super(...args); globalThis.__fixtureSockets.push(this); }
      };
    });
    const page = await context.newPage();
    const observation = { label, pageErrors: [], sockets: 0, frames: 0, fixtureFrames: 0, socketCloses: 0 };
    observations.push(observation);
    page.on('pageerror', error => observation.pageErrors.push(error.message));
    page.on('websocket', socket => {
      if (!socket.url().includes('/api/remote.mux')) return;
      observation.sockets++;
      socket.on('framereceived', frame => {
        observation.frames++;
        if (String(frame.payload).includes('DSH-SAME-HOST-')) observation.fixtureFrames++;
      });
      socket.on('close', () => observation.socketCloses++);
    });
    await page.goto(app.ctx.connection.authenticatedUrl(relayMode && label === 'ipad-browser' ? relayConfig.publicUrl : origin + '/'), { waitUntil: 'load' });
    const preview = page.getByRole('dialog', { name: '预览版说明', exact: true });
    const apiSetup = page.getByRole('dialog', { name: '添加一个 API Key 开始使用', exact: true });
    await page.addLocatorHandler(preview, async () => { await preview.getByRole('button', { name: '继续', exact: true }).click(); });
    await page.addLocatorHandler(apiSetup, async () => { await apiSetup.getByRole('button', { name: '稍后配置', exact: true }).click(); });
    await page.getByRole('button', { name: '设置', exact: true }).waitFor({ timeout: 30000 });
    check(`${label}: browser branch boots without Electron bridge`, await page.evaluate(() => !globalThis.dshDesktop));
    pages.push(page);
  }
  const created = await rpc('workspace/create', { request: { path: workspace } });
  assert.equal(typeof created.workspace.workspaceId, 'string', 'Native WorkspaceView identity');
  const session = await rpc('session/create', { request: { workspaceId: created.workspace.workspaceId, agentPreset: 'standard' } });
  const title = 'DSH-SAME-HOST-' + randomUUID().slice(0, 8);
  await rpc('session/rename', { request: { sessionId: session.sessionId, title } });
  await rpc('session/selectModel', { request: { sessionId: session.sessionId, provider: 'dsh-local-validation', model: 'local-only' } });
  result.sessionId = session.sessionId;
  result.fixtureListed = (await rpc('session/list', { _request: {} })).items.some(row => row.sessionId === session.sessionId || row.id === session.sessionId);
  check('Fixture session belongs to the same Host catalog', result.fixtureListed);
  const prompted = await pages[1].evaluate(async ({ sessionId, requestId }) => {
    const method = 'session/prompt';
    const response = await fetch('/api/' + method, { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ type: 'client-request', rpcId: requestId, method,
        payload: { args: { request: { sessionId, requestId, mode: 'queue', content: [{ type: 'text', text: '这是移动浏览器发出的本地测试 DSH-FIXTURE-USER' }] } } } }) });
    return { status: response.status, body: await response.json() };
  }, { sessionId: session.sessionId, requestId: randomUUID() });
  check('Mobile-context prompt accepted by the same Host', prompted.status === 200 && prompted.body.result?.ok === true);
  for (let index = 0; index < pages.length; index++) {
    const page = pages[index];
    await page.getByRole('treeitem', { name: 'workspace', exact: true }).click();
    await page.getByText(title, { exact: true }).first().waitFor({ timeout: 15000 });
    await page.getByText(title, { exact: true }).first().click();
    await page.getByText(/DSH-FIXTURE-USER/).first().waitFor({ timeout: 15000 });
    await page.getByRole('button', { name: '停止生成', exact: true }).waitFor({ timeout: 15000 });
    await page.getByRole('button', { name: '思考', exact: true }).click();
    await page.getByText(/DSH-FIXTURE-REASONING/).filter({ visible: true }).first().waitFor({ timeout: 15000 });
    await page.screenshot({ path: join(fixture, `${observations[index].label}.png`) });
    await writeFile(join(fixture, `${observations[index].label}.aria.txt`), await page.locator('body').ariaSnapshot());
    check(`${observations[index].label}: same live session appears without refresh`, observations[index].fixtureFrames > 0);
    check(`${observations[index].label}: authenticated mux socket carries frames`, observations[index].sockets > 0 && observations[index].frames > 0);
    check(`${observations[index].label}: streamed reasoning arrives before completion`);
  }
  const mobileSocketsBefore = observations[1].sockets;
  await pages[1].evaluate(() => {
    for (const socket of globalThis.__fixtureSockets) {
      if (socket.url.includes('/api/remote.mux') && socket.readyState === WebSocket.OPEN) socket.close(4001, 'Isolated reconnect acceptance');
    }
  });
  await pages[1].waitForFunction(() => globalThis.__fixtureSockets.filter(socket => socket.url.includes('/api/remote.mux')).length > 1
    && globalThis.__fixtureSockets.some(socket => socket.readyState === WebSocket.OPEN), undefined, { timeout: 15000 });
  check('Native client recovers a deliberately closed mux connection without reload', observations[1].sockets > mobileSocketsBefore);
  finishFixtureStream();
  for (const [index, page] of pages.entries()) {
    await page.getByText(/DSH-FIXTURE-COMPLETED/).first().waitFor({ timeout: 15000 });
    await page.getByRole('button', { name: '发送消息', exact: true }).waitFor({ timeout: 15000 });
    await page.getByRole('button', { name: '停止生成', exact: true }).waitFor({ state: 'hidden', timeout: 15000 });
    check(`${observations[index].label}: completion arrives and running control clears`);
    await page.screenshot({ path: join(fixture, `${observations[index].label}-completed.png`) });
    await writeFile(join(fixture, `${observations[index].label}-completed.aria.txt`), await page.locator('body').ariaSnapshot());
  }
  await pages[1].reload({ waitUntil: 'load' });
  await pages[1].getByText(title, { exact: true }).first().waitFor({ timeout: 15000 });
  check('Second browser reload recovers the same persisted session');
  const sidebar = pages[1].getByRole('button', { name: '收起侧边栏', exact: true });
  if (await sidebar.isVisible()) await sidebar.click();
  await pages[1].setViewportSize({ width: 390, height: 844 });
  await pages[1].screenshot({ path: join(fixture, 'phone-layout.png') });
  check('Phone viewport renders', await pages[1].locator('body').isVisible());
  for (const observation of observations) check(`${observation.label}: no uncaught page error`, observation.pageErrors.length === 0);
  result.observations = observations;
  result.sessionId = session.sessionId;
  result.passed = true;
} catch (error) {
  if (browser) {
    for (const [index, page] of browser.contexts().flatMap(context => context.pages()).entries()) {
      await page.screenshot({ path: join(fixture, `failure-${index}.png`) }).catch(() => {});
      await writeFile(join(fixture, `failure-${index}.aria.txt`), await page.locator('body').ariaSnapshot()).catch(() => {});
    }
  }
  result.passed = false;
  result.failure = String(error.stack ?? error);
  console.error('ISOLATED_SEAM_FAILURE ' + String(error.message ?? error));
  process.exitCode = 1;
} finally {
  finishFixtureStream();
  if (browser) await browser.close();
  if (app) await app.shutdown.shutdown(result.passed ? 0 : 1);
  if (serveOwned) tailscale(['serve', '--https=443', 'off']);
  clearTimeout(deadline);
  result.liveProfileUnchanged = JSON.stringify(before) === JSON.stringify(await profileDigests());
  if (!result.liveProfileUnchanged) { result.passed = false; process.exitCode = 1; }
  await writeFile(join(fixture, 'result.json'), JSON.stringify(result, null, 2) + '\n');
  console.log('ISOLATED_SEAM_RESULT ' + JSON.stringify(result));
}
