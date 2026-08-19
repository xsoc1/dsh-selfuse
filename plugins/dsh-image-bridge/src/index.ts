/**
 * @dsh-external/dsh-image-bridge — 图片附件 → view_image 路径标记桥 + 本地生图。
 *
 * 纯文本模型（deepseek-v4 系）的适配器拒绝 image 内容块（UNSUPPORTED_CONTENT），
 * 但 dsh web 输入框原生支持拖拽/粘贴图片（image 块进入会话日志）。本插件在
 * `llm/stream` 瀑布最前拦截：把用户消息里的每个 image 块导出为带扩展名的本地
 * 文件（DSH_HOME/vision-bridge/），并替换为文本标记 `[用户上传的图片：<路径>]`，
 * 然后带新消息递归重入 llm.stream()（二次进入无 image 块 → 走原链，天然不循环）。
 * 配套系统提示段要求模型对每个标记调用 view_image 工具（由 dsh-vision 插件提供，
 * 转发给本地 Ollama VLM），从而让纯文本模型"看见"用户上传的图片。
 *
 * 生图：注册 `generate_image` 工具，把模型的中文画图请求转发给本地 diffusers
 * 服务（默认 http://127.0.0.1:17821，SDXL-Turbo），生成的 PNG 保存到
 * DSH_HOME/image-gen/ 并返回路径，与 view_image 形成"识图 + 生图"闭环。
 *
 * 资源注册全部挂 ctx.effect（热重载/卸载自动清理）。
 */
import { copyFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import type { Context } from 'cordis'
import z from 'schemastery'
import { defineTool } from '@deepseek-ai/dsh-tools'
import type { AttachmentStore, ImageAttachmentRef } from '@deepseek-ai/dsh-attachment'
import type { GenerateOptions, Message, StreamChunk, TextBlock } from '@deepseek-ai/dsh-llm'
// Side-effect type import: registers the `ctx.systemPrompt` Context extension.
import type {} from '@deepseek-ai/dsh-system-prompt'

export const name = '@dsh-external/dsh-image-bridge'
export const inject = ['llm', 'attachments', 'systemPrompt', 'tools']

export interface Config {
  imageGenBaseURL?: string
  imageGenDir?: string
}

export const Config = z.object({
  imageGenBaseURL: z.string().default('http://127.0.0.1:17821')
    .description('Local text-to-image service base URL (diffusers SDXL-Turbo server)'),
  imageGenDir: z.string().default('')
    .description('Directory for generated images (empty = DSH_HOME/image-gen)'),
})

/** Supported attachment media types → view_image-compatible file extension. */
const MEDIA_EXT: Readonly<Record<string, string>> = {
  'image/png': '.png',
  'image/jpeg': '.jpg',
  'image/webp': '.webp',
  'image/gif': '.gif',
}

/** Export cache directory rooted below DSH_HOME. */
function bridgeDir(): string {
  const home = process.env.DSH_HOME ?? join(homedir(), '.dsh')
  return join(home, 'vision-bridge')
}

/** Generated-image output directory rooted below DSH_HOME (or config override). */
function genDir(config: Config): string {
  if (config.imageGenDir !== undefined && config.imageGenDir !== '') return config.imageGenDir
  const home = process.env.DSH_HOME ?? join(homedir(), '.dsh')
  return join(home, 'image-gen')
}

/**
 * Resolve one content-addressed attachment object file (attachment-local layout:
 * `<root>/objects/<hash[0..2]>/<hash>`). Returns undefined for foreign layouts.
 */
function objectPathOf(root: string, attachmentId: string): string | undefined {
  const match = /^sha256:([0-9a-f]{64})$/.exec(attachmentId)
  if (!match) return undefined
  const hash = match[1]
  return join(root, 'objects', hash.slice(0, 2), hash)
}

/**
 * Export one image attachment to a view_image-readable file (idempotent).
 * @returns the absolute path, or undefined when the attachment is unavailable.
 */
function exportImage(store: AttachmentStore, ref: ImageAttachmentRef): string | undefined {
  const ext = MEDIA_EXT[ref.mediaType]
  if (ext === undefined) return undefined
  const root = (store as { root?: string }).root
  if (root === undefined) return undefined
  const source = objectPathOf(root, ref.attachmentId)
  if (source === undefined || !existsSync(source)) return undefined
  const hash = ref.attachmentId.replace(/^sha256:/, '')
  const target = join(bridgeDir(), `${hash}${ext}`)
  if (!existsSync(target)) {
    mkdirSync(bridgeDir(), { recursive: true })
    copyFileSync(source, target)
  }
  return target
}

/**
 * Rewrite user messages: replace image blocks with `[用户上传的图片：<路径>]` text
 * markers. Returns a new messages array only when at least one block changed.
 */
function rewriteMessages(store: AttachmentStore, messages: readonly Message[]): Message[] | undefined {
  const next = messages.map((message) => {
    if (message.role !== 'user') return message
    let changed = false
    const content = message.content.map((block) => {
      if (block.type !== 'image') return block
      const path = exportImage(store, block.attachment)
      if (path === undefined) return block
      changed = true
      const marker: TextBlock = { type: 'text', text: `[用户上传的图片：${path}]` }
      return marker
    })
    return changed ? { ...message, content } : message
  })
  return next.some((message, index) => message !== messages[index]) ? next : undefined
}

/** Save generated PNG bytes to the gen dir and return the absolute path. */
function saveGeneratedPng(config: Config, bytes: Uint8Array): string {
  const dir = genDir(config)
  mkdirSync(dir, { recursive: true })
  const stamp = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
  const target = join(dir, `gen-${stamp}.png`)
  writeFileSync(target, bytes)
  return target
}

export function apply(ctx: Context, config: Config): void {
  // Intercept before every other llm/stream listener: rewrite image blocks to
  // path markers, then re-enter with the rewritten request (no image block on
  // re-entry, so the chain proceeds normally — no recursion loop).
  ctx.effect(() => ctx.on('llm/stream', (options: GenerateOptions, next: () => AsyncIterable<StreamChunk>) => {
    const messages = rewriteMessages(ctx.attachments, options.messages)
    if (messages === undefined) return next()
    return ctx.llm.stream({ ...options, messages })
  }, { prepend: true }), 'dsh-image-bridge: llm/stream')

  // generate_image: forward a drawing request to the local diffusers service.
  ctx.effect(() => ctx.tools.register(defineTool({
    name: 'generate_image',
    description: 'Generate an image locally with the tiny SDXL-Turbo model. Given a detailed English or Chinese prompt, returns the path to a generated PNG. Note the service must be running (image-gen server on port 17821).',
    parameters: {
      prompt: { type: 'string', required: true, description: 'The image description. Be specific about subject, style, composition, colors.' },
      negative_prompt: { type: 'string', description: 'Things to avoid (optional).' },
      width: { type: 'number', description: 'Output width (default 512, clamped 384..1344, multiple of 8).' },
      height: { type: 'number', description: 'Output height (default 512, clamped 384..1344, multiple of 8).' },
      steps: { type: 'number', description: 'Inference steps (default 4; SDXL-Turbo works best at 1-4).' },
    },
    output: {
      schema: { type: 'string' },
      render: (_args: unknown, value: unknown) => [{ type: 'text', text: String(value) }],
    },
    timeoutMs: 180_000,
    isConcurrencySafe: () => true,
    execute: async (args: { prompt?: string; negative_prompt?: string; width?: number; height?: number; steps?: number }, exec: { signal?: AbortSignal }) => {
      const prompt = typeof args.prompt === 'string' ? args.prompt.trim() : ''
      if (prompt === '') throw new Error('generate_image: prompt is required')
      const base = (config.imageGenBaseURL ?? 'http://127.0.0.1:17821').replace(/\/$/, '')
      const body = {
        prompt,
        negative_prompt: typeof args.negative_prompt === 'string' ? args.negative_prompt : '',
        width: typeof args.width === 'number' ? args.width : 512,
        height: typeof args.height === 'number' ? args.height : 512,
        steps: typeof args.steps === 'number' ? args.steps : 4,
      }
      const signals = [AbortSignal.timeout(180_000), ...exec.signal === undefined ? [] : [exec.signal]]
      let response: Response
      try {
        response = await fetch(`${base}/generate`, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify(body),
          signal: AbortSignal.any(signals),
        })
      } catch (error: unknown) {
        const reason = error instanceof Error ? error.message : String(error)
        throw new Error(`generate_image: local image-gen service unreachable at ${base} (${reason}). Start it with: F:/tools/image-gen/venv/Scripts/python.exe F:/tools/image-gen/server.py`)
      }
      if (!response.ok) {
        const text = await response.text().catch(() => '')
        throw new Error(`generate_image: service returned ${response.status}: ${text.slice(0, 200)}`)
      }
      const png = new Uint8Array(await response.arrayBuffer())
      const path = saveGeneratedPng(config, png)
      const seconds = response.headers.get('x-image-gen-seconds') ?? '?'
      const size = response.headers.get('x-image-gen-size') ?? '?'
      return `已生成图片：${path}（${size}，用时 ${seconds}s）。图片已保存，可直接把路径交给用户。`
    },
  })), 'dsh-image-bridge: generate_image tool')

  // Teach the model that a marker means a real image it must inspect.
  ctx.effect(() => ctx.systemPrompt.section({
    name: 'tool:dsh-image-bridge',
    order: 117,
    text: `## 用户消息中的图片附件
用户消息里可能出现「[用户上传的图片：<路径>]」标记，每个标记对应一张用户上传的图片（同一消息可能有多张）。
看到标记时必须调用 view_image 工具查看对应路径的图片（每张图一次调用），再基于图片内容回答；
绝不允许在未调用 view_image 查看图片的情况下声称自己已经看到了图片内容。

## 本地生图
当用户要求画图/生成图片时，调用 generate_image 工具（本地 SDXL-Turbo 小模型，几秒出图）。
prompt 写清楚主体、风格、构图、配色。生成成功后把返回的图片路径告知用户。`,
  }), 'dsh-image-bridge: prompt')
}
