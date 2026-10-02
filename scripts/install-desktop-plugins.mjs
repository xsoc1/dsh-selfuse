import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cp, mkdir, readFile, realpath, stat, symlink, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { basename, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { promisify } from 'node:util';

const execute = promisify(execFile);
export const packages = Object.freeze([
  'plugin-mount', 'skin-layout-compat', 'backup', 'memory-panel', 'soul-md',
  'git-workflow', 'web-ui-git-graph', 'skin-center', 'task-notify', 'content-risk-guard',
]);
const manualRows = ['task-notify', 'content-risk-guard'];
const configFiles = ['package.json', 'cordis.yml', 'cordis.patch.yml', 'pnpm-lock.yaml', 'pnpm-workspace.yaml'];
const payload = ['package.json', 'lib', 'cordis.patch.yml', 'skins', 'contracts', 'LICENSE', 'README.md', 'README.zh.md'];
const digest = data => createHash('sha256').update(data).digest('hex');

/** Give an external link deployment native dependencies and declared in-box peers.
 * The official linked-package resolver reads peer declarations at ancestor projects.
 * This project uses the installed ABI without copying any ASAR or WSL modules.
 */
export async function connectRuntimeDependencies(artifacts, profile, installationEntries, deploymentPackages = packages) {
  assert.equal(await existing(join(artifacts, 'package.json')), undefined, 'Do not overwrite an existing deployment manifest');
  const provided = new Map(installationEntries.filter(entry => entry.scope === 'installation').map(entry => [entry.name, entry]));
  const requested = new Set();
  for (const name of deploymentPackages) {
    const manifest = JSON.parse(await readFile(join(artifacts, name, 'package.json'), 'utf8'));
    for (const dependency of Object.keys({ ...manifest.dependencies, ...manifest.peerDependencies })) requested.add(dependency);
  }
  const peers = {};
  const links = [];
  const modules = join(artifacts, 'node_modules');
  await mkdir(modules);
  for (const name of [...requested].sort()) {
    assert.match(name, /^(?:@[a-z0-9._-]+\/)?[a-z0-9._-]+$/u, 'Invalid dependency package name');
    assert.ok(!name.split('/').some(part => part === '.' || part === '..'), 'Dependency names cannot traverse directories');
    if (provided.has(name)) {
      const entry = provided.get(name);
      assert.ok(entry.version, `${name}: installed runtime must declare its version`);
      peers[name] = entry.version;
      continue;
    }
    const localName = name.startsWith('@dsh-selfuse/') ? name.slice('@dsh-selfuse/'.length) : undefined;
    let target;
    if (localName !== undefined) {
      assert.ok(deploymentPackages.includes(localName), `${name}: required selfuse package is not deployed`);
      target = join(artifacts, localName);
    } else {
      target = await realpath(join(profile, 'node_modules', name));
      const profileModules = await realpath(join(profile, 'node_modules'));
      assert.ok(target.startsWith(profileModules + '\\'), `${name}: dependency must belong to this Windows profile`);
    }
    const destination = join(modules, name);
    await mkdir(join(destination, '..'), { recursive: true });
    await symlink(target, destination, 'junction');
    assert.equal(await realpath(destination), await realpath(target), `${name}: dependency link readback`);
    links.push({ name, target });
  }
  const manifest = { name: 'dsh-selfuse-desktop-deployment', private: true, peerDependencies: peers };
  await writeFile(join(artifacts, 'package.json'), JSON.stringify(manifest, null, 2) + '\n');
  await writeFile(join(artifacts, 'runtime-dependencies.json'), JSON.stringify({ peers, links }, null, 2) + '\n');
  return { peers, links };
}

/** Noninteractive child commands receive EOF, not an indefinitely open input pipe. */
export function executeWithClosedInput(runner, command, args, options) {
  return runner(command, args, { ...options, stdin: 'ignore', killDescendants: true });
}

/** Retain user configuration verbatim, inserting only missing ordinary plugins. */
export function extendPatch(text, parse, stringify) {
  const document = parse(text);
  assert.ok(Array.isArray(document), 'Desktop patch must be a YAML sequence');
  const inserted = new Set();
  function visit(rows) {
    for (const row of rows) {
      assert.ok(row && typeof row === 'object' && !Array.isArray(row), 'Patch rows must be objects');
      if (typeof row.name === 'string') inserted.add(row.name);
      if (row.insert !== undefined) {
        assert.ok(Array.isArray(row.insert), 'insert must be a sequence');
        visit(row.insert);
      }
    }
  }
  visit(document);
  const missing = manualRows.filter(name => !inserted.has(`@dsh-selfuse/${name}`));
  if (missing.length === 0) return text;
  const addition = stringify([{ insert: missing.map(name => ({ id: name, name: `@dsh-selfuse/${name}` })) }]);
  const result = addition + '\n' + text;
  assert.deepEqual(parse(result).slice(1), document, 'Existing YAML configuration must be unchanged');
  return result;
}

/** Reject shell metacharacters before constructing the official Windows CLI invocation. */
export function cliCommand(cli, args) {
  const values = [cli, ...args];
  for (const value of values) {
    assert.equal(typeof value, 'string');
    assert.ok(value.length > 0 && !/[\r\n"&|<>^%!?]/u.test(value), 'Unsafe CLI argument');
  }
  return `"${values.map(value => `"${value}"`).join(' ')}"`;
}

async function existing(path) {
  try { return await stat(path); }
  catch (error) { if (error.code === 'ENOENT') return undefined; throw error; }
}

async function desktopStopped() {
  const command = `@(Get-CimInstance Win32_Process -Filter "Name = 'DeepSeek Harness.exe'" | Where-Object { $_.ProcessId -ne ${process.pid} }).Count`;
  const { stdout } = await execute('powershell.exe', ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(command, 'utf16le').toString('base64')], { windowsHide: true });
  assert.equal(stdout.trim(), '0', 'Normally exit Desktop before installing plugins; no processes are forcibly stopped');
}

async function main() {
  assert.equal(process.platform, 'win32', 'Run with the installed Windows Electron runtime');
  const options = {};
  let apply = false;
  for (let index = 2; index < process.argv.length; index++) {
    const key = process.argv[index];
    if (key === '--apply') { apply = true; continue; }
    assert.ok(['--source', '--install', '--artifacts', '--home'].includes(key), `Unknown option: ${key}`);
    assert.ok(process.argv[index + 1] && !process.argv[index + 1].startsWith('--'), `${key} needs a value`);
    options[key.slice(2)] = resolve(process.argv[++index]);
  }
  const source = options.source ?? resolve(import.meta.dirname, '../vendor/deepseek-harness');
  const installation = options.install ?? 'F:/Apps/DeepSeekHarness';
  const home = options.home ?? join(process.env.USERPROFILE, '.dsh');
  const artifacts = options.artifacts ?? `F:/Apps/DeepSeekHarnessPlugins/selfuse-${new Date().toISOString().replace(/[:.]/gu, '-')}`;
  assert.ok(basename(artifacts).startsWith('selfuse-'), 'Use a new, dedicated selfuse-* artifact directory');
  assert.equal(await existing(artifacts), undefined, 'Never overwrite an existing deployment or backup');
  const profile = join(home, 'profiles/desktop');
  const cli = join(installation, 'resources/runtime/cli/bin/dsh.cmd');
  const anchor = join(installation, 'resources/app.asar/dsh/node_modules/@deepseek-ai/dsh/package.json');
  const installedRequire = createRequire(anchor);
  const yaml = installedRequire('yaml');
  const { execa } = installedRequire('execa');
  const appVersion = JSON.parse(await readFile(join(installation, 'resources/app.asar/package.json'), 'utf8')).version;
  assert.equal(appVersion, '0.2.0-rc.2', 'This deployment was validated for official Desktop rc.2 only');
  assert.ok(await existing(cli), 'Official bundled CLI is missing');
  const originalPatch = await readFile(join(profile, 'cordis.patch.yml'), 'utf8');
  const newPatch = extendPatch(originalPatch, yaml.parse, yaml.stringify);
  for (const name of packages) {
    const directory = join(source, 'packages/selfuse', name);
    const manifest = JSON.parse(await readFile(join(directory, 'package.json'), 'utf8'));
    assert.equal(manifest.name, `@dsh-selfuse/${name}`);
    assert.ok(await existing(join(directory, 'lib/index.js')), `${name}: build the candidate before deployment`);
    cliCommand(cli, ['plugin', '--profile', 'desktop', 'add', `link:${join(artifacts, name).replaceAll('\\', '/')}`]);
  }
  await desktopStopped();
  console.log(JSON.stringify({ mode: apply ? 'install' : 'plan', version: appVersion, source, home, artifacts, packages, changes: 'Native CLI dependencies plus two ordinary plugin rows; no user settings or session rewrite' }, null, 2));
  if (!apply) return;

  await mkdir(artifacts, { recursive: true });
  const identityCommand = '[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value';
  const identity = await execute('powershell.exe', ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(identityCommand, 'utf16le').toString('base64')], { windowsHide: true });
  assert.match(identity.stdout.trim(), /^S-1-5-[\d-]+$/u);
  await execute('icacls.exe', [artifacts, '/inheritance:r', '/grant:r', `*${identity.stdout.trim()}:(OI)(CI)F`, '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F'], { windowsHide: true });
  const backup = join(artifacts, '_profile-before');
  await mkdir(backup);
  const saved = {};
  for (const filename of configFiles) {
    const path = join(profile, filename);
    if (!(await existing(path))) { saved[filename] = { existed: false }; continue; }
    const bytes = await readFile(path);
    await cp(path, join(backup, filename));
    saved[filename] = { existed: true, sha256: digest(bytes) };
    assert.equal(digest(await readFile(join(backup, filename))), saved[filename].sha256);
  }
  await writeFile(join(backup, 'manifest.json'), JSON.stringify(saved, null, 2));
  for (const name of packages) {
    const directory = join(artifacts, name);
    await mkdir(directory);
    for (const filename of payload) {
      const origin = join(source, 'packages/selfuse', name, filename);
      if (await existing(origin)) await cp(origin, join(directory, filename), { recursive: true });
    }
  }
  const workspacePath = join(profile, 'pnpm-workspace.yaml');
  const workspace = await existing(workspacePath) ? yaml.parse(await readFile(workspacePath, 'utf8')) : {};
  assert.ok(workspace && typeof workspace === 'object' && !Array.isArray(workspace), 'Invalid profile workspace config');
  await writeFile(workspacePath, yaml.stringify({ ...workspace, nodeLinker: 'hoisted', autoInstallPeers: false, allowBuilds: workspace.allowBuilds ?? {} }));
  const installed = [];
  try {
    for (const name of packages) {
      const args = ['plugin', '--profile', 'desktop', 'add', `link:${join(artifacts, name).replaceAll('\\', '/')}`];
      const output = await executeWithClosedInput(execa, 'cmd.exe', ['/d', '/s', '/c', cliCommand(cli, args)], { cwd: profile, env: { ...process.env, DSH_HOME: home }, timeout: 120_000, maxBuffer: 16 * 1024 * 1024, windowsHide: true, windowsVerbatimArguments: true });
      await writeFile(join(artifacts, `${name}.stdout.log`), output.stdout);
      await writeFile(join(artifacts, `${name}.stderr.log`), output.stderr);
      installed.push(name);
    }
    const args = ['plugin', '--profile', 'desktop', 'add', 'jpeg-js@0.4.4', 'lightningcss@1.32.0', 'yaml@2.9.0'];
    const output = await executeWithClosedInput(execa, 'cmd.exe', ['/d', '/s', '/c', cliCommand(cli, args)], { cwd: profile, env: { ...process.env, DSH_HOME: home }, timeout: 120_000, maxBuffer: 16 * 1024 * 1024, windowsHide: true, windowsVerbatimArguments: true });
    await writeFile(join(artifacts, 'runtime-dependencies.stdout.log'), output.stdout);
    await writeFile(join(artifacts, 'runtime-dependencies.stderr.log'), output.stderr);
    await desktopStopped();
    assert.equal(await readFile(join(profile, 'cordis.patch.yml'), 'utf8'), originalPatch, 'Profile patch changed during installation; do not overwrite it');
    await writeFile(join(profile, 'cordis.patch.yml'), newPatch);
    const { loadProfileDirectory, createRuntimeResolution } = await import(pathToFileURL(installedRequire.resolve('@deepseek-ai/dsh-app-boot')).href);
    const composition = loadProfileDirectory('dsh', profile, anchor);
    assert.deepEqual(composition.skippedBundles, [], 'Every selected bundle must resolve');
    const runtime = await createRuntimeResolution({ installAnchor: anchor, profile: composition, home });
    await connectRuntimeDependencies(artifacts, profile, runtime.entries);
    await writeFile(join(artifacts, 'installation.json'), JSON.stringify({ version: appVersion, source, profile, artifacts, installed, backup, layers: composition.layers.map(layer => layer.packageName), acceptance: 'CLI installation and profile composition only; Host and GUI need separate acceptance' }, null, 2));
    console.log(`Installed ${installed.length} packages; reversible profile backup: ${backup}`);
  } catch (error) {
    await writeFile(join(artifacts, 'installation-failed.json'), JSON.stringify({ installed, backup, error: String(error.message ?? error) }, null, 2));
    throw error;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) await main();
