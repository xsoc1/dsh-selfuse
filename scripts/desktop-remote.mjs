/** Private production installer/status. Execute with the installed Electron in Node mode. */
import assert from 'node:assert/strict';
import { cp, mkdir, readFile, writeFile, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createRequire } from 'node:module';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { validateConfig } from '../plugins/desktop-remote/index.mjs';

const execute = promisify(execFile);
const installation = 'F:/Apps/DeepSeekHarness';
const anchor = join(installation, 'resources/app.asar/dsh/node_modules/@deepseek-ai/dsh/package.json');
const cli = join(installation, 'resources/app.asar/dsh/node_modules/@deepseek-ai/dsh-desktop-host/lib/cli.js');
const require = createRequire(anchor);
const configFiles = ['package.json', 'cordis.yml', 'cordis.patch.yml', 'pnpm-lock.yaml', 'pnpm-workspace.yaml'];
const digest = data => createHash('sha256').update(data).digest('hex');
const deployment = 'F:/Apps/DeepSeekHarnessRemote';
export function executeClosed(command, args, options) {
  return new Promise((resolve, reject) => {
    const child = execFile(command, args, options, (error, stdout, stderr) => {
      if (error) { error.stdout = stdout; error.stderr = stderr; reject(error); }
      else resolve({ stdout, stderr });
    });
    child.stdin?.end();
  });
}
export async function stopped() {
  const command = `@(Get-CimInstance Win32_Process -Filter "Name = 'DeepSeek Harness.exe'" | Where-Object { $_.ProcessId -ne ${process.pid} }).Count`;
  const result = await execute('powershell.exe', ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(command, 'utf16le').toString('base64')], { windowsHide: true });
  assert.equal(result.stdout.trim(), '0', 'Exit Desktop normally first');
}
async function tailContext(authorizationMode = 'owner-browser') {
  const output = await execute('C:/Program Files/Tailscale/tailscale.exe', ['status', '--json'], { windowsHide: true });
  const tail = JSON.parse(output.stdout);
  assert.equal(tail.BackendState, 'Running');
  const publicUrl = 'https://' + tail.Self.DNSName.replace(/\.$/u, '') + '/';
  const ownerLogin = tail.User[String(tail.Self.UserID)]?.LoginName;
  return validateConfig({ publicUrl, authorizationMode, ...(authorizationMode === 'tailnet' ? {} : { ownerLogin }), relayPort: 17893, stateDirectory: join(deployment, 'state') });
}
export function mergeRemotePatch(text, config, yaml) {
  const doc = yaml.parseDocument(text);
  assert.equal(doc.errors.length, 0);
  const existing = doc.toJS();
  assert.ok(Array.isArray(existing));
  assert.ok(!existing.some(row => row.id === 'desktop-remote' || row.insert?.some(child => child.id === 'desktop-remote')), 'Already configured; inspect instead of duplicate installation');
  const rows = existing.filter(row => row.id === 'connection');
  assert.ok(rows.length <= 1, 'Ambiguous connection patch');
  if (rows.length) {
    const index = existing.indexOf(rows[0]);
    const current = rows[0].config?.trustedHosts ?? [];
    assert.ok(Array.isArray(current));
    doc.setIn([index, 'config', 'trustedHosts'], [...new Set([...current, config.authority])]);
  } else doc.add({ id: 'connection', config: { trustedHosts: [config.authority] } });
  doc.add({ insert: [{ id: 'desktop-remote', name: '@dsh-selfuse/desktop-remote', config: {
    publicUrl: config.publicUrl, ...(config.authorizationMode === 'tailnet' ? { authorizationMode: 'tailnet' } : { ownerLogin: config.ownerLogin }), relayPort: config.relayPort, stateDirectory: config.stateDirectory,
  } }] });
  const after = doc.toJS();
  for (let index = 0; index < existing.length; index++) {
    if (existing[index].id === 'connection') {
      const copy = structuredClone(after[index]);
      if (existing[index].config?.trustedHosts === undefined) delete copy.config.trustedHosts;
      else copy.config.trustedHosts = existing[index].config.trustedHosts;
      if (existing[index].config === undefined) delete copy.config;
      assert.deepEqual(copy, existing[index]);
    } else assert.deepEqual(after[index], existing[index], 'Unrelated patch rows must remain identical');
  }
  return doc.toString();
}
async function main() {
  assert.equal(process.env.ELECTRON_RUN_AS_NODE, '1');
  const action = process.argv[2] ?? 'status';
  if (action === 'status') {
    const state = JSON.parse(await readFile(join(deployment, 'state/connection.json'), 'utf8'));
    console.log(JSON.stringify({ ...state, ...(state.loginUrl ? { loginUrl: '[private state file only]' } : {}) }, null, 2)); return;
  }
  assert.equal(action, 'install');
  await stopped();
  assert.equal(JSON.parse(await readFile(anchor, 'utf8')).version, '0.2.0-rc.2');
  await assert.rejects(stat(deployment), error => error.code === 'ENOENT', 'Use a fresh dedicated deployment');
  const config = await tailContext(process.argv.includes('--tailnet') ? 'tailnet' : 'owner-browser');
  const profile = join(process.env.USERPROFILE, '.dsh/profiles/desktop');
  const home = join(process.env.USERPROFILE, '.dsh');
  const yaml = require('yaml');
  const patch = await readFile(join(profile, 'cordis.patch.yml'), 'utf8');
  const amended = mergeRemotePatch(patch, config, yaml);
  await mkdir(deployment);
  const who = await execute('whoami.exe', [], { windowsHide: true });
  await execute('icacls.exe', [deployment, '/inheritance:r', '/grant:r',
    `${who.stdout.trim()}:(OI)(CI)F`, '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F'], { windowsHide: true });
  const backup = join(deployment, 'profile-before');
  await mkdir(backup);
  const manifest = {};
  for (const file of configFiles) {
    try {
      const data = await readFile(join(profile, file));
      await cp(join(profile, file), join(backup, file));
      manifest[file] = { existed: true, sha256: digest(data) };
      assert.equal(digest(await readFile(join(backup, file))), manifest[file].sha256);
    } catch (error) { if (error.code !== 'ENOENT') throw error; manifest[file] = { existed: false }; }
  }
  await writeFile(join(backup, 'manifest.json'), JSON.stringify(manifest, null, 2));
  await mkdir(config.stateDirectory);
  await cp(join(import.meta.dirname, '../plugins/desktop-remote'), join(deployment, 'plugin'), { recursive: true });
  await writeFile(join(deployment, 'private-config.json'), JSON.stringify(config, null, 2));
  try {
    // This is the exact bundled CLI entry used by dsh.cmd, directly, without a shell.
    const output = await executeClosed(join(installation, 'DeepSeek Harness.exe'), ['--expose-internals', cli,
      'plugin', '--profile', 'desktop', 'add', 'link:' + join(deployment, 'plugin').replaceAll('\\', '/')],
    { env: { ...process.env, DSH_HOME: home, ELECTRON_RUN_AS_NODE: '1' }, cwd: profile,
      windowsHide: true, timeout: 120000, maxBuffer: 16 * 1024 * 1024 });
    await writeFile(join(deployment, 'cli.stdout.log'), output.stdout);
    await writeFile(join(deployment, 'cli.stderr.log'), output.stderr);
    await stopped();
    assert.equal(await readFile(join(profile, 'cordis.patch.yml'), 'utf8'), patch);
    await writeFile(join(profile, 'cordis.patch.yml'), amended);
    const { loadProfileDirectory } = await import(pathToFileURL(require.resolve('@deepseek-ai/dsh-app-boot')).href);
    const composed = loadProfileDirectory('dsh', profile, anchor);
    assert.deepEqual(composed.skippedBundles, []);
    await writeFile(join(deployment, 'installation.json'), JSON.stringify({ version: '0.2.0-rc.2', backup,
      installed: true, profile, config: { ...config, ownerLogin: '[private config]' },
      acceptance: 'CLI and composition only; separate Host, HTTPS and mobile acceptance required' }, null, 2));
    console.log('DESKTOP_REMOTE_INSTALLED; private backup and connection state are in ' + deployment);
  } catch (error) {
    await writeFile(join(deployment, 'installation-failed.json'), JSON.stringify({ backup, error: String(error.stack ?? error) }, null, 2));
    throw error;
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
