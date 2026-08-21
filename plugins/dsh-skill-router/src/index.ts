/**
 * @dsh-external/dsh-skill-router — 全局技能路由提示段。
 *
 * 职责：往每个会话的 system prompt 注入一张浓缩技能路由表（任务桶 + 中英触发词 +
 * 流程铁律），让 35 个 mattpocock 技能 + 4 个数学技能在日常中文对话中被正确触发，
 * 大任务自动走 grill → spec/tickets → implement → review 主流程。
 *
 * 机制：ctx.systemPrompt.section 注入提示段。
 * 零工具、零依赖；纯提示段，卸载即净。
 */
import type { Context } from 'cordis'
import z from 'schemastery'
// Side-effect type import: registers the `ctx.systemPrompt` Context extension.
import type {} from '@deepseek-ai/dsh-system-prompt'

export const name = '@dsh-external/dsh-skill-router'
export const inject = ['systemPrompt']

export interface Config {
  enabled: boolean
}

export const Config = z.object({
  enabled: z.boolean().default(true),
})

const ROUTER_SECTION = `## 技能路由（每个任务开始前先分类，再选技能/流程）
你有 35 个工程技能 + 4 个数学技能可用（skill 工具按需加载全文）。先识别任务桶，再走对应流程：

【打磨想法/设计方案】→ grill-with-docs（在仓库里：边问边留 CONTEXT.md/ADR 纸面记录）
                        / grill-me（无工作目录：无状态访谈）
                        / grilling（裸访谈原语，被上面两个包装）
  触发：帮我理理思路 / 这个方案靠谱吗 / grill 我 / 压力测试我的计划 / sharpen this idea

【规格化 + 拆票】→ to-spec（对话→spec 发布到 issue tracker）→ to-tickets（拆成 tracer-bullet 票，标注阻塞边）
  触发：写成 spec / 拆成任务 / 出个实施计划（多会话工程）
  前置：先跑 setup-matt-pocock-skills 配好 issue tracker（本机已配 GitHub）

【实现】→ implement（按 spec/票逐票实现，内部驱动 tdd 红绿切片，收尾 code-review）
  触发：实现这个 / 按 spec 写代码 / build this ticket

【评审】→ code-review（双轴：是否遵守仓库规范 + 是否满足原 spec；对 commit/branch/PR）
  触发：评审一下 / review 这个 PR / 检查这段改动

【修 bug】→ diagnosing-bugs（先建能复现的红测试反馈环，再修 + 回归测试，拒绝空想理论）
  触发：这个 bug / 排查一下 / 为什么挂了 / 性能回退 / diagnose this
  修完发现"没有好的 seam 锁住这个 bug" → improve-codebase-architecture

【大工程/看不清路线】→ wayfinder（决策票地图，逐个解决直到路线清晰）→ 汇入 to-spec
  触发：大项目 / 不知道从哪下手 / 超过一个会话的工程 / huge foggy effort

【独立件】→ research（后台调研一手来源，写 Markdown 存档）/ prototype（一次性原型回答设计问题）
            / wizard（只有人类能做的步骤→生成交互式 bash 向导）/ teach（多会话教学）
            / handoff（交接文档：换 harness/目录/人时）/ wait-what（上条没讲清，重述）
            / to-questionnaire（把答不了的决定转成问卷）/ resolving-merge-conflicts（正在冲突中）
            / setup-pre-commit（Husky+lint-staged+类型检查+测试）/ migrate-to-shoehorn
            / scaffold-exercises（课程练习目录）/ git-guardrails-claude-code / writing-for-agents

【数学】→ rigorous-open-math-research（开放/困难数学问题研究）
         / lean-verify（Lean 4 证明审计）/ math-research-workflow（研究+验证全流程编排）
         / manage-math-research-program（长期跨论文研究项目管理）
  触发：定理 / 猜想 / 证明 / 反例 / Lean / 数学研究

【流程铁律】
- 主流程按序：grill → (to-spec→to-tickets) → implement(tdd) → code-review，实现前不跳步
- 到 to-tickets 之前保持同一上下文窗口（想法/规格/票共享思考，不压缩不换会话）
- 每个 implement 从新上下文开始，按票工作
- 拿不准该用哪个技能/流程 → 先加载 ask-matt 技能看完整路由地图再决定
- to-spec / to-tickets / triage 只在 setup-matt-pocock-skills 配置完成后使用`

export function apply(ctx: Context, config: Config): void {
  if (!config.enabled) return

  // 资源注册挂 ctx.effect：热重载/卸载自动清理
  ctx.effect(() => ctx.systemPrompt.section({
    name: 'tool:dsh-skill-router',
    order: 110,
    text: ROUTER_SECTION,
  }), '@dsh-external/dsh-skill-router: router section')
}
