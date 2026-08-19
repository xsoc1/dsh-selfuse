/**
 * dsh-memory-panel 宿主半边 —— 纯本地文件记忆服务。
 *
 * 在 dsh web 的 webserver 上挂一组 JSON 路由（前缀 /memory），供
 * 设置 → 插件 →「记忆」标签页读写本地记忆：
 *   - 知识页（knowledge/ 下的 Markdown 文件，一个文件一页）
 *   - 记忆条目（notes/ 下的 Markdown 文件，一条一文件）
 *   - 子串搜索、写入一条记忆
 *
 * 存储根目录：`~/.dsh/memory`（可用环境变量 DSH_MEMORY_ROOT 覆盖，供测试）。
 * 零依赖、零模型、永远离线可用：不加云、不调 LLM、数据不出本机。
 * 本插件是 Hindsight 云端记忆的本地替代，不依赖 @vectorize-io/hindsight-*。
 *
 * 安全：文件 id 只允许 [A-Za-z0-9._-]，无路径穿越；所有读取限定在存储根目录内。
 */

import { mkdir, readdir, readFile, stat, writeFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { basename, extname, join, resolve } from 'node:path'

export const name = 'dsh-memory-panel'
export const inject = []

/** webserver 前缀（无尾斜杠：prefix 匹配语义为 pathname.startsWith(prefix + '/')）。 */
const PREFIX = '/memory'

const DEFAULT_ROOT = join(homedir(), '.dsh', 'memory')
/** 子目录：知识页 / 记忆条目。 */
const DIRS = { pages: 'knowledge', notes: 'notes' }
/** 文件 id：basename 前缀，只允许安全字符（ASCII + CJK，无分隔符），杜绝路径穿越。 */
const ID_RE = /^[A-Za-z0-9\u4e00-\u9fa5][A-Za-z0-9\u4e00-\u9fa5._-]{0,119}$/
/** 搜索每组最多结果条数。 */
const SEARCH_CAP = 50
/** 单条新增记忆的最大字节。 */
const MAX_NOTE_BYTES = 256 * 1024

function storeRoot() {
  return resolve(process.env.DSH_MEMORY_ROOT || DEFAULT_ROOT)
}

function kindDir(kind) {
  return join(storeRoot(), DIRS[kind] || '')
}

/**
 * 校验 id 并解析出文件绝对路径；非法抛出带 code 的 Error。
 * @param kind - 'pages' | 'notes'。
 * @param id - 文件名前缀（不带 .md）。
 */
function safePath(kind, id) {
  if (!ID_RE.test(id || '')) {
    throw Object.assign(new Error('非法文件 id'), { code: 'bad-id' })
  }
  const target = resolve(kindDir(kind), `${id}.md`)
  const root = resolve(storeRoot())
  if (!(target.startsWith(`${root}${sepFor()}`) || target === root)) {
    throw Object.assign(new Error('路径越界'), { code: 'bad-id' })
  }
  return target
}

function sepFor() {
  // resolve 已按平台处理；这里用 / 与 \ 两者都判，兼容跨平台路径。
  return process.platform === 'win32' ? '\\' : '/'
}

/** 从文件内容头部解析可显示的标题（frontmatter title 或首个非空行/# 标题）。 */
function titleOf(content, fallback) {
  const lines = content.split(/\r?\n/)
  for (const line of lines.slice(0, 8)) {
    const m = /^title:\s*(.*)$/.exec(line)
    if (m && m[1].trim()) return m[1].trim()
    const h = /^#\s+(.*)$/.exec(line)
    if (h) return h[1].trim()
  }
  const first = lines.map((l) => l.trim()).find((l) => l !== '')
  return (first && first.slice(0, 60)) || fallback
}

/** 列出某类文件（知识页按名排序；记忆条目按 mtime 倒序）。 */
async function listFiles(kind) {
  const dir = kindDir(kind)
  await mkdir(dir, { recursive: true })
  const entries = await readdir(dir, { withFileTypes: true })
  const rows = []
  for (const e of entries) {
    if (!e.isFile() || extname(e.name).toLowerCase() !== '.md') continue
    const id = basename(e.name, '.md')
    if (!ID_RE.test(id)) continue
    const p = join(dir, e.name)
    const st = await stat(p)
    rows.push({ id, name: id, mtime: st.mtimeMs, size: st.size })
  }
  if (kind === 'pages') rows.sort((a, b) => a.name.localeCompare(b.name))
  else rows.sort((a, b) => b.mtime - a.mtime)
  return rows
}

/** 搜索：遍历知识页与记忆条目，子串匹配 标题+内容。 */
async function searchMemories(q) {
  const needle = (q || '').trim().toLowerCase()
  if (!needle) return []
  const out = []
  for (const kind of ['pages', 'notes']) {
    for (const f of await listFiles(kind)) {
      let content = ''
      try {
        content = await readFile(safePath(kind, f.id), 'utf8')
      } catch {
        continue
      }
      const title = titleOf(content, f.id)
      const hay = `${title}\n${content}`.toLowerCase()
      const at = hay.indexOf(needle)
      if (at === -1) continue
      const snippet = snippetOf(content, at, needle.length)
      out.push({ id: f.id, kind: kind === 'pages' ? 'page' : 'note', name: title, snippet })
      if (out.length >= SEARCH_CAP) return out
    }
  }
  return out
}

/** 取命中位置前后一小段作为摘要。 */
function snippetOf(content, at, len) {
  const start = Math.max(0, at - 40)
  const end = Math.min(content.length, at + len + 100)
  const prefix = start > 0 ? '…' : ''
  const suffix = end < content.length ? '…' : ''
  return prefix + content.slice(start, end).replace(/\r?\n/g, ' ') + suffix
}

/* ---------------- 请求处理 ---------------- */

function json(res, status, value) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' })
  res.end(JSON.stringify(value))
}

function sendOk(res, value) {
  json(res, 200, { ok: true, value })
}

function sendErr(res, err) {
  json(res, 200, {
    ok: false,
    error: {
      code: err && err.code ? String(err.code) : 'error',
      message: err && err.message ? err.message : String(err),
    },
  })
}

function readBody(req) {
  return new Promise((resolveFn) => {
    let data = ''
    req.on('data', (chunk) => {
      data += chunk
      if (data.length > MAX_NOTE_BYTES + 1024) req.destroy()
    })
    req.on('end', () => {
      try {
        resolveFn(data ? JSON.parse(data) : {})
      } catch {
        resolveFn({})
      }
    })
    req.on('error', () => resolveFn({}))
  })
}

function clampInt(value, min, max, fallback) {
  const n = Number(value)
  if (!Number.isFinite(n)) return fallback
  return Math.max(min, Math.min(max, Math.floor(n)))
}

/** @returns 存储根目录的现状统计。 */
async function storeStatus() {
  const root = storeRoot()
  await mkdir(kindDir('pages'), { recursive: true })
  await mkdir(kindDir('notes'), { recursive: true })
  const pages = await listFiles('pages')
  const notes = await listFiles('notes')
  const bytes = pages.reduce((n, x) => n + x.size, 0) + notes.reduce((n, x) => n + x.size, 0)
  return { store: root, counts: { pages: pages.length, notes: notes.length }, bytes }
}

/**
 * 路由分发。
 * @param req - node http 请求对象。
 * @param res - node http 响应对象。
 */
async function handle(req, res) {
  const { pathname, searchParams } = new URL(req.url || '/', 'http://x')
  try {
    if (req.method !== 'GET' && req.method !== 'POST') {
      json(res, 405, { ok: false, error: { code: 'method', message: 'method not allowed' } })
      return
    }

    if (pathname === '/memory/api/status' && req.method === 'GET') {
      sendOk(res, await storeStatus())
      return
    }

    if (pathname === '/memory/api/pages' && req.method === 'GET') {
      const rows = await listFiles('pages')
      const items = []
      for (const r of rows) {
        let content = ''
        try {
          content = await readFile(safePath('pages', r.id), 'utf8')
        } catch {
          continue
        }
        items.push({ id: r.id, name: titleOf(content, r.id), size: r.size })
      }
      sendOk(res, { items })
      return
    }

    if (pathname === '/memory/api/page' && req.method === 'GET') {
      const id = searchParams.get('id') || ''
      if (!id) {
        sendErr(res, new Error('缺少 id'))
        return
      }
      const p = safePath('pages', id)
      const content = await readFile(p, 'utf8')
      sendOk(res, { page: { id, name: titleOf(content, id), content } })
      return
    }

    if (pathname === '/memory/api/notes' && req.method === 'GET') {
      const limit = clampInt(searchParams.get('limit'), 1, 500, 100)
      const offset = clampInt(searchParams.get('offset'), 0, 100000, 0)
      const rows = await listFiles('notes')
      const page = rows.slice(offset, offset + limit)
      const items = []
      for (const r of page) {
        let content = ''
        try {
          content = await readFile(safePath('notes', r.id), 'utf8')
        } catch {
          continue
        }
        items.push({ id: r.id, name: titleOf(content, r.id), mtime: r.mtime, size: r.size })
      }
      sendOk(res, { items, total: rows.length, limit, offset })
      return
    }

    if (pathname === '/memory/api/note' && req.method === 'GET') {
      const id = searchParams.get('id') || ''
      if (!id) {
        sendErr(res, new Error('缺少 id'))
        return
      }
      const p = safePath('notes', id)
      const content = await readFile(p, 'utf8')
      sendOk(res, { note: { id, name: titleOf(content, id), content } })
      return
    }

    if (pathname === '/memory/api/search' && req.method === 'GET') {
      const q = (searchParams.get('q') || '').trim()
      if (!q) {
        sendOk(res, { results: [] })
        return
      }
      sendOk(res, { results: await searchMemories(q) })
      return
    }

    if (pathname === '/memory/api/note' && req.method === 'POST') {
      const body = await readBody(req)
      const raw = typeof body.text === 'string' ? body.text.trim() : ''
      if (!raw) {
        sendErr(res, new Error('缺少 text'))
        return
      }
      const title = typeof body.title === 'string' && body.title.trim() ? body.title.trim() : null
      const slug = (title || raw.slice(0, 20)).toLowerCase().replace(/[^a-z0-9\u4e00-\u9fa5]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40) || 'note'
      const id = `${stamp()}-${slug}`
      const content = title ? `# ${title}\n\n${raw}\n` : `${raw}\n`
      await writeFile(safePath('notes', id), content, 'utf8')
      sendOk(res, { id, name: title || titleOf(content, id), path: `~/.dsh/memory/notes/${id}.md` })
      return
    }

    sendErr(res, new Error('未知端点'))
  } catch (err) {
    sendErr(res, err)
  }
}

function stamp() {
  const d = new Date()
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`
}

/**
 * 插件主体：挂 /memory 前缀路由（仅 Web profile 有 webServer 时装配）。
 * @param ctx - 宿主根上下文。
 */
export function apply(ctx) {
  ctx.inject(['webServer'], (scope) => {
    scope.effect(
      () => scope.webServer.register({
        kind: 'prefix',
        path: PREFIX,
        handler: (req, res) => { void handle(req, res) },
      }),
      'dsh-memory-panel: memory routes',
    )
  })
}
