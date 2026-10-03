/** Scoped, backed-up mode change for the existing native Desktop link deployment. */
import assert from 'node:assert/strict';
import { readFile, writeFile, cp, mkdir, mkdtemp, rename } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { join, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { isDeepStrictEqual, promisify } from 'node:util';
import { execFile } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { stopped } from './desktop-remote.mjs';
import { validateConfig } from '../plugins/desktop-remote/index.mjs';

export function setModePatch(text, mode, yaml, ownerLogin) {
  assert.ok(['tailnet', 'owner-browser'].includes(mode));
  const doc = yaml.parseDocument(text);
  assert.equal(doc.errors.length, 0, 'Invalid profile patch');
  const before = doc.toJS();
  assert.ok(Array.isArray(before));
  const paths = [];
  before.forEach((row, index) => {
    if (row.id === 'desktop-remote') paths.push([index]);
    row.insert?.forEach((child, childIndex) => { if (child.id === 'desktop-remote') paths.push([index, 'insert', childIndex]); });
  });
  assert.equal(paths.length, 1, 'Expected one installed remote extension');
  const path = paths[0];
  let target = before;
  for (const key of path) target = target[key];
  assert.equal(target.name, '@dsh-selfuse/desktop-remote');
  const amended = { ...target.config, authorizationMode: mode };
  if (mode === 'tailnet') delete amended.ownerLogin;
  else amended.ownerLogin = ownerLogin;
  validateConfig(amended);
  doc.setIn([...path, 'config', 'authorizationMode'], mode);
  if (mode === 'tailnet') doc.deleteIn([...path, 'config', 'ownerLogin']);
  else doc.setIn([...path, 'config', 'ownerLogin'], ownerLogin);
  const expected = structuredClone(before);
  let expectedTarget = expected;
  for (const key of path) expectedTarget = expectedTarget[key];
  expectedTarget.config = amended;
  assert.ok(isDeepStrictEqual(doc.toJS(), expected), 'Unrelated profile patch content changed');
  return { text: doc.toString(), config: amended };
}

async function main() {
  assert.equal(process.env.ELECTRON_RUN_AS_NODE, '1');
  const mode = process.argv[2];
  assert.ok(['tailnet', 'owner-browser'].includes(mode), 'Choose tailnet or owner-browser explicitly');
  await stopped();
  const root = 'F:/Apps/DeepSeekHarnessRemote';
  const anchor = 'F:/Apps/DeepSeekHarness/resources/app.asar/dsh/node_modules/@deepseek-ai/dsh/package.json';
  const require = createRequire(anchor);
  const yaml = require('yaml');
  assert.equal(JSON.parse(await readFile(anchor, 'utf8')).version, '0.2.0-rc.2');
  const installation = JSON.parse(await readFile(join(root, 'installation.json'), 'utf8'));
  const profile = installation.profile;
  assert.equal(resolve(profile), resolve('C:/Users/HuangZY/.dsh/profiles/desktop'));
  const execute = promisify(execFile);
  let ownerLogin;
  if (mode === 'owner-browser') {
    const status = JSON.parse((await execute('C:/Program Files/Tailscale/tailscale.exe', ['status', '--json'], { windowsHide: true })).stdout);
    ownerLogin = status.User[String(status.Self.UserID)]?.LoginName;
  }
  const patchPath = join(profile, 'cordis.patch.yml');
  const amended = setModePatch(await readFile(patchPath, 'utf8'), mode, yaml, ownerLogin);
  const files = ['package.json', 'cordis.yml', 'cordis.patch.yml', 'pnpm-lock.yaml', 'pnpm-workspace.yaml'];
  const digest = value => createHash('sha256').update(value).digest('hex');
  const before = Object.fromEntries(await Promise.all(files.map(async file => [file, digest(await readFile(join(profile, file)))])));
  const backup = await mkdtemp(join(root, 'mode-before-'));
  await mkdir(join(backup, 'profile'));
  await cp(join(root, 'plugin'), join(backup, 'plugin'), { recursive: true });
  for (const file of files) {
    await cp(join(profile, file), join(backup, 'profile', file));
    assert.equal(digest(await readFile(join(backup, 'profile', file))), before[file]);
  }
  await cp(join(root, 'private-config.json'), join(backup, 'private-config.json'));
  await writeFile(join(backup, 'manifest.json'), JSON.stringify({ profile, before }, null, 2));
  const payload = ['index.mjs', 'native-auth.mjs', 'package.json', 'test.mjs', 'tailnet.test.mjs', 'README.md'];
  for (const file of payload) {
    const source = join(import.meta.dirname, '../plugins/desktop-remote', file);
    const target = join(root, 'plugin', file);
    await cp(source, target);
    assert.equal(digest(await readFile(source)), digest(await readFile(target)), 'Payload hash mismatch');
  }
  await stopped();
  assert.equal(digest(await readFile(patchPath)), before['cordis.patch.yml'], 'Profile changed while stopped');
  await writeFile(patchPath + '.remote-mode.tmp', amended.text);
  await rename(patchPath + '.remote-mode.tmp', patchPath);
  await writeFile(join(root, 'private-config.json'), JSON.stringify(validateConfig(amended.config), null, 2));
  for (const file of files.filter(file => file !== 'cordis.patch.yml')) assert.equal(digest(await readFile(join(profile, file))), before[file]);
  const record = { mode, backup, version: JSON.parse(await readFile(join(root, 'plugin/package.json'), 'utf8')).version,
    coreProfileFilesUnchanged: 4, onlyRemotePatchFieldsChanged: true, payloadHashMatched: true,
    acceptance: 'Configuration delivery only; fresh runtime, HTTPS and actual mobile checks remain required' };
  await writeFile(join(root, 'mode-change.json'), JSON.stringify(record, null, 2));
  console.log(JSON.stringify(record, null, 2));
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
