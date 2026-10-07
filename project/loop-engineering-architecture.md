# 蜃都 Loop Engineering — 架构、流程与逻辑总览

> 文档版本：2026-07-03
> 状态：Phase A/B/C 已落地 · Phase D Maker/Checker 设计完成 · Phase E AI Player 框架就绪
> 维护：Trace（main session）

## TL;DR

蜃都 Loop Engineering 是一个**哲学驱动的反向追溯闭环**，目标是把"Robert 发现问题 → Trace 修复"的 pull 模式升级为"系统自己发现 → 自动修复 → 不收敛再转人工"的 push 模式。

- **哲学权威**：`final-guide.md`（10 黄金法则 + 10 红线）由 2026-05-22 Model Council 产出
- **检测层**：`loop-check.mjs` 静态扫描设计文档 / 代码 / 美术资产是否触碰红线
- **决策层**：按 critical / warn / info 分级，critical 走 Maker/Checker 自动修复
- **集成层**：cron 每天 09:00 + 每 6 小时各跑一次，输出 `loop-state.yaml` + `qa-report.json`
- **总开销**：3 轮 × 2 agent ≈ 6 次 LLM 调用 / 修复周期（强收敛）

---

## 1. 设计哲学权威

### 1.1 来源与归档

| 项 | 路径 |
|---|---|
| 主路径 | `~/.openclaw/workspace/shendu/design/archive/council-reports-old/final-guide.md`（5347 bytes） |
| 镜像 | `~/.openclaw/workspace/reports/game-council/final-guide.md`（5347 bytes，SHA256 一致） |
| 运行时引用 | `skills/shendu-loop/references/philosophy.md`（= 拷贝） |
| 出品方 | Model Council (qwen3.6-plus / deepseek-v4-pro / kimi-k2.6 / MiniMax-M2.7) |
| 时间 | 2026-05-22 |

### 1.2 核心命题

**玩家留下的原因不是"内容多"，而是"在可控的不确定性中，持续感到自己变得更强、更有连接、更有意义"。**

### 1.3 四层驱动模型

| 层级 | 时间尺度 | 满足的需求 | 设计抓手 |
|---|---|---|---|
| 即时反馈 | 秒/分钟 | 心流（胜任） | 操控手感、即时反馈、可变奖励 |
| 成长叙事 | 小时 | 胜任 + 自主 | 可见进度、真实选择、Meta-Progression |
| 社交归属 | 天/周 | 归属 | 朋友链、合作依赖、UGC |
| 意义传奇 | 月/年 | 自我实现 | 个人叙事、文化参与、怀旧锚点 |

**设计原则**：每一层都优先满足 SDT 三需求（自主、胜任、归属），商业化机制在底层叠加，**底线是不烧信任桥**。

### 1.4 10 黄金法则（`rule_1` ~ `rule_10`）

| ID | 法则 | 一句话 |
|---|---|---|
| `rule_1_core_loop_first` | Core 循环优先 | 前 5 分钟的核心玩法必须好玩 |
| `rule_2_failure_must_have_meaning` | 失败有意义 | 每次失败让玩家学到或获得长期进度 |
| `rule_3_three_layer_loops` | 三层循环嵌套 | Core / Meta / Content 缺一不可 |
| `rule_4_social_optional` | 社交可选 | 提供从异步到强社交的参与梯度 |
| `rule_5_real_agency` | 真实 Agency | 少选项但每个有真差异 |
| `rule_6_flow_channel` | 心流通道 | 动态难度保持"稍难但可达" |
| `rule_7_daily_gentle_not_fomo` | 日常温柔 | 每天回归有小收获，不用"不来就没了" |
| `rule_8_cosmetics_over_p2w` | Cosmetics > P2W | 外观付费满足自我表达 |
| `rule_9_progressive_disclosure` | 渐进揭示 | UI 随玩家成长逐步解锁 |
| `rule_10_narrative_play_unified` | 叙事玩法统一 | 角色在剧情中什么样，玩法就匹配 |

### 1.5 10 红线（`red_1` ~ `red_10`）

| ID | 红线 | 替代方案 |
|---|---|---|
| `red_1_p2w` | 付费直接变强 | Cosmetics-only 或加速不突破上限 |
| `red_2_forced_social` | 强制社交绑定 | 单人 / 社交双路径同奖励 |
| `red_3_constant_fomo` | 持续 FOMO | 季度 1-2 次限时 + 回归获取通道 |
| `red_4_fake_choices` | 虚假选择 | 少选项但真实差异，或过程不同结果同 |
| `red_5_narrative_play_mismatch` | 叙事与玩法失调 | 叙事与玩法系统统一 |
| `red_6_ui_overload` | UI 信息过载 | 渐进式信息揭示 |
| `red_7_difficulty_wall` | 难度墙无过渡 | 动态难度或准备阶段提示 |
| `red_8_tutorial_hell` | 教程地狱 | 嵌入式教学，允许跳过 |
| `red_9_ugc_without_base` | 无基础做 UGC 平台 | 先有 10 万+ DAU 再开创作工具 |
| `red_10_three_layer_break` | 三层循环断裂 | Core 产出 → Meta 用途 → Core 闭环 |

---

## 2. 总体架构

### 2.1 全景图

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         蜃都 Loop Engineering                                │
│                                                                              │
│   哲学权威 (immutable)                                                       │
│   ┌────────────────────────────────────┐                                     │
│   │  skills/shendu-loop/references/    │                                     │
│   │   philosophy.md                    │ ← final-guide.md 拷贝               │
│   │   red-line-patterns.md             │ ← 10 红线代码模式字典                │
│   └────────────────────────────────────┘                                     │
│                                                                              │
│   检测层 (read-only)                                                          │
│   ┌─────────────┐  ┌──────────────────┐  ┌──────────────────────────┐        │
│   │ 设计文档     │  │ 代码 (.gd)        │  │ 美术 (meta.yaml)         │        │
│   │ 扫描        │  │ 扫描              │  │ 扫描                     │        │
│   │ frontmatter │  │ # implements:    │  │ implements_philosophy    │        │
│   │ 正文扫雷    │  │ red-line patterns │  │ integration_review.score │        │
│   └──────┬──────┘  └────────┬─────────┘  └────────────┬─────────────┘        │
│          └──────────────────┼──────────────────────────┘                     │
│                             ▼                                                 │
│                  ┌──────────────────────┐                                    │
│                  │   loop-check.mjs     │ 静态（每日 09:00）                  │
│                  │   qa_orchestrator.mjs│ 动态（每 6h）+ 静态 + 运行时解析   │
│                  └──────────┬───────────┘                                    │
│                             │                                                 │
│                  project/loop-state.yaml                                      │
│                  memory/YYYY-MM-DD-loop-report.md                             │
│                  qa-logs/<run_id>/qa-report.json                              │
│                             │                                                 │
│                             ▼                                                 │
│   决策层                                                                       │
│                  loop_status = critical ?                                     │
│                       ├─ NO: 写日报，结束                                      │
│                       └─ YES:                                                 │
│                             │                                                 │
│                  ┌──────────┴───────────┐                                    │
│                  ▼                      ▼                                     │
│          ┌─────────────┐         ┌──────────────┐                            │
│          │ 自动修复     │         │ 转人工       │                             │
│          │ Maker +     │         │ Workboard    │                             │
│          │ Checker     │         │ blocked 卡片 │                             │
│          └──────┬──────┘         └──────────────┘                            │
│                 │                                                             │
│                 ▼                                                             │
│         convergence detector                                                   │
│         M == 0 → PASS | M < N → CONDITIONAL | M == N → REJECT                │
│         3 轮不收敛 → 转人工                                                   │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 三层组件

| 层级 | 组件 | 性质 | 文件 |
|---|---|---|---|
| **数据层** | 哲学文件 | immutable | `references/philosophy.md` |
| | 策划文档 | 标注哲学映射 | `shendu/design/*.md` |
| | 代码 + 注释 | 标注 `# implements:` | `shendu/scripts/*.gd` |
| | 美术 meta.yaml | 标注哲学映射 | `shendu/assets/images/**/*.meta.yaml` |
| **检测层** | `loop-check.mjs` | 静态扫描（Phase A 6 步） | `skills/shendu-loop/references/loop-check.mjs` |
| | `qa_orchestrator.mjs` | 端到端 QA（Godot + 静态 + 运行时解析） | `skills/shendu-loop/references/qa_orchestrator.mjs` |
| | `runtime_error_parser.mjs` | Godot 日志解析 | `skills/shendu-loop/references/runtime_error_parser.mjs` |
| | `window_capture.ps1` | Windows 窗口截图 | `skills/shendu-loop/references/window_capture.ps1` |
| **决策层** | `shendu-loop-daily` cron | 09:00 跑 loop-check | cron job (id: `affa98d7-...`) |
| | `shendu-qa-orchestrator` cron | 每 6h 跑 QA Orchestrator | cron job (id: `e00bf604-...`) |
| | Maker session | ACP-driven 自动修复 | `sessions_spawn(runtime="acp", agentId="opencode")` |
| | Checker session | ACP-driven 独立验证 | `sessions_spawn(runtime="acp", agentId="opencode")` |

### 2.3 cron 集成

| Cron | Schedule | Model | Fallback | 干什么 |
|---|---|---|---|---|
| `shendu-loop-daily` | 每天 09:00 Asia/Shanghai | `opencode-go/kimi-k2.7-code` | `minimax-portal/MiniMax-M3` | 跑 loop-check → 写 loop-state.yaml + memory report → critical 时 spawn Maker/Checker |
| `shendu-qa-orchestrator` | 每 6 小时 | `opencode-go/kimi-k2.7-code` | `minimax-portal/MiniMax-M3` | 跑 Godot QA → 运行时解析 + 静态 + 截图 → critical 时生成修复计划 |

**模型选型理由**（2026-07-03 Robert 明确）：
- 默认 `opencode-go/kimi-k2.7-code`（质量最高 + 便宜 + 长 context）
- `minimax-portal/MiniMax-M3` 作 fallback（kimi 周配额耗尽时兜底，2026-07-06 ~08:30 恢复）
- 图片理解例外：当前没有可用 vision model，详见 `memory/2026-07-03.md`

---

## 3. 静态检查流程（Phase A — 6 步）

完整定义见 `skills/shendu-loop/SKILL.md`。本节强调**逻辑决策**：

### Step 0: 加载哲学

读取 `references/philosophy.md`。如果文件不存在 → **立即终止**，提示 Robert 恢复。这是唯一让 loop 终止的硬条件（除崩溃外）。

### Step 1: 扫描策划文档

```
扫描路径：shendu/design/**/*.md（排除 archive/）
豁免规则：非"两位数字开头"的文件（ui-spec / checklists / 索引 / 项目计划 等）
         不强制 implements_philosophy（视为辅助文档）
核心文档（如 07-combat-system-spec.md）要求：
  - YAML frontmatter 含 implements_philosophy / avoids_red_lines
  - 缺 → warn（Phase A 宽松模式）
  - 正文含 P2W / FOMO / 难度墙 等关键词 → critical
```

### Step 2: 扫描代码

```
扫描路径：shendu/scripts/**/*.gd
追溯注释（推荐）：
  - # implements: design/07-combat-system-spec §三.1
  - # implements_philosophy: rule_1_core_loop_first
  - # avoids_red_line: red_6_ui_overload
红线模式扫描（必查）：
  - 10 红线对应的正则（见 references/red-line-patterns.md）
  - 命中 → critical（注释行跳过，避免误报讨论红线的注释）
  - 缺 # implements: → info
```

### Step 3: 扫描美术资产

```
扫描路径：shendu/assets/images/**/*.meta.yaml（排除 _archive/）
必查字段：
  - implements_philosophy: [rule_x, rule_y]（缺 → warn）
  - integration_review.score（< 75 → critical）
```

### Step 4: 汇总偏差

输出到 `shendu/project/loop-state.yaml`：

```yaml
last_run: 2026-07-03T13:00:00+08:00
philosophy_source: skills/shendu-loop/references/philosophy.md

deviations:
  - severity: critical | warn | info
    type: missing_philosophy_ref | red_line_violation | low_integration_score | ...
    target: <file path>
    message: <human readable>
    evidence: <line content>

summary:
  design_docs: { ok: N, warn: N, critical: N }
  code_files: { ok: N, warn: N, critical: N }
  art_assets: { ok: N, warn: N, critical: N }
  deviations: { critical: N, warn: N, info: N }
  loop_status: ok | warn | critical
```

**严重程度判定逻辑**：
- `critical`：实际触碰红线（有 evidence）+ 集成审核分 < 75
- `warn`：缺 frontmatter / 缺 implements_philosophy
- `info`：可优化项（如可以更明确标注）

### Step 5: 报告 Robert

- `loop_status: critical` → 立即报告（带完整 critical 清单）
- `loop_status: warn` → 当日 memory 提及，给累计趋势
- `loop_status: ok` → memory 简短一行

### Step 6: 启动自动修复（critical 时）

进入 §6 Maker/Checker 流程。

---

## 4. 动态 QA 流程（`qa_orchestrator.mjs`）

每 6 小时跑一次端到端 QA，捕获运行时 + 静态 + 视觉证据：

```
qa_orchestrator.mjs
  │
  ├─ Step 1: 启动 Godot QA
  │    godot --path C:\Users\hbgan\Projects\shendu -- --qa-auto-run --quit
  │    默认非 headless（支持截图）
  │    写日志到 qa-logs/<run_id>/godot-qa.log
  │
  ├─ Step 2: 捕获窗口截图（非 headless）
  │    window_capture.ps1 → qa-logs/<run_id>/window_capture.png
  │
  ├─ Step 3: 运行时错误解析
  │    runtime_error_parser.mjs --log godot-qa.log
  │    分类：critical / warn / info
  │
  ├─ Step 4: 静态 loop-check
  │    loop-check.mjs（与 Phase A 同）
  │    读 project/loop-state.yaml
  │
  ├─ Step 5: 收集截图
  │    qa-captures/*.png + window_capture.png
  │
  ├─ Step 6: 汇总报告
  │    qa-logs/<run_id>/qa-report.json
  │    {
  │      run_id, timestamp, godot: {exit_code, log_path},
  │      runtime: {total, critical, warn, info, issues: [...]},
  │      static: {loop_status, critical, warn, info},
  │      screenshots: [...]
  │    }
  │
  └─ Step 7: 生成修复计划（critical > 0）
       loop-repair.mjs --state project/loop-state.yaml
       → shendu/project/repair-plan.json
```

**关键参数**：
- Godot 超时：5 分钟硬切断
- 启动模式：默认非 headless（--headless 仅在 CI 时手动加）
- 截图：通过 `--qa-auto-run` 触发 autoload 截图脚本（参考 `qa_capture.gd`）

---

## 5. 决策逻辑

### 5.1 `loop_status` 判定

```
if critical_count > 0:
    status = 'critical'
elif warn_count > 0:
    status = 'warn'
else:
    status = 'ok'
```

### 5.2 自动修复 vs 转人工

| 情况 | 动作 |
|---|---|
| `loop_status: ok` | 写日报，结束 |
| `loop_status: warn` | 写日报 + 累计趋势，不自动修复 |
| `loop_status: critical` 且偏差类型 = 红线触碰 | spawn Maker session 自动修复 |
| `loop_status: critical` 但偏差超 50 条 | 提示 Robert 考虑迁移到严格模式 |
| Godot 崩溃 / 启动失败 | 立即通知 Robert，不进入修复循环 |

### 5.3 自动修复可处理范围

**Maker 可自动改**：
- 补 frontmatter（implements_philosophy / avoids_red_lines）
- 补 `# implements:` 注释
- 删除红线代码模式（如果只是命名/标签）
- UI 尺寸微调、注释补全、null 检查

**Maker 不能改**：
- 哲学 / 红线 ID（锁定）
- 数值平衡调整
- 核心机制变更
- 新增 / 删除功能
- 资产审核分 < 75（必须重新过美术 review）

**Maker 看不到**：
- 历史 attempt 数据（避免前次失败路径）
- warn / info 偏差（只修 critical）

---

## 6. Maker/Checker 自动修复（Phase D 设计）

### 6.1 流程

```
shendu-loop-daily (09:00) 检测到 critical > 0
  │
  ├─ 1. 读 loop-state.yaml 提取 critical deviations
  │
  ├─ 2. spawn Maker session（ACP，agentId="opencode"）
  │     输入：critical 列表 + philosophy.md + red-line-patterns.md
  │     输出：修复后文件 + memory/YYYY-MM-DD-loop-repair.md
  │
  ├─ 3. spawn Checker session（ACP，agentId="opencode"）
  │     输入：修复前 critical 列表 + 修复后文件路径（不读 Maker prompt/diagnosis/repair_notes）
  │     输出：JSON { verdict: PASS|CONDITIONAL|REJECT, composite_score, issues, evidence }
  │
  ├─ 4. 收敛判定（convergence detector）
  │     if M == 0       → PASS，写日报，结束
  │     if M < N        → CONDITIONAL，回 Maker 重做
  │     if M == N       → REJECT，回 Maker 重做
  │
  └─ 5. 3 轮不收敛（M != 0）
        → 创建 Workboard blocked 卡片，通知 Robert
```

### 6.2 Checker 评分维度

| 维度 | 权重 | 含义 |
|---|---|---|
| critical 是否真的修复 | 50% | 修复后 critical 数 < 修复前 |
| 修复方式是否过度 | 20% | 是否改了不该改的（warn/info） |
| 是否引入新红线 | 20% | 修复后 critical 严格 ≤ 修复前 |
| 修复说明一致性 | 10% | repair.md 与实际改动一致 |

### 6.3 物理隔离（关键设计）

| 谁看不到什么 | 目的 |
|---|---|
| Maker 看不到历史 attempt | 避免重复失败路径 |
| Maker 看不到 warn/info | 专注修 critical |
| Maker 看不到 Checker 评分 | 避免博弈 |
| Checker 看不到 Maker prompt | 独立判断 |
| Checker 看不到 Maker repair.md | 不被诊断影响 |

### 6.4 限制条件

- **MAX_ROUNDS = 3**（强制转人工）
- **总 token 预算**：3 × 2 = 6 次 LLM 调用 / 修复周期
- **sub-agent model 链**：primary `kimi-k2.7-code`，fallback `minimax-portal/MiniMax-M3`（继承 main session 路由规则）
- **隔离执行**：`sessions_spawn(isolated=true)` 防止 cron 失败挂 main session

---

## 7. 模式：宽松 vs 严格

| 项 | Phase A 宽松（当前） | Phase B 严格（计划） |
|---|---|---|
| frontmatter 缺 | warn（不阻断） | 强制，否则不让任务开始 |
| 注释缺 | info（不阻断） | 校验 implements_philosophy ≥ 1 |
| 红线触碰 | critical（依然报告） | critical + 阻断任务 |
| 美术 meta 缺 | warn | 强制要求 implements_philosophy |

**Phase A 当前在 main session 里跑**，不消耗额外 token。Phase B 引入严格模式后，shendu-dev / shendu-art 任务会先校验 frontmatter，缺则补。

---

## 8. 日志与产物

### 8.1 静态检查产物

| 文件 | 内容 |
|---|---|
| `shendu/project/loop-state.yaml` | 机器可读，git 跟踪 |
| `memory/YYYY-MM-DD-loop-report.md` | 人可读日报 |
| `shendu/project/repair-plan.json` | 自动修复计划（critical > 0 时） |
| `memory/YYYY-MM-DD-loop-repair.md` | Maker 修复说明 |

### 8.2 动态 QA 产物

| 文件 | 内容 |
|---|---|
| `shendu/qa-logs/<run_id>/godot-qa.log` | Godot 完整运行日志 |
| `shendu/qa-logs/<run_id>/window_capture.png` | Windows 窗口截图 |
| `shendu/qa-logs/<run_id>/qa-report.json` | 评估汇总 |
| `shendu/qa-logs/<run_id>/<base>-runtime-issues.json` | 运行时问题分类 |
| `shendu/qa-captures/*.png` | Godot 内部截图（qa_capture.gd） |

### 8.3 工作流文件

| 文件 | 用途 |
|---|---|
| `memory/2026-07-01.md` | Phase A 启动记录 |
| `memory/YYYY-MM-DD-loop-report.md` | 日报（每日追加） |

---

## 9. Phase 路线图

| Phase | 名称 | 状态 | 内容 |
|---|---|---|---|
| **A** | 静态检测 | ✅ 已落地（2026-07-01） | loop-check.mjs 6 步流程，宽松模式，main session 跑 |
| **B** | 注入式约束 | ✅ 已落地 | shendu-dev / shendu-art 强制加载 final-guide + 派生概念 YAML |
| **C** | Hook + cron | ✅ 已落地 | before_prompt_build hook 模板 + shendu-loop-daily / shendu-qa-orchestrator |
| **D** | Maker/Checker 自动修复 | 📐 设计完成 | sessions_spawn 隔离执行 + 收敛检测 + 3 轮转人工 |
| **E** | AI Player + 经验系统 | 🔧 框架就绪 | shendu-ai-player 模型观察截图 + ExperienceMemory 记录技巧 |

**当前优先级**（2026-07-03）：
1. Phase D 实现：等 kimi 配额恢复（07-06 ~08:30）后端到端验证 Maker/Checker
2. Phase E 端到端：VLM 截图分析默认走 kimi，目前限流中无法验证
3. Phase B 严格模式：暂不切，等累计偏差趋势后再决定

---

## 10. 与其他 skill 的关系

```
                       final-guide.md (immutable)
                              │
                              ▼
       ┌────────────────────────────────────────────┐
       │              shendu-loop                    │ ← 哲学反向追溯
       │  检测 / 决策 / 自动修复                      │
       └─────┬─────────────┬─────────────┬──────────┘
             │             │             │
             ▼             ▼             ▼
       ┌──────────┐  ┌──────────┐  ┌──────────────┐
       │shendu-dev│  │shendu-art│  │shendu-ai-    │ ← 模型驱动玩家
       │ 代码开发 │  │ 美术生产 │  │player        │
       └─────┬────┘  └────┬─────┘  └──────┬───────┘
             │            │               │
             ▼            ▼               ▼
       ┌────────────────────────────────────────────┐
       │              godot-dev                      │ ← Godot 错误检查 / 单元测试
       └────────────────────────────────────────────┘
                              │
                              ▼
       ┌────────────────────────────────────────────┐
       │          model-council                      │ ← critical 决策 / 多模型评审
       └────────────────────────────────────────────┘
```

| Skill | 关系 |
|---|---|
| **shendu-dev** | Phase B 改造后强制加载 final-guide。开发任务完成后会被 loop-check 验证 |
| **shendu-art** | Phase B 改造后 concept YAML 强制含 philosophy_alignment |
| **shendu-ai-player** | Phase E 模型驱动 playtest，输出经验与问题到 `ExperienceMemory` |
| **model-council** | critical 偏差需要多角度决策时调用 |
| **godot-dev** | 跑游戏内集成验证（截图 + VLM）时的底层工具 |

---

## 11. 失败处理

| 失败场景 | 行为 |
|---|---|
| 扫描脚本报错 | 立即报告，不掩盖 |
| 缺哲学文件 | 终止运行，提示 Robert 恢复 `references/philosophy.md` |
| Godot 启动失败 | qa_orchestrator 立即报告，不进入修复循环 |
| Maker/Checker 3 轮不收敛 | 强制转人工（Workboard blocked 卡片 + 通知 Robert） |
| 偏差超 50 条 | 提示 Robert 考虑迁移到严格模式（Phase B） |
| cron 连续失败 5 次 | 触发 failureAlert（如果配置） |
| Memory pressure 升级 | 触发 gateway restart 建议 |

---

## 12. 待决策项

| # | 项 | 状态 | 备注 |
|---|---|---|---|
| 1 | Loop Engineering v1 整体架构是否批准 | ✅ 已批准（2026-07-01） | 当前在跑 |
| 2 | Windows 计划任务前台启动 Godot | ⏳ 备选方案 | 当前用 `--qa-auto-run` autoload hook 替代 |
| 3 | 自动修复范围是否合适 | ✅ 已定义 | 见 §5.3 |
| 4 | cron 频率 | ✅ 已定 | daily 09:00 + 每 6h |
| 5 | VLM 模型 | ⏸ 暂停 | kimi 限流中（07-06 恢复），等配额恢复后验证 |
| 6 | Phase D Maker/Checker 端到端 | ⏳ 等配额 | 设计完成，待 kimi 恢复后跑 |

---

## 13. 关键决策记录

| 时间 | 决策 | 影响 |
|---|---|---|
| 2026-05-22 | Model Council 产出 final-guide | 10 黄金法则 + 10 红线成哲学权威 |
| 2026-07-01 17:42 | Phase A 落地（main session，宽松模式） | 不消耗额外 token，只检测不修 |
| 2026-07-02 | Phase B/C 落地 | shendu-dev/art 注入 final-guide，cron 自动跑 |
| 2026-07-02 | Phase D 设计完成 | Maker/Checker 隔离执行 + 收敛检测 |
| 2026-07-03 11:48 | 模型路由规则统一 | kimi primary + MiniMax-M3 fallback 跨 main + 2 cron |
| 2026-07-03 13:00 | 本文档落地 | 项目级架构文档 |

---

## 附录 A：10 红线代码模式（节选）

完整版见 `skills/shendu-loop/references/red-line-patterns.md`。

```javascript
// red_1_p2w
/\b(buy_gold_with_real_money|iap_purchase.*stat_buff|vip.*(damage|attack)|pay_to_win|p2w|premium_currency)\b/i

// red_2_forced_social
/\b(force_join_team|require_friend|cannot_solo|solo_disabled|daily_share_required|co_op_mandatory)\b/i

// red_3_constant_fomo
/\b(limited_time_offer|countdown.*reward|miss_today.*lose|daily_login_streak|lose_streak|event_ends_in_24h)\b/i

// red_6_ui_overload
/\b(show_all_stats_at_start|tooltip_everything|no_progressive_disclosure)\b/i

// red_7_difficulty_wall
/\b(spike_difficulty|boss_no_warning|level_skip.*no_tutorial|hard_mode_from_start)\b/i
```

**误报注意**：代码里出现关键词**不等于**违反红线（可能是注释、配置、测试代码）。Phase A 宽进严出：命中即 critical，由 Robert / Trace 决定真假。

## 附录 B：文件清单

```
shendu-loop/
├── SKILL.md                       # 6 步流程定义
├── PHASE_D_DESIGN.md              # Maker/Checker 设计
├── LOOP_ENGINEERING_V1.md         # V1 总体架构（早期设计）
├── references/
│   ├── philosophy.md              # final-guide 拷贝
│   ├── red-line-patterns.md       # 10 红线正则字典
│   ├── loop-check.mjs             # 静态检查脚本（487 行）
│   ├── loop-repair.mjs            # 修复计划生成
│   ├── qa_orchestrator.mjs        # 端到端 QA 编排（328 行）
│   ├── runtime_error_parser.mjs   # Godot 日志解析
│   ├── window_capture.ps1         # Windows 窗口截图
│   ├── batch-update-traceability.mjs
│   ├── interactive_game_launcher.ps1
│   ├── loop_engineering_demo.mjs
│   ├── manual_visual_qa.ps1
│   ├── prompt_injection_templates.md
│   └── read_godot_log.ps1
```

---

*文档维护者：Trace（main session）*
*最后更新：2026-07-03 13:00 GMT+8*