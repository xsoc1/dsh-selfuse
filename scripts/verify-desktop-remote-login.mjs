/** Real Chrome first-login check; external handoff is synthetic, not a Lens test. */
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { request as httpRequest } from 'node:http';
import { createRelay } from '../plugins/desktop-remote/index.mjs';

const statePath = process.argv.slice(2).find(arg => !arg.startsWith('--')) ?? 'F:/Apps/DeepSeekHarnessRemote/state/connection.json';
const state = JSON.parse(await readFile(statePath, 'utf8'));
const tailnetMode = state.authorizationMode === 'tailnet';
const entry = tailnetMode ? state.publicUrl : state.loginUrl;
assert.ok(!(tailnetMode && process.argv.includes('--source-relay')), 'Use isolated --tailnet native installation to check source mode before deployment');
const require = createRequire(import.meta.url);
const { chromium } = require('//wsl.localhost/Ubuntu/home/huangzy/tools/deepseek-harness-upgrade-20260929/node_modules/.pnpm/playwright-core@1.61.1/node_modules/playwright-core/index.js');
const browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
const report = { cases: [], limitations: ['Synthetic external link navigation in Windows Chrome; actual Android Lens/Chrome remains a separate check.'] };
const sourceRelay = process.argv.includes('--source-relay') ? await createRelay({ publicUrl: state.publicUrl, ownerLogin: 'isolated-browser-test', relayPort: 0 }, () => state.targetPort) : undefined;
if (sourceRelay) report.limitations.push('First document goes through temporary source relay and browser routing; active Tailscale Serve and installed relay are unchanged.');
const htmlEscape = value => value.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');
try {
  const anonymous = await fetch(state.publicUrl, { signal: AbortSignal.timeout(10000) });
  const anonymousText = await anonymous.text();
  assert.equal(anonymous.status, tailnetMode ? 200 : 401);
  report.anonymousMatchesReportedError = /DSH web authentication required/iu.test(anonymousText);
  for (const mode of ['direct', 'external-link']) {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
    try {
      const page = await context.newPage();
      if (sourceRelay) {
        await page.route(new URL(state.publicUrl).origin + '/**', async route => {
          const request = route.request();
          const url = new URL(request.url());
          if (!request.isNavigationRequest() || url.pathname !== '/' || !url.searchParams.has('token')) { await route.continue(); return; }
          const incoming = await new Promise((resolve, reject) => {
            const proxy = httpRequest({ hostname: '127.0.0.1', port: sourceRelay.port, path: url.pathname + url.search, method: 'GET',
              headers: { ...request.headers(), host: url.host, 'x-forwarded-host': url.host, 'x-forwarded-proto': 'https',
                'tailscale-user-login': 'isolated-browser-test', 'sec-fetch-mode': 'navigate', 'sec-fetch-dest': 'document' } }, response => {
              const chunks = [];
              response.on('data', chunk => chunks.push(chunk));
              response.on('end', () => resolve({ status: response.statusCode, headers: response.headers, body: Buffer.concat(chunks) }));
              response.on('error', reject);
            });
            proxy.setTimeout(10000, () => proxy.destroy(new Error('Source relay request timeout')));
            proxy.on('error', reject); proxy.end();
          });
          await route.fulfill({ status: incoming.status, headers: Object.fromEntries(Object.entries(incoming.headers)
            .filter(([key]) => !['connection', 'transfer-encoding'].includes(key)).map(([key, value]) => [key, Array.isArray(value) ? value.join('\n') : value])), body: incoming.body });
        });
      }
      const cookieBlocks = [];
      const documentResponses = [];
      const cdp = await context.newCDPSession(page);
      await cdp.send('Network.enable');
      cdp.on('Network.requestWillBeSentExtraInfo', event => {
        for (const row of event.associatedCookies ?? []) {
          if (row.blockedReasons?.length) cookieBlocks.push(...row.blockedReasons);
        }
      });
      page.on('response', response => {
        const url = new URL(response.url());
        if (url.origin === new URL(state.publicUrl).origin && response.request().isNavigationRequest()) documentResponses.push(response.status());
      });
      const cleanNavigation = page.waitForResponse(response => {
        const url = new URL(response.url());
        return url.origin === new URL(state.publicUrl).origin && url.pathname === '/' && !url.search && response.request().isNavigationRequest();
      }, { timeout: 30000 });
      let finalResponse;
      if (mode === 'direct') {
        finalResponse = await page.goto(entry, { waitUntil: 'domcontentloaded', timeout: 30000 });
      } else {
        await page.route('https://handoff.example.test/**', route => route.fulfill({ status: 200, contentType: 'text/html',
          body: `<html><body><a id="login" href="${htmlEscape(entry)}">Open private DSH</a></body></html>` }));
        await page.goto('https://handoff.example.test/', { waitUntil: 'domcontentloaded' });
        [finalResponse] = await Promise.all([page.waitForNavigation({ waitUntil: 'domcontentloaded', timeout: 30000 }), page.locator('#login').click()]);
      }
      finalResponse = await cleanNavigation;
      await page.waitForFunction(() => globalThis.__DSH_BOOT__ || /DSH web authentication required/iu.test(document.body?.innerText ?? ''), undefined, { timeout: 20000 });
      const result = { mode, status: finalResponse?.status(), authenticationRequired: /DSH web authentication required/iu.test(await page.locator('body').innerText()),
        queryRemoved: new URL(page.url()).search === '', nativeCookiePresent: (await context.cookies(state.publicUrl)).some(cookie => cookie.name.startsWith('dsh-auth-') && cookie.httpOnly && cookie.secure && cookie.sameSite === 'Strict'),
        documentResponses, cookieBlocks };
      if (result.authenticationRequired) {
        const refreshed = await page.reload({ waitUntil: 'domcontentloaded', timeout: 30000 });
        result.refreshStatus = refreshed.status();
        result.refreshAuthenticationRequired = /DSH web authentication required/iu.test(await page.locator('body').innerText());
        const directAgain = await page.goto(state.publicUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
        result.directAgainStatus = directAgain.status();
      }
      report.cases.push(result);
    } finally { await context.close(); }
  }
  console.log(JSON.stringify(report, null, 2));
  assert.equal(report.anonymousMatchesReportedError, !tailnetMode, 'Plain entry must match the configured authentication mode');
  assert.ok(report.cases.every(result => result.status === 200 && !result.authenticationRequired && result.queryRemoved && result.nativeCookiePresent === !tailnetMode), 'Every first-login navigation must match configured authentication without an authentication-required page');
} catch (error) {
  const message = String(error.message).replaceAll(entry, '<PRIVATE_ENTRY_URL>').replace(/([?&]token=)[^\s"'<>]+/giu, '$1<REDACTED>');
  console.error(message);
  process.exitCode = 1;
} finally { await browser.close(); await sourceRelay?.close(); }
