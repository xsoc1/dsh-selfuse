/**
 * dsh-memory-panel 客户端冒烟测试（Node 环境驱动浏览器 factory）。
 *
 * 桩掉 window.__ModuleLoader__ 与 react 后：校验注册 id、导出面、apply 里
 * 的 settings.plugins.tab 槽位注册（名称/id/顺序/标签/locale/inject 面）。
 */
import assert from 'node:assert/strict'

let handoff
globalThis.window = {
  __ModuleLoader__: {
    load(h) {
      handoff = h
    },
  },
}
globalThis.document = {
  createElement() {
    return { setAttribute() {}, textContent: '', remove() {} }
  },
  head: { appendChild() {} },
}

const fakeReact = {
  useState: (v) => [v, () => {}],
  useEffect: () => {},
}

await import(new URL('../lib/client.js', import.meta.url).href)

assert.ok(handoff, 'factory 应通过 window.__ModuleLoader__.load 注册')
assert.equal(handoff.id, 'dsh-memory-panel')

let requireCalls = []
const exportsObj = handoff.factory((spec) => {
  requireCalls.push(spec)
  if (spec === 'react') return fakeReact
  throw new Error('unexpected require: ' + spec)
})

assert.equal(exportsObj.name, 'dsh-memory-panel')
assert.deepEqual(exportsObj.inject, ['slots', 'locale'])
assert.equal(typeof exportsObj.apply, 'function')
assert.ok(requireCalls.includes('react'), 'factory 应 require react')

let reg
exportsObj.apply({
  effect(fn, label) {
    assert.equal(typeof fn, 'function')
    assert.equal(label, 'dsh-memory-panel: stylesheet')
  },
  inject(deps, cb) {
    assert.deepEqual(deps, ['slots', 'locale'])
    const dict = { 'settings.memoryPanel': { tab: '记忆' } }
    const scope = {
      locale: {
        register(ns, map) {
          assert.equal(ns, 'settings.memoryPanel')
          assert.ok(map.zh && map.en)
        },
        bind(ns) {
          return (k) => dict[ns]?.[k] ?? k
        },
      },
      slots: {
        inject(name, fn) {
          assert.equal(name, 'settings.plugins.tab')
          fn()
          return () => {}
        },
        register(opts, Component) {
          assert.equal(typeof Component, 'function')
          reg = { opts, Component }
          return () => {}
        },
      },
    }
    cb(scope)
  },
})

assert.ok(reg, '应注册 settings.plugins.tab')
assert.equal(reg.opts.name, 'settings.plugins.tab')
assert.equal(reg.opts.id, 'memory')
assert.equal(reg.opts.order, 45)
assert.equal(reg.opts.label(), '记忆')
assert.equal(reg.opts.locale, 'settings.memoryPanel')
const face = reg.opts.inject()
for (const m of ['status', 'pages', 'page', 'notes', 'note', 'saveNote', 'search']) {
  assert.equal(typeof face.api[m], 'function', m + ' 应为函数')
}

console.log('client smoke OK: factory + slot registration passed')
