/**
 * dsh-memory-panel 冒烟测试（独立临时存储目录，无真实 dsh 环境）。
 *
 * 用 DSH_MEMORY_ROOT 指向临时目录，驱动宿主路由处理器，验证：
 * status 统计、知识页列表/详情、记忆条目列表/详情、搜索、写入新条目、
 * 非法 id 拒绝。
 */
import assert from 'node:assert/strict'
import { mkdtemp, mkdir, writeFile, rm, readdir } from 'node:fs/promises'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

const store = await mkdtemp(join(tmpdir(), 'dsh-memory-smoke-'))
await mkdir(join(store, 'knowledge'))
await mkdir(join(store, 'notes'))
await writeFile(join(store, 'knowledge', 'architecture.md'), '# 架构\n\n端口 11810 用于 Ollama。\n', 'utf8')
await writeFile(join(store, 'notes', '20260818-000000-first.md'), '记一条：记忆面板改成本地文件。\n', 'utf8')

process.env.DSH_MEMORY_ROOT = store
const mod = await import('../lib/index.js')

function mount() {
  let handler
  const ctx = {
    inject(deps, cb) {
      assert.deepEqual(deps, ['webServer'], '应注入 webServer')
      const scope = {
        webServer: {
          register({ kind, path, handler: h }) {
            assert.equal(kind, 'prefix')
            assert.equal(path, '/memory')
            handler = h
            return () => {}
          },
        },
        effect: (fn) => { fn(); return () => {} },
      }
      cb(scope)
      return () => {}
    },
  }
  mod.apply(ctx)
  assert.ok(handler, 'apply 应注册 /memory handler')
  return handler
}

function drive(handler, method, url, body) {
  const req = {
    method,
    url,
    on(ev, cb) {
      if (ev === 'data') { if (body) cb(JSON.stringify(body)) }
      if (ev === 'end') cb()
      return this
    },
    destroy() {},
  }
  let sent
  const res = {
    writeHead(status, headers) { sent = { status, headers } },
    end(payload) { this.payload = payload },
  }
  return new Promise((resolve) => {
    handler(req, res)
    const timer = setInterval(() => {
      if (res.payload !== undefined) {
        clearInterval(timer)
        resolve({ json: JSON.parse(res.payload) })
      }
    }, 5)
    setTimeout(() => { clearInterval(timer); resolve({ json: null }) }, 1500)
  })
}

let handler = mount()

// 1. status
{
  const r = await drive(handler, 'GET', '/memory/api/status')
  assert.equal(r.json.ok, true)
  assert.equal(r.json.value.store, store)
  assert.equal(r.json.value.counts.pages, 1)
  assert.equal(r.json.value.counts.notes, 1)
}

// 2. pages 列表
{
  const r = await drive(handler, 'GET', '/memory/api/pages')
  assert.equal(r.json.ok, true)
  assert.equal(r.json.value.items.length, 1)
  assert.equal(r.json.value.items[0].id, 'architecture')
  assert.equal(r.json.value.items[0].name, '架构')
}

// 3. page 详情
{
  const r = await drive(handler, 'GET', '/memory/api/page?id=architecture')
  assert.ok(r.json.ok)
  assert.ok(String(r.json.value.page.content).includes('11810'))
}

// 4. notes 列表 + 详情
{
  const list = await drive(handler, 'GET', '/memory/api/notes')
  assert.equal(list.json.ok, true)
  assert.equal(list.json.value.total, 1)
  const detail = await drive(handler, 'GET', '/memory/api/note?id=20260818-000000-first')
  assert.ok(String(detail.json.value.note.content).includes('本地文件'))
}

// 5. 搜索
{
  const r = await drive(handler, 'GET', '/memory/api/search?q=11810')
  assert.equal(r.json.ok, true)
  assert.ok(r.json.value.results.some((x) => x.kind === 'page' && x.id === 'architecture'), '应命中知识页')
}

// 6. 写入新条目
{
  const r = await drive(handler, 'POST', '/memory/api/note', { title: '测试条目', text: '一条测试记忆内容' })
  assert.equal(r.json.ok, true)
  const files = await readdir(join(store, 'notes'))
  assert.equal(files.length, 2, '应新增 1 条')
  const list = await drive(handler, 'GET', '/memory/api/notes')
  assert.equal(list.json.value.total, 2, '计数应含新条目')
}

// 7. 非法 id
{
  const r = await drive(handler, 'GET', '/memory/api/page?id=..%2F..%2Fetc%2Fpasswd')
  assert.equal(r.json.ok, false)
  assert.equal(r.json.error.code, 'bad-id')
}

await rm(store, { recursive: true, force: true })
console.log('smoke OK: 7 scenarios passed')
