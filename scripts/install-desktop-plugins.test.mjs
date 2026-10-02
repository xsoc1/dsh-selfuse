import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { mkdir, mkdtemp, readFile, realpath, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { cliCommand, connectRuntimeDependencies, executeWithClosedInput, extendPatch, packages } from './install-desktop-plugins.mjs';

const installedRequire = createRequire('F:/Apps/DeepSeekHarness/resources/app.asar/dsh/node_modules/@deepseek-ai/dsh/package.json');
const yaml = installedRequire('yaml');
const { execa } = installedRequire('execa');

async function dependencyFixture(dependencies) {
  const root = await mkdtemp('F:/tools/dsh-retired-20261001/completion-final/dependency-test-');
  const artifacts = join(root, 'selfuse-artifacts');
  const profile = join(root, 'profiles/desktop');
  await mkdir(join(artifacts, 'consumer'), { recursive: true });
  await mkdir(join(artifacts, 'helper'));
  await mkdir(join(profile, 'node_modules/local-runtime'), { recursive: true });
  await writeFile(join(profile, 'node_modules/local-runtime/package.json'), JSON.stringify({ name: 'local-runtime', version: '1.0.0' }));
  await writeFile(join(artifacts, 'consumer/package.json'), JSON.stringify({ dependencies }));
  await writeFile(join(artifacts, 'helper/package.json'), '{}');
  return { artifacts, profile };
}

test('external F-drive deployment uses in-box peers and exact native dependency links', async () => {
  const { artifacts, profile } = await dependencyFixture({ '@deepseek-ai/schemastery': 'workspace:~', '@dsh-selfuse/helper': 'workspace:~', 'local-runtime': '1.0.0' });
  const result = await connectRuntimeDependencies(artifacts, profile, [{ name: '@deepseek-ai/schemastery', scope: 'installation', version: '3.18.4' }], ['consumer', 'helper']);
  assert.deepEqual(result.peers, { '@deepseek-ai/schemastery': '3.18.4' });
  assert.equal(await realpath(join(artifacts, 'node_modules/@dsh-selfuse/helper')), await realpath(join(artifacts, 'helper')));
  assert.equal(await realpath(join(artifacts, 'node_modules/local-runtime')), await realpath(join(profile, 'node_modules/local-runtime')));
  const manifest = JSON.parse(await readFile(join(artifacts, 'package.json'), 'utf8'));
  assert.deepEqual(manifest.peerDependencies, result.peers);
  await assert.rejects(connectRuntimeDependencies(artifacts, profile, [], ['consumer', 'helper']), /existing deployment manifest/u);
});

test('a missing required local helper fails instead of silently omitting it', async () => {
  const { artifacts, profile } = await dependencyFixture({ '@dsh-selfuse/missing': 'workspace:~' });
  await assert.rejects(connectRuntimeDependencies(artifacts, profile, [], ['consumer']), /not deployed/u);
});

test('a missing native dependency and a directory traversal request both fail', async () => {
  for (const dependency of ['missing-runtime', '..']) {
    const { artifacts, profile } = await dependencyFixture({ [dependency]: '1.0.0' });
    await assert.rejects(connectRuntimeDependencies(artifacts, profile, [], ['consumer']), /ENOENT|traverse/u);
  }
});
test('keeps all prior configuration and comments while inserting the two missing plugins', () => {
  const prior = '# User comments stay\r\n- id: webserver\r\n  config: {port: 0}\r\n- id: agent-default-model\r\n  config: {model: private-choice}\r\n';
  const output = extendPatch(prior, yaml.parse, yaml.stringify);
  assert.ok(output.endsWith(prior));
  assert.deepEqual(yaml.parse(output).slice(1), yaml.parse(prior));
  assert.deepEqual(yaml.parse(output)[0].insert.map(row => row.name), ['@dsh-selfuse/task-notify', '@dsh-selfuse/content-risk-guard']);
});
test('existing rows and disabled user choices are not duplicated or overwritten', () => {
  const prior = '- insert:\n  - id: custom-name\n    name: "@dsh-selfuse/task-notify"\n    disabled: true\n  - id: content-risk-guard\n    name: "@dsh-selfuse/content-risk-guard"\n';
  assert.equal(extendPatch(prior, yaml.parse, yaml.stringify), prior);
});
test('adds only the missing row, even when the existing plugin is nested', () => {
  const prior = '- insert:\n  - insert:\n    - id: notice\n      name: "@dsh-selfuse/task-notify"\n';
  const output = extendPatch(prior, yaml.parse, yaml.stringify);
  assert.equal(yaml.parse(output)[0].insert.length, 1);
  assert.equal(yaml.parse(output)[0].insert[0].name, '@dsh-selfuse/content-risk-guard');
});
test('rejects malformed YAML or non-sequence insert before writing', () => {
  for (const input of ['{}', 'null', '- bad-string', '- insert: {}', 'a: [']) assert.throws(() => extendPatch(input, yaml.parse, yaml.stringify));
});
test('CLI arguments with spaces remain quoted', () => {
  assert.equal(cliCommand('F:\\Apps\\DeepSeekHarness\\dsh.cmd', ['plugin', 'link:F:/path with spaces']), '""F:\\Apps\\DeepSeekHarness\\dsh.cmd" "plugin" "link:F:/path with spaces""');
});
test('rejects shell injection characters and empty arguments', () => {
  for (const value of ['', 'x&y', 'x|y', '%PATH%', '!x!', 'a"b', 'x\ny', 'x^y', 'x>y']) assert.throws(() => cliCommand('dsh.cmd', [value]));
});
test('retired features cannot enter the explicit deployment set', () => {
  assert.equal(packages.length, 10);
  for (const name of ['undo', 'wsl-workspace', 'remote-web-ui', 'control-gui', 'web-ui-settings', 'ssh', 'web-ui-task-board', 'mineru']) assert.ok(!packages.includes(name));
});
test('the real executable entry point runs preflight and rejects a missing source', () => {
  const result = spawnSync(process.execPath, [fileURLToPath(new URL('./install-desktop-plugins.mjs', import.meta.url)), '--source', 'F:/dsh-test-source-that-does-not-exist'], {
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' }, encoding: 'utf8', windowsHide: true,
  });
  assert.notEqual(result.status, 0, 'The executable must not silently skip main()');
  assert.match(result.stderr, /ENOENT|missing/iu);
});
test('noninteractive children receive input EOF and actually exit', async () => {
  const result = await executeWithClosedInput(execa, process.execPath, ['-e', 'process.stdin.on("end",()=>console.log("EOF_RECEIVED"));process.stdin.resume()'], {
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' }, timeout: 5000, windowsHide: true,
  });
  assert.equal(result.stdout.trim(), 'EOF_RECEIVED');
});
test('cancelled installation children dispose their owned descendants before rejection', { timeout: 20000 }, async () => {
  const controller = new AbortController();
  const childCode = 'console.log("CHILD_READY:"+process.pid);setInterval(()=>{},1000)';
  const parentCode = `require('node:child_process').spawn(process.execPath,['-e',${JSON.stringify(childCode)}],{stdio:['ignore','inherit','inherit'],env:process.env});setInterval(()=>{},1000)`;
  const child = executeWithClosedInput(execa, process.execPath, ['-e', parentCode], {
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' }, windowsHide: true, cancelSignal: controller.signal,
  });
  // Observe readiness before cancelling; time only bounds a stuck fixture.
  const settled = child.then(value => ({ value }), error => ({ error }));
  let childPid;
  try {
    const ready = await new Promise((accept, reject) => {
      const timer = setTimeout(() => reject(new Error('Child readiness deadline exceeded')), 15000);
      child.stdout.on('data', data => {
        const match = /CHILD_READY:(\d+)/u.exec(String(data));
        if (match) { clearTimeout(timer); accept(Number(match[1])); }
      });
      settled.then(() => { clearTimeout(timer); reject(new Error('Parent exited before child readiness')); });
    });
    childPid = ready;
    controller.abort();
    const outcome = await settled;
    assert.ok(outcome.error?.isCanceled, 'Cancellation must be reported, not disguised as an exit status');
    assert.throws(() => process.kill(childPid, 0), { code: 'ESRCH' }, 'Awaited teardown must leave no live descendant');
  } finally {
    controller.abort();
    await settled;
  }
});
