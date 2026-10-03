/** Native CLI link installation and actual Host activation, isolated from production. */
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { request } from 'node:http';
import { executeClosed, mergeRemotePatch } from './desktop-remote.mjs';
import { setModePatch } from './desktop-remote-mode.mjs';

assert.equal(process.env.ELECTRON_RUN_AS_NODE, '1');
const fixture = await mkdtemp('F:/tools/dsh-remote-validation-20261003/native-install-');
const identity = spawnSync('whoami.exe', [], { encoding: 'utf8', windowsHide: true });
assert.equal(spawnSync('icacls.exe', [fixture, '/inheritance:r', '/grant:r', `${identity.stdout.trim()}:(OI)(CI)F`,
  '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F'], { windowsHide: true }).status, 0);
const anchor = 'F:/Apps/DeepSeekHarness/resources/app.asar/dsh/node_modules/@deepseek-ai/dsh/package.json';
const require = createRequire(anchor);
const yaml = require('yaml');
const home = join(fixture, 'home');
const user = join(fixture, 'user');
const profile = join(home, 'profiles/desktop');
const stateDirectory = join(fixture, 'state');
await Promise.all([home, user, join(user, 'Roaming'), join(user, 'Local'), stateDirectory].map(path => mkdir(path, { recursive: true })));
for (const key of Object.keys(process.env)) if (/API.?KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL/i.test(key)) delete process.env[key];
Object.assign(process.env, { DSH_HOME: home, USERPROFILE: user, APPDATA: join(user, 'Roaming'), LOCALAPPDATA: join(user, 'Local'),
  DSH_TELEMETRY_DISABLED: '1', DSH_CLIENT_VERSION: '0.2.0-rc.2' });
const { initProfile, PROFILE_TEMPLATES, loadProfileDirectory } = await import(pathToFileURL(require.resolve('@deepseek-ai/dsh-app-boot')).href);
initProfile(profile, PROFILE_TEMPLATES.web.bundles);
const output = await executeClosed(process.execPath, ['--expose-internals',
  'F:/Apps/DeepSeekHarness/resources/app.asar/dsh/node_modules/@deepseek-ai/dsh-desktop-host/lib/cli.js',
  'plugin', '--profile', 'desktop', 'add', 'link:' + join(import.meta.dirname, '../plugins/desktop-remote').replaceAll('\\', '/')],
{ env: { ...process.env }, cwd: profile, windowsHide: true, timeout: 120000, maxBuffer: 16 * 1024 * 1024 });
await writeFile(join(fixture, 'cli.stdout.log'), output.stdout);
await writeFile(join(fixture, 'cli.stderr.log'), output.stderr);
const config = { publicUrl: 'https://example.tail123456.ts.net/', authority: 'example.tail123456.ts.net',
  ...(process.argv.includes('--tailnet') ? { authorizationMode: 'tailnet' } : { ownerLogin: 'owner@example.test' }), relayPort: 0, stateDirectory };
const source = '- id: unrelated\n  config:\n    retained: true\n- id: connection\n  config:\n    cookieMaxAgeDays: 7\n    trustedHosts: [existing.example]\n';
const merged = yaml.parse(mergeRemotePatch(source, config, yaml));
assert.deepEqual(merged[0], yaml.parse(source)[0]);
assert.equal(merged[1].config.cookieMaxAgeDays, 7);
assert.deepEqual(merged[1].config.trustedHosts, ['existing.example', config.authority]);
const modeFixture = yaml.stringify([{ id: 'unrelated', config: { retained: true } }, { insert: [{ id: 'desktop-remote',
  name: '@dsh-selfuse/desktop-remote', config: { ...config, ownerLogin: 'owner@example.test' } }] }]);
const changedMode = setModePatch(modeFixture, 'tailnet', yaml);
assert.equal(yaml.parse(changedMode.text)[1].insert[0].config.ownerLogin, undefined);
assert.deepEqual(yaml.parse(changedMode.text)[0], yaml.parse(modeFixture)[0]);
const restoredMode = setModePatch(changedMode.text, 'owner-browser', yaml, 'owner@example.test');
assert.equal(yaml.parse(restoredMode.text)[1].insert[0].config.authorizationMode, 'owner-browser');
const patchPath = join(profile, 'cordis.patch.yml');
await writeFile(patchPath, mergeRemotePatch(await readFile(patchPath, 'utf8'), config, yaml));
const { runProfile } = await import(pathToFileURL(require.resolve('@deepseek-ai/dsh/profile-boot')).href);
const { createLaunchEnvironmentSnapshot } = await import(pathToFileURL(require.resolve('@deepseek-ai/dsh-launch-environment')).href);
let app;
const result = { fixture, passed: false };
try {
  app = await runProfile({ environment: createLaunchEnvironmentSnapshot([{ source: 'process', values: { ...process.env } }]),
    profile: 'desktop', resolvedProfile: { profile: loadProfileDirectory('dsh', profile, anchor), installAnchor: anchor },
    patchFiles: [], args: ['--no-open', '--port', '0'] });
  await app.ctx.loader.await();
  const state = JSON.parse(await readFile(join(stateDirectory, 'connection.json'), 'utf8'));
  assert.equal(state.targetPort, app.ctx.webServer.port);
  assert.ok(state.relayPort > 0);
  assert.ok((await readFile(join(stateDirectory, 'connect.html'), 'utf8')).includes((state.loginUrl ?? state.publicUrl).replaceAll('&', '&amp;')));
  if (config.authorizationMode === 'tailnet') {
    assert.equal(state.loginUrl, undefined);
    const response = await new Promise((resolve, reject) => {
      const probe = request({ hostname: '127.0.0.1', port: state.relayPort, path: '/', headers: { host: config.authority,
        'x-forwarded-host': config.authority, 'x-forwarded-proto': 'https', 'x-forwarded-for': '100.64.1.2' } }, res => {
        const chunks = [];
        res.on('data', chunk => chunks.push(chunk));
        res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks).toString() }));
        res.on('error', reject);
      });
      probe.on('error', reject); probe.end();
    });
    assert.equal(response.status, 200);
    assert.equal(response.headers['set-cookie'], undefined);
    assert.ok(response.body.includes('__DSH_BOOT__'));
  }
  result.passed = true;
  result.checks = ['Official CLI direct entry installs link package without a shell', 'Existing trust/config rows preserved',
    'Official loader resolves installed package', 'Real Cordis plugin activates and follows dynamic Host port'];
  if (config.authorizationMode === 'tailnet') result.checks.push('Native authentication works behind a simulated private Serve carrier with no browser credential and no credential in state');
} finally {
  if (app) await app.shutdown.shutdown(result.passed ? 0 : 1);
  await assert.rejects(readFile(join(stateDirectory, 'connection.json')), error => error.code === 'ENOENT');
  await assert.rejects(readFile(join(stateDirectory, 'connect.html')), error => error.code === 'ENOENT');
  result.disposedPrivateLoginState = true;
  await writeFile(join(fixture, 'result.json'), JSON.stringify(result, null, 2));
  console.log('NATIVE_INSTALL_RESULT ' + JSON.stringify(result));
}
