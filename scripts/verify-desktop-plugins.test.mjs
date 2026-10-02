import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { test } from 'node:test';
import { expectedClients, expectedHosts, verifyDesktopPlugins } from './verify-desktop-plugins.mjs';

async function fixture(options, inspect) {
  const entries = expectedClients.filter(name => name !== options.missingClient).map(id => ({ id, url: `plugins/${id}/client.js` }));
  const hosts = expectedHosts.map(moduleName => ({ moduleName, enabled: true, fiberPhase: moduleName === options.failedHost ? null : 'active' }));
  const calls = [];
  const server = createServer((request, response) => {
    calls.push({ path: request.url, method: request.method });
    if (request.url === '/?canary=1') { response.writeHead(303, { 'set-cookie': 'fixture=test; HttpOnly', location: '/' }); response.end(); return; }
    if (request.headers.cookie !== 'fixture=test') { response.writeHead(401); response.end(); return; }
    if (request.url === '/') { response.end(`<script>globalThis["__DSH_BOOT__"] = ${JSON.stringify({ entries })}</script>`); return; }
    if (request.url === '/api/pluginInventory/list') {
      let body = '';
      request.on('data', data => { body += data; });
      request.on('end', () => {
        const message = JSON.parse(body);
        assert.equal(message.method, 'pluginInventory/list');
        assert.deepEqual(message.payload, { args: {} });
        response.setHeader('content-type', 'application/json');
        response.end(JSON.stringify({ rpcId: options.staleResponse ? 'stale' : message.rpcId, result: { ok: true, value: { entries: hosts } } }));
      });
      return;
    }
    if (request.url.startsWith('/plugins/')) { response.end('globalThis.__ModuleLoader__.load({id:"fixture",factory(){}});'); return; }
    response.writeHead(404); response.end();
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try { await inspect(`http://127.0.0.1:${server.address().port}/?canary=1`, calls); }
  finally { await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve())); }
}

test('checks live Host activation and every advertised Client bundle using only read-only operations', async () => {
  await fixture({}, async (url, calls) => {
    const result = await verifyDesktopPlugins(url);
    assert.deepEqual(result.hosts, expectedHosts);
    assert.deepEqual(result.clients, expectedClients);
    assert.equal(calls.filter(call => call.method === 'POST').length, 1);
    assert.equal(calls.filter(call => call.path.startsWith('/plugins/')).length, 5);
    assert.ok(!JSON.stringify(result).includes('canary'));
  });
});

test('a declared plugin without an active fiber fails acceptance', async () => {
  await fixture({ failedHost: '@dsh-selfuse/backup' }, async url => {
    await assert.rejects(verifyDesktopPlugins(url), /backup: Host entry did not activate/u);
  });
});

test('active Host entries without a Client graph row fail acceptance', async () => {
  await fixture({ missingClient: '@dsh-selfuse/memory-panel' }, async url => {
    await assert.rejects(verifyDesktopPlugins(url), /memory-panel: expected one served Client row/u);
  });
});

test('remote URLs are rejected before sending credentials', async () => {
  for (const url of ['https://example.test/?token=canary', 'http://localhost:8080/', 'file:///F:/test', 'http://user:pass@127.0.0.1:8080/']) {
    await assert.rejects(verifyDesktopPlugins(url), /local Desktop endpoint/u);
  }
});

test('an unrelated cached inventory response fails correlation', async () => {
  await fixture({ staleResponse: true }, async url => {
    await assert.rejects(verifyDesktopPlugins(url), /does not match/u);
  });
});
