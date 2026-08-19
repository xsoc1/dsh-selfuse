# dsh-image-vision

给纯文本的 DeepSeek 加上眼睛：**聊天里传图 + 识图**，一个插件搞定。

- `view_image` 工具：模型带着问题调用它（OCR、数数、读图表、看 UI 布局……任意视觉问题），插件把图片和问题转发给任意 **OpenAI 兼容的 VLM 端点**（本地 Ollama / 智谱 / DashScope / 豆包……），答案以文本返回。
- **图片附件桥**：在聊天对话框**拖拽或粘贴图片**即可发送——dsh web 输入框原生接收图片附件，本插件在模型请求前把附件改写为 `[用户上传的图片：<路径>]` 标记，并引导模型调用 `view_image` 查看，纯文本模型因此"看见"你上传的图。

```
用户: （拖一张截图进对话框）帮我看看这个报错
模型 → view_image(source="…vision-bridge/xxx.png", question="这个报错的完整文本是什么？")
     ← "TypeError: Cannot read properties of undefined (reading 'map') at …"
模型: 这是一个 … 建议 …
```

## 安装

```sh
dsh plugin --profile web add dsh-image-vision
```

或经 [dsh-market](https://github.com/dsh-market/dsh-market) 插件市场安装。

> 注意：host 在消息提交时会校验当前模型的 `inputModalities` 声明。纯文本模型（如 deepseek-v4-flash 经网关路由）需要在 profile 的 `settings.yaml` 里把该模型声明为支持图片输入，否则带图消息在提交时就被拒绝：

```yaml
llm-pi-ai:
  providers:
    opencode-go:
      apiKeyEnv: OPENCODE_GO_API_KEY
      modelOverrides:
        deepseek-v4-flash:
          input: ['text', 'image']
```

（网关模型目录里本就直接声明 `image` 能力的模型无需此步。）

## 后端选择

一套配置（`baseURL` + `apiKey` + `model`）覆盖所有后端：

| 场景 | baseURL | model | 说明 |
| --- | --- | --- | --- |
| **默认（免费）** | `https://open.bigmodel.cn/api/paas/v4` | `glm-4.6v-flash` | 智谱免费视觉模型，零成本开箱；高峰限流自动降级 |
| **本地 Ollama** | `http://localhost:11434/v1` | `qwen3-vl:4b` | 离线、无 key；小模型对穷举任务较慢，建议 `maxTokens: 4096` + `timeoutMs: 300000` |
| DashScope | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen3-vl-flash` | 百炼 VL 线，高精度 OCR |
| 火山豆包 | `https://ark.cn-beijing.volces.com/api/v3` | `doubao-seed-2-1-turbo-260628` | Ark 模型 ID 带日期后缀 |

API key 读取顺序：插件配置 `apiKey` → `$VISION_API_KEY` → `$DSH_VISION_API_KEY`（仅 export）→ `$ZHIPUAI_API_KEY` → `$DASHSCOPE_API_KEY`。本地端点（localhost）无需 key。

免费档降级链：默认配置下插件自动依次降级 `glm-4.6v-flash` → `glm-4.1v-thinking-flash` → `glm-4v-flash`（可用 `fallbackModels` 覆盖）。thinking 系模型的 `<think>` 推理块会被自动剥离。

## 配置

```yaml
dsh-image-vision:
  baseURL: http://localhost:11434/v1
  apiKey: ""            # 留空则读环境变量；本地端点无需 key
  model: qwen3-vl:4b
  maxTokens: 4096       # 推理型模型建议 ≥2048
  timeoutMs: 300000     # 本地冷加载与穷举 OCR 需 1-4 分钟
  maxImageBytes: 10485760
```

## 工作原理

1. **传图**：对话框拖拽/粘贴 → dsh 附件服务持久化（`~/.dsh/attachments/v1/`）→ 消息带 image 块。
2. **桥接**：`llm/stream` 瀑布最前拦截 → 图片导出为 `~/.dsh/vision-bridge/<sha256>.<ext>` → 替换为 `[用户上传的图片：<路径>]` 文本标记 → 递归重入（无图时直通，不循环）。纯文本适配器不再报 `UNSUPPORTED_CONTENT`。
3. **识图**：模型看到标记 → 调用 `view_image` → VLM 返回文本描述 → 模型基于描述回答。

## License

BSD-3-Clause。`view_image` 转发逻辑移植自 [dsh-vision](https://github.com/william-jin-cmu/dsh-vision)（BSD-3-Clause）。
