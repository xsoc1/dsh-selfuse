/** Manager publication preflight: candidate metadata/links/syntax and bounded sensitive-content checks. */
import assert from 'node:assert/strict';
import { readFile, lstat } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { resolve, dirname, extname } from 'node:path';
import { validateConfig } from '../plugins/desktop-remote/index.mjs';

const git = (...args) => execFileSync('D:/Git/cmd/git.exe', args, { encoding: 'utf8', windowsHide: true }).trim();
const staged = process.argv.includes('--staged');
const files = [...new Set((staged ? git('diff', '--cached', '--name-only', '--diff-filter=AM')
  : git('diff', 'HEAD', '--name-only', '--diff-filter=AM') + '\n' + git('ls-files', '--others', '--exclude-standard')).split('\n').filter(Boolean))];
assert.ok(files.length > 0, 'No publication candidate');
const state = JSON.parse(await readFile('F:/Apps/DeepSeekHarnessRemote/state/connection.json', 'utf8'));
const tail = JSON.parse(execFileSync('C:/Program Files/Tailscale/tailscale.exe', ['status', '--json'], { encoding: 'utf8', windowsHide: true, timeout: 10000 }));
const privateValues = [new URL(state.publicUrl).hostname, state.loginUrl, ...Object.values(tail.User ?? {}).map(user => user.LoginName),
  ...Object.values(tail.Peer ?? {}).flatMap(peer => peer.TailscaleIPs ?? []), ...(tail.Self?.TailscaleIPs ?? [])].filter(value => value?.length > 5);
const hits = [];
const slug = value => value.replace(/<[^>]*>/gu, '').replace(/[^\p{L}\p{N}_ -]/gu, '').toLowerCase().replaceAll(' ', '-');
let links = 0;
let scripts = 0;
for (const file of files) {
  const info = await lstat(file);
  assert.ok(info.isFile() && !info.isSymbolicLink(), 'Only regular source files can be published: ' + file);
  assert.ok(!/\.(?:log|token|secret|png|zip|exe|asar)$/iu.test(file), 'Runtime/binary candidate: ' + file);
  const text = await readFile(file, 'utf8');
  if (privateValues.some(value => text.includes(value))) hits.push({ file, category: 'actual-runtime-identity-or-address' });
  for (const [category, pattern] of [
    ['provider-token', /\b(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[A-Za-z0-9_-]{25,})\b/u],
    ['credential-url', /https?:\/\/[^\s/'"]+:[^\s/'"]+@/u],
    ['literal-launch-token', /[?&]token=[A-Za-z0-9._-]{24,}/u],
    ['literal-native-cookie', /dsh-auth-[A-Za-z0-9_-]+=v1\.[A-Za-z0-9_-]{24,}\.[A-Za-z0-9_-]{24,}/u],
    ['private-key', /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/u],
  ]) if (pattern.test(text)) hits.push({ file, category });
  if (extname(file) === '.json') JSON.parse(text);
  if (extname(file) === '.mjs') {
    execFileSync(process.execPath, ['--check', resolve(file)], { windowsHide: true, stdio: 'pipe' }); scripts++;
  }
  if (extname(file) === '.md') {
    const prose = text.replace(/```[\s\S]*?```/gu, '');
    const targets = [...prose.matchAll(/\[[^\]\n]*\]\(([^)]+)\)/gu)].map(match => match[1]);
    targets.push(...[...prose.matchAll(/^\[[^\]\n]+\]:\s*(\S+)/gmu)].map(match => match[1]));
    for (const raw of targets) {
      const target = raw.replace(/^<|>$/gu, '');
      if (/^(?:[a-z][a-z0-9+.-]*:|\/)/iu.test(target)) continue;
      const [path, anchor] = target.split('#');
      const destination = path ? resolve(dirname(file), decodeURIComponent(path)) : resolve(file);
      assert.ok((await lstat(destination)).isFile(), 'Missing linked file in ' + file);
      if (anchor && extname(destination) === '.md') {
        const content = await readFile(destination, 'utf8');
        const headings = [...content.matchAll(/^#{1,6}\s+(.+)$/gmu)].map(match => slug(match[1].trim()));
        assert.ok(headings.includes(decodeURIComponent(anchor)), 'Missing heading anchor in ' + file + ': ' + anchor);
      }
      links++;
    }
  }
}
console.log(JSON.stringify({ files: files.length, links, syntaxChecked: scripts, sensitiveHits: hits }));
assert.equal(hits.length, 0, 'Sensitive candidate content requires manual review; no raw values printed');
const manifest = JSON.parse(await readFile('manifest.json', 'utf8'));
const schema = JSON.parse(await readFile('docs/manifest.schema.json', 'utf8'));
for (const key of schema.required) assert.ok(key in manifest, 'Missing manifest field: ' + key);
for (const row of manifest.components) {
  const item = schema.properties.components.items;
  for (const key of item.required) assert.ok(key in row, 'Missing component field: ' + key);
  for (const [key, spec] of Object.entries(item.properties)) if (spec.enum && key in row) assert.ok(spec.enum.includes(row[key]), 'Invalid component enum: ' + key);
}
const example = validateConfig(JSON.parse(await readFile('config/remote/desktop-relay.example.json', 'utf8')));
assert.equal(example.authorizationMode, 'tailnet');
assert.equal(example.ownerLogin, undefined);
console.log('Manifest required fields/enums and explicit tailnet example passed; pattern scan is not a complete security guarantee.');
