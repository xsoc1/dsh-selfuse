/**
 * @dsh-external/dsh-image-vision — 对话框传图 + 本地/云端识图，一体插件。
 *
 * 给纯文本模型（deepseek-v4 系）补上"眼睛"：
 * 1. `view_image` 工具：模型带着问题调用它（OCR、数数、读图表、看 UI 布局……），
 *    插件把图片和问题转发给任意 OpenAI 兼容的 VLM 端点（本地 Ollama、智谱、
 *    DashScope、豆包……），答案以文本返回。
 * 2. 图片附件桥：dsh web 输入框原生支持拖拽/粘贴图片（image 附件块），但纯文本
 *    适配器拒绝 image 内容（UNSUPPORTED_CONTENT）。本插件在 `llm/stream` 瀑布
 *    最前拦截：把用户消息里的每个 image 块导出为带扩展名的本地文件
 *    （DSH_HOME/vision-bridge/），替换为文本标记 `[用户上传的图片：<路径>]`，
 *    再以新消息递归重入 llm.stream()（无图时直通 next()，不循环）；配套系统提示
 *    要求模型对每个标记调用 view_image 查看，从而让纯文本模型"看见"聊天里
 *    上传的图片。
 *
 * 注意：host 在消息提交时会校验当前模型的能力声明（inputModalities），纯文本
 * 模型需要把 inputModalities 声明为含 'image'（pi-ai 路由可在 settings.yaml 用
 * modelOverrides 覆盖），否则带图消息在提交时就被拒绝。
 *
 * 资源注册全部挂 ctx.effect（热重载/卸载自动清理）。
 */
import { copyFileSync, existsSync, mkdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import type { Context } from 'cordis'
import z from 'schemastery'
import { defineTool } from '@deepseek-ai/dsh-tools'
import type { AttachmentStore, ImageAttachmentRef } from '@deepseek-ai/dsh-attachment'
import type { GenerateOptions, Message, StreamChunk, TextBlock } from '@deepseek-ai/dsh-llm'
// Side-effect type imports: register the `ctx.systemPrompt`/`ctx.llm` Context extensions.
import type {} from '@deepseek-ai/dsh-system-prompt'
import { visionChat } from './vlm.js'

export const name = '@dsh-external/dsh-image-vision'
export const inject = ['tools', 'systemPrompt', 'llm', 'attachments']

const DEFAULT_BASE_URL = 'https://open.bigmodel.cn/api/paas/v4'
/** Zhipu's free tier gets congested (HTTP 429 code 1305); older free models still answer. */
const DEFAULT_FREE_FALLBACKS = ['glm-4.1v-thinking-flash', 'glm-4v-flash']
/** Errors worth trying the next model for: rate limit, missing model, server trouble. */
const RETRIABLE = /returned (?:429|404|5\d\d)/

export interface Config {
  baseURL?: string
  apiKey?: string
  model?: string
  fallbackModels?: string[]
  maxTokens?: number
  timeoutMs?: number
  maxImageBytes?: number
}

export const Config = z.object({
  baseURL: z.string().default(DEFAULT_BASE_URL)
    .description('OpenAI-compatible VLM endpoint base URL (…/chat/completions is appended); local Ollama: http://localhost:11434/v1'),
  apiKey: z.string().role('secret').default('')
    .description('API key; falls back to $VISION_API_KEY (or exported $DSH_VISION_API_KEY), then $ZHIPUAI_API_KEY / $DASHSCOPE_API_KEY. Local endpoints need none.'),
  model: z.string().default('glm-4.6v-flash')
    .description('Vision model id at the endpoint, e.g. glm-4.6v-flash (free) / qwen3-vl:4b (Ollama) / qwen3-vl-flash'),
  fallbackModels: z.array(z.string()).default([])
    .description('Models tried in order when the primary returns 429/404/5xx; defaults to Zhipu free-tier chain when baseURL is the default'),
  maxTokens: z.number().step(1).min(1).max(32_768).default(4096)
    .description('Output cap per vision call; thinking models need >= 2048'),
  timeoutMs: z.number().step(1).min(1_000).max(600_000).default(180_000)
    .description('Per-call timeout; local Ollama cold loads and exhaustive OCR can take minutes'),
  maxImageBytes: z.number().step(1).min(1).default(10 * 1024 * 1024),
})

const VIEW_IMAGE_PROMPT = `## Vision (view_image)
The chat model itself cannot see images, but the view_image tool can. Whenever an image matters — a screenshot path the user mentions, an image URL, a chart, a UI mockup — call view_image instead of guessing or refusing. Ask it a specific question (extract text, count objects, read a chart, describe the layout); it answers arbitrary questions, not just captions. Prefer one focused call per thing you need to know; ask a follow-up call rather than one vague question.`

const IMAGE_MARKER_PROMPT = `## 用户消息中的图片附件
用户消息里可能出现「[用户上传的图片：<路径>]」标记，每个标记对应一张用户上传的图片（同一消息可能有多张）。
看到标记时必须调用 view_image 工具查看对应路径的图片（每张图一次调用），再基于图片内容回答；
绝不允许在未调用 view_image 查看图片的情况下声称自己已经看到了图片内容。`

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

/** Resolve one content-addressed attachment object file (attachment-local layout: `<root>/objects/<hash[0..2]>/<hash>`). */
function objectPathOf(root: string, attachmentId: string): string | undefined {
  const match = /^sha256:([0-9a-f]{64})$/.exec(attachmentId)
  if (!match) return undefined
  const hash = match[1]
  return join(root, 'objects', hash.slice(0, 2), hash)
}

/** Export one image attachment to a view_image-readable file (idempotent). */
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

/** Rewrite user messages: replace image blocks with `[用户上传的图片：<路径>]` text markers. */
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

export function apply(ctx: Context, config: Config): void {
  const resolved = {
    baseURL: config.baseURL ?? DEFAULT_BASE_URL,
    model: config.model ?? 'glm-4.6v-flash',
    maxTokens: config.maxTokens ?? 4096,
    timeoutMs: config.timeoutMs ?? 180_000,
    maxImageBytes: config.maxImageBytes ?? 10 * 1024 * 1024,
  }
  const fallbackModels = config.fallbackModels !== undefined && config.fallbackModels.length > 0
    ? config.fallbackModels
    : resolved.baseURL === DEFAULT_BASE_URL && resolved.model === 'glm-4.6v-flash' ? DEFAULT_FREE_FALLBACKS : []
  const isLocal = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:|\/|$)/.test(resolved.baseURL)
  const resolveApiKey = (): string => {
    const key = config.apiKey !== undefined && config.apiKey !== '' ? config.apiKey
      : process.env.VISION_API_KEY ?? process.env.DSH_VISION_API_KEY ?? process.env.ZHIPUAI_API_KEY ?? process.env.DASHSCOPE_API_KEY ?? ''
    if (key === '' && !isLocal) {
      throw new Error('view_image: no API key. Set the plugin apiKey config, or set VISION_API_KEY (also honored: ZHIPUAI_API_KEY, DASHSCOPE_API_KEY). The default model glm-4.6v-flash is FREE — create a key at https://open.bigmodel.cn. Offline alternative: baseURL http://localhost:11434/v1 + an Ollama vision model, no key needed.')
    }
    return key
  }

  // 1) view_image tool: forward the model's question about an image to a VLM.
  ctx.effect(() => ctx.tools.register(defineTool({
    name: 'view_image',
    description: 'Look at an image and answer a question about it (OCR, counting, chart reading, layout, arbitrary visual questions). Accepts an absolute local file path, an http(s) URL, or a data: URL.',
    parameters: {
      source: {
        type: 'string',
        required: true,
        description: 'The image: absolute local file path, http(s) URL, or data: URL',
      },
      question: {
        type: 'string',
        description: 'What to find out about the image. Be specific. Default: a thorough general description including any visible text.',
      },
    },
    output: {
      schema: { type: 'string' },
      render: (_args: unknown, value: unknown) => [{ type: 'text', text: String(value) }],
    },
    timeoutMs: resolved.timeoutMs,
    isConcurrencySafe: () => true,
    execute: async (args: { source?: string; question?: string }, exec: { signal?: AbortSignal }) => {
      const source = typeof args.source === 'string' ? args.source : ''
      if (source === '') throw new Error('view_image: source is required')
      const question = typeof args.question === 'string' && args.question !== ''
        ? args.question
        : 'Describe this image thoroughly. Include any visible text verbatim, the overall layout, and notable details.'
      const apiKey = resolveApiKey()
      let lastError: unknown
      for (const model of [resolved.model, ...fallbackModels]) {
        try {
          return await visionChat({ ...resolved, model, apiKey, source, question, signal: exec.signal })
        } catch (error: unknown) {
          lastError = error
          if (!(error instanceof Error) || !RETRIABLE.test(error.message)) throw error
        }
      }
      throw lastError
    },
  })), 'dsh-image-vision: view_image tool')

  // 2) Attachment bridge: rewrite image blocks to path markers before the
  // text-only adapter sees them, then re-enter with the rewritten request
  // (no image block on re-entry, so the chain proceeds normally — no loop).
  ctx.effect(() => ctx.on('llm/stream', (options: GenerateOptions, next: () => AsyncIterable<StreamChunk>) => {
    const messages = rewriteMessages(ctx.attachments, options.messages)
    if (messages === undefined) return next()
    return ctx.llm.stream({ ...options, messages })
  }, { prepend: true }), 'dsh-image-vision: llm/stream')

  // 3) System prompt: teach the model the view_image tool and the marker semantics.
  ctx.effect(() => ctx.systemPrompt.section({
    name: 'tool:dsh-image-vision',
    order: 116,
    text: VIEW_IMAGE_PROMPT,
  }), 'dsh-image-vision: view_image prompt')
  ctx.effect(() => ctx.systemPrompt.section({
    name: 'tool:dsh-image-vision-bridge',
    order: 117,
    text: IMAGE_MARKER_PROMPT,
  }), 'dsh-image-vision: marker prompt')
}
