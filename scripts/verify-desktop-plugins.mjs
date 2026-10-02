import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export const expectedHosts = Object.freeze(['backup', 'memory-panel', 'soul-md', 'git-workflow', 'web-ui-git-graph', 'skin-layout-compat', 'skin-center', 'task-notify', 'content-risk-guard'].map(name => `@dsh-selfuse/${name}`));
export const expectedClients = Object.freeze(['backup', 'memory-panel', 'web-ui-git-graph', 'skin-layout-compat', 'skin-center'].map(name => `@dsh-selfuse/${name}`));

/** Read active Host fibers, served Client registrations and their bundle resources.
 * Only read-only RPC and GET requests are issued; credentials never enter reports.
 * This does not claim GUI rendering or model acceptance.
 */
export async function verifyDesktopPlugins(loginAddress) {
  const address = new URL(loginAddress);
  assert.ok(address.protocol === 'http:' && address.hostname === '127.0.0.1' && address.port && !address.username && !address.password, 'Only an authenticated local Desktop endpoint is allowed');
  const login = await fetch(address, { redirect: 'manual', signal: AbortSignal.timeout(10000) });
  assert.ok(login.status === 200 || login.status === 303, 'Desktop authentication failed');
  const cookie = login.headers.getSetCookie().map(value => value.split(';')[0]).join('; ');
  const request = (path, init = {}) => fetch(new URL(path, address.origin), { ...init, headers: { cookie, ...init.headers }, signal: AbortSignal.timeout(10000) });
  const page = await request('/');
  assert.equal(page.status, 200, 'Desktop page is unavailable');
  const graphText = (await page.text()).match(/globalThis\["__DSH_BOOT__"\]\s*=\s*(\{[^<]+?\})<\/script>/)?.[1];
  assert.ok(graphText, 'Desktop page has no Client graph');
  const graph = JSON.parse(graphText);
  assert.ok(Array.isArray(graph.entries), 'Invalid Client graph');
  const rpcId = randomUUID();
  const response = await request('/api/pluginInventory/list', { method: 'POST', headers: { 'content-type': 'application/json', origin: address.origin }, body: JSON.stringify({ type: 'client-request', rpcId, method: 'pluginInventory/list', payload: { args: {} } }) });
  assert.equal(response.status, 200, 'Host inventory is unavailable');
  const inventory = await response.json();
  assert.equal(inventory.rpcId, rpcId, 'Host inventory response does not match this request');
  assert.equal(inventory.result?.ok, true, 'Host inventory RPC failed');
  assert.ok(Array.isArray(inventory.result.value.entries), 'Invalid Host inventory');
  for (const name of expectedHosts) {
    const rows = inventory.result.value.entries.filter(row => row.moduleName === name);
    assert.equal(rows.length, 1, `${name}: expected one Host entry`);
    assert.equal(rows[0].enabled, true, `${name}: Host entry is disabled; user choices were not changed`);
    assert.equal(rows[0].fiberPhase, 'active', `${name}: Host entry did not activate`);
  }
  for (const name of expectedClients) {
    const rows = graph.entries.filter(row => row.id === name);
    assert.equal(rows.length, 1, `${name}: expected one served Client row`);
    const resource = new URL(rows[0].url, address.origin + '/');
    assert.equal(resource.origin, address.origin, 'Client resources must stay on the local Host');
    assert.ok(resource.pathname.startsWith('/plugins/'), 'Client resource is outside the plugin route');
    const bundle = await request(resource.pathname + resource.search);
    assert.equal(bundle.status, 200, `${name}: Client bundle is unavailable`);
    assert.ok((await bundle.text()).includes('__ModuleLoader__'), `${name}: Client bundle lacks a registration factory`);
  }
  return { hosts: expectedHosts, clients: expectedClients, acceptance: 'Active Host entries and served Client bundles only; GUI and model acceptance remain separate' };
}

async function main() {
  assert.equal(process.argv[2], '--log', 'Supply --log with the current persistent Desktop stdout file');
  assert.equal(process.argv.length, 4, 'Only --log is supported');
  const log = await readFile(process.argv[3], 'utf8');
  const addresses = [...log.matchAll(/http:\/\/127\.0\.0\.1:\d+[^\s\x1b]*/gu)];
  assert.ok(addresses.length, 'No authenticated local URL in the current startup log');
  console.log(JSON.stringify(await verifyDesktopPlugins(addresses.at(-1)[0]), null, 2));
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) await main();
