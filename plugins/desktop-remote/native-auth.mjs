/** Private in-memory native authentication for the explicitly trusted tailnet carrier. */
import assert from 'node:assert/strict';
import { request } from 'node:http';

export function createNativeCookieProvider(publicUrl, getTargetPort, authenticatedUrl, now = Date.now) {
  let cached;
  let pending;
  let outgoing;
  let closed = false;
  const origin = new URL(publicUrl).origin;
  const exchange = () => new Promise((resolve, reject) => {
    const url = new URL(authenticatedUrl(publicUrl));
    assert.equal(url.origin, origin);
    assert.equal(url.pathname, '/');
    assert.equal(url.searchParams.getAll('token').length, 1);
    const port = getTargetPort();
    assert.ok(Number.isInteger(port) && port > 0 && port <= 65535);
    outgoing = request({ hostname: '127.0.0.1', port, method: 'GET', path: url.pathname + url.search,
      headers: { host: url.host }, agent: false }, response => {
      response.resume();
      try {
        assert.equal(response.statusCode, 303, 'Native server-side authentication failed');
        assert.equal(response.headers.location, './');
        const cookies = (response.headers['set-cookie'] ?? []).filter(cookie => /^dsh-auth-[A-Za-z0-9_-]+=v1\./u.test(cookie));
        assert.equal(cookies.length, 1, 'Expected one native signed cookie');
        const value = cookies[0];
        assert.ok(/;\s*HttpOnly(?:;|$)/iu.test(value) && /;\s*SameSite=Strict(?:;|$)/iu.test(value));
        const maxAge = Number(value.match(/;\s*Max-Age=(\d+)(?:;|$)/iu)?.[1]);
        assert.ok(Number.isSafeInteger(maxAge) && maxAge > 0, 'Native cookie lifetime is required');
        const cookie = value.split(';')[0];
        assert.ok(/^dsh-auth-[A-Za-z0-9_-]+=v1\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/u.test(cookie), 'Invalid native cookie shape');
        assert.ok(!closed, 'Native authentication provider closed');
        const ttl = maxAge * 1000;
        assert.ok(Number.isSafeInteger(ttl), 'Invalid native cookie lifetime');
        cached = { cookie, refreshAt: now() + ttl - Math.min(30000, ttl / 2) };
        resolve(cookie);
      } catch (error) { reject(error); }
    });
    outgoing.setTimeout(10000, () => outgoing.destroy(new Error('Native authentication timeout')));
    outgoing.once('error', reject);
    outgoing.end();
  });
  return {
    async get() {
      assert.ok(!closed, 'Native authentication provider closed');
      if (cached && now() < cached.refreshAt) return cached.cookie;
      if (!pending) pending = exchange().finally(() => { pending = undefined; outgoing = undefined; });
      return await pending;
    },
    close() { closed = true; cached = undefined; outgoing?.destroy(new Error('Native authentication provider closed')); },
  };
}
