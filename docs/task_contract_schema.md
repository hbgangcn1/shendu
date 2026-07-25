# 蜃都任务契约 Schema（Task Contract Schema v1）

> **来源**：借鉴磊哥 Cocos Creator × AI skill v1（2026-07-25）「任务状态机 + 任务契约」原则
> **作者**：Trace + Robert 终审
> **强制级别**：所有 workboard_specify 调用必须用本 schema 的 YAML 格式填 notes 字段
> **生效日期**：2026-07-25 P0-4

---

## 1. 为什么需要契约

磊哥的判断是对的：「做到哪算哪」是 AI 开发游戏的死法之一。**任务契约 = 在动工前冻结"做什么 / 不做什么 / 怎么验证"**，避免范围蔓延和标准漂移。

蜃都当前痛点：
- workboard 卡的 `notes` 字段是自由文本，没有结构化字段
- 改需求没有 `revision` 跟踪，证据无法证明新鲜度
- maker session 经常"顺手"扩展范围（如做 boss HP 时重写了战斗系统）

---

## 2. 契约结构（YAML）

放在 workboard 卡的 `notes` 字段（结构化 YAML 字符串）：

```yaml
# ═══ 契约标识 ═══
contract_version: 1                # 契约 schema 版本（未来 v2 时强制迁移）
revision: 1                        # 当前修订号；改需求/标准时 +1

# ═══ 任务定义 ═══
goal: "用一句话说清楚这次要达成什么"
scope:
  in_scope:                       # 在范围内
    - "明确要做的事 1"
    - "明确要做的事 2"
  out_of_scope:                   # 不在范围内（关键！防止范围蔓延）
    - "明确不做的事 1（即使顺手也不做）"
    - "明确不做的事 2"

# ═══ 产品假设 ═══
assumptions:
  - "假设当前战斗循环可跑（即使硬门禁 #1 FAIL，本次任务不修）"
  - "假设现有 60+ 美术资产风格已锁定（本次不重做）"

# ═══ 工程上下文 ═══
context:
  project_path: "C:\\Users\\hbgan\\Projects\\shendu"
  godot_version: "4.7-stable"
  branch: "main"
  related_files:
    - "scripts/battle/battle_manager.gd"
    - "scenes/battle_demo.tscn"

# ═══ 硬门禁（引用 hard_gates_v1.yaml） ═══
hard_gates_required:
  - gate_2_gdscript_clean         # 必过的硬门禁
  - gate_3_entry_scene_valid
  - gate_5_no_placeholders
  - gate_8_real_preview_evidence

# ═══ 证据要求 ═══
evidence_required:
  - type: screenshot
    path: "memory/ai_player_sessions/{run_id}/screenshots/battle_after_fix.png"
    description: "修复后战斗场景截图，HP 条颜色变红"
  - type: lint_output
    path: "scripts/Lint-ShenduGDScript.ps1 output"
    description: "GDScript lint 0 命中"
  - type: godot_log
    path: "shendu/qa-logs/godot-{timestamp}.log"
    description: "godot headless 启动无 error"

# ═══ 验收标准（详细） ═══
acceptance_criteria:
  functional:
    - "Boss HP 满血时 HP 条变红色（#C53030）"
    - "Boss 半血时 HP 条变橙色（#E25822）"
  technical:
    - "lint 0 命中"
    - "godot --headless --quit-after 60 无 error"
  visual:
    - "截图与 Art Bible v1 §2.1 土系主色一致"

# ═══ 审批项（需要 Robert 拍板的） ═══
approvals_required:
  - type: paid_asset_generation
    enabled: false                # 本次不需要付费素材
  - type: deployment
    enabled: false                # 本次不部署
  - type: overwrite_existing
    enabled: false                # 本次不覆盖线上版本（dev game 不适用）

# ═══ 角色（maker / verify 分离） ═══
roles:
  maker:
    session_id: "spawn_{task_id}_maker"
    tools_allowed: ["read", "edit", "write", "exec(godot)", "image_generate"]
    tools_forbidden: ["workboard_complete", "memory_search"]
  verifier:
    session_id: "spawn_{task_id}_verifier"
    tools_allowed: ["read", "exec(godot)", "image", "workboard_complete"]
    tools_forbidden: ["write", "edit", "image_generate"]  # 验证阶段不写

# ═══ 时间戳 + 新鲜度 ═══
timestamps:
  contract_created: "2026-07-25T16:30:00+08:00"
  revision_history:
    - revision: 1
      at: "2026-07-25T16:30:00+08:00"
      reason: "初版"

freshness_hours: 24               # 证据超过 24h 标 stale

# ═══ maker 报告字段（执行后填） ═══
maker_report:
  diagnosis: "..."                # 问题诊断
  changes:                        # 实际修改文件清单
    - "scripts/battle/battle_manager.gd:42-58"
  prompt_diff: "..."              # 美术任务才有
  new_artifact_path: "..."        # 美术任务才有
  expected_improvement: "..."

# ═══ checker 报告字段（验证后填） ═══
checker_report:
  decision: "PASS|CONDITIONAL|REJECT"
  scores:
    functional: 95
    technical: 100
    visual: 88
  issues:
    - severity: low
      description: "..."
```

---

## 3. workboard_specify 调用模板

```javascript
workboard_specify({
  id: "card_xxx",
  title: "Boss HP 满血时 HP 条变红色",
  notes: `contract_version: 1
revision: 1
goal: "用一句话说清楚这次要达成什么"
scope:
  in_scope:
    - "修改 scripts/ui/boss_hp_bar.gd 的颜色逻辑"
  out_of_scope:
    - "不改 player HP 条"
    - "不重做战斗 UI"
    - "不新增任何场景"
hard_gates_required:
  - gate_2_gdscript_clean
  - gate_3_entry_scene_valid
  - gate_5_no_placeholders
evidence_required:
  - type: screenshot
    path: "memory/screenshots/boss_hp_red.png"
freshness_hours: 24`,
  priority: "normal",
  labels: ["ui", "battle"],
  maxRuntimeSeconds: 1800,
  maxRetries: 2
})
```

---

## 4. 状态机映射

借鉴磊哥的 5 态：

```
draft（Trace 起草）
   ↓ ready_for_maker（契约冻结）
   ↓ in_progress（maker 执行）
   ↓ review（证据冻结，待 verify）
   ↓ accepted / rework_required
```

映射到 workboard 状态：

| 磊哥状态 | workboard 状态 |
|---------|----------------|
| draft | `backlog` |
| ready_for_codex / ready_for_maker | `todo` |
| in_progress_codex / in_progress | `running` |
| review_hermes / review | `running`（带 `awaiting_review` label）|
| accepted | `done` |
| rework_required | `blocked`（附复现步骤 + 期望结果）|

---

## 5. revision 规则

**何时 `revision +1`**：
- 改 goal 任何一个字
- 改 scope.in_scope 添加项
- 改 scope.out_of_scope 添加项
- 改 hard_gates_required
- 改 acceptance_criteria
- 改 evidence_required

**何时不 `revision +1`**：
- 改 timestamps.contract_created（不影响契约内容）
- 改 maker_report / checker_report（执行后字段）
- 改 timestamps.revision_history（自动追加）

**强制证据对应**：
- 每次 evidence_required 提供的路径必须含 `revision-{N}` 子目录或文件名含 `r{N}`
- 否则 orchestrator 视为 stale 拒绝

---

## 6. out_of_scope 强制（防范围蔓延）

这是借鉴磊哥最重要的条款之一。

**实施**：
1. workboard_specify 后，loop-orchestrator 在 spawn maker 前把 `scope.out_of_scope` 注入 system prompt
2. maker session 必须遵守：禁止 read/write out_of_scope 列举的文件
3. 如果 maker 想扩展范围 → 必须先 `revision +1` 更新契约，再开工

**P1 实施**（sessions_spawn role + toolsAllow）：
- toolsAllow 显式列出 in_scope 文件路径
- out_of_scope 文件被 git pre-commit hook 拦截

**当前 P0 阶段**：
- 仅靠 system prompt 软约束（maker 自觉）
- maker 越界时 verifier 阶段 reject + workboard_comment 标记

---

## 7. evidence_required 自动过期

**逻辑**：
- 提交 proof 时，workboard_proof 的 `command` 字段必须引用 `contract.revision`
- 证据路径的最后修改时间戳 + freshness_hours < 当前时间 → 通过
- 否则 verifier 视为 stale，要求重新生成证据

**P1 实施**：workboard_proof 加 `revision` + `evidence_timestamp` 字段，orchestrator 自动验证。

**P0 阶段**：手工在 verifier 报告里写"证据时间戳：YYYY-MM-DD HH:MM"。

---

## 8. 与 Art Bible + Hard Gates 协同

```
                ┌─────────────────┐
                │ task_contract   │
                │   (this doc)    │
                └────────┬────────┘
                         │ references
          ┌──────────────┼──────────────┐
          │              │              │
          ▼              ▼              ▼
   ┌─────────────┐ ┌──────────────┐ ┌─────────────┐
   │ Art Bible   │ │ Hard Gates   │ │ Loop        │
   │ (v1)        │ │ (v1)         │ │ Orchestrator│
   │             │ │              │ │             │
   │ 视觉契约    │ │ 质量门禁     │ │ 流程编排    │
   └─────────────┘ └──────────────┘ └─────────────┘
```

**示例**：做"战斗背景重新配色"任务时
- 契约 goal: "战斗背景主色改为 #1B3A5C 水系蓝"
- 契约引用 Art Bible v1 §2.1（水系主色）+ §5.2（光照规则）
- 契约 hard_gates_required: [gate_5_no_placeholders, gate_8_real_preview_evidence]
- Orchestrator spawn maker → maker 读 Art Bible §2.1 §5.2 → 生成图 → attach proof
- Orchestrator spawn verifier → verifier 跑 gate_5 + gate_8 → 通过 → accepted

---

## 9. 修订历史

| 版本 | 日期 | 变更 | 作者 |
|------|------|------|------|
| v1 | 2026-07-25 | 初版（借鉴磊哥 skill + workboard 现状适配） | Trace |

---

## 附录 A：完整契约示例

```yaml
contract_version: 1
revision: 1
goal: "Boss HP 满血时 HP 条变红色（#C53030），半血时橙色（#E25822），低血时黄色闪烁"
scope:
  in_scope:
    - "修改 scripts/ui/boss_hp_bar.gd 颜色映射逻辑"
    - "添加 HP 阈值常量到 scripts/constants/battle_constants.gd"
    - "新增 HP < 30% 时黄色闪烁动画"
  out_of_scope:
    - "不改 player HP 条（player_hp_bar.gd 不动）"
    - "不重做战斗 UI 布局"
    - "不增加新场景或 Prefab"
    - "不改 Art Bible v1（即使发现色值不准，本任务也不调）"
assumptions:
  - "当前战斗循环可跑（即使硬门禁 #1 FAIL，本次任务不修）"
  - "现有 boss_*.png 资产不动"
context:
  project_path: "C:\\Users\\hbgan\\Projects\\shendu"
  godot_version: "4.7-stable"
  branch: "main"
  related_files:
    - "scripts/ui/boss_hp_bar.gd"
    - "scripts/constants/battle_constants.gd"
    - "scenes/battle_demo.tscn"
hard_gates_required:
  - gate_2_gdscript_clean
  - gate_3_entry_scene_valid
  - gate_5_no_placeholders
  - gate_8_real_preview_evidence
evidence_required:
  - type: screenshot
    path: "memory/screenshots/boss_hp_full_r1.png"
    description: "Boss 满血时 HP 条红色"
  - type: screenshot
    path: "memory/screenshots/boss_hp_low_r1.png"
    description: "Boss < 30% HP 时黄色闪烁"
  - type: lint_output
    path: "scripts/Lint-ShenduGDScript.ps1 output"
    description: "0 命中"
  - type: godot_log
    path: "shendu/qa-logs/battle-r1.log"
    description: "headless 启动无 error"
acceptance_criteria:
  functional:
    - "HP >= 70% 时 HP 条 #C53030 红色"
    - "30% < HP < 70% 时 HP 条 #E25822 橙色"
    - "HP <= 30% 时 HP 条 #FFB347 黄色 + 1Hz 闪烁"
  technical:
    - "lint 0 命中"
    - "godot --headless --quit-after 60 无 error"
  visual:
    - "HP 条颜色与 Art Bible v1 §2.2 警示色一致"
approvals_required:
  paid_asset_generation: false
  deployment: false
  overwrite_existing: false
roles:
  maker:
    session_id: "spawn_boss_hp_color_maker"
    tools_allowed: [read, edit, write, exec_godot]
  verifier:
    session_id: "spawn_boss_hp_color_verifier"
    tools_allowed: [read, exec_godot, image, workboard_complete]
freshness_hours: 24
timestamps:
  contract_created: "2026-07-25T16:30:00+08:00"
  revision_history:
    - revision: 1
      at: "2026-07-25T16:30:00+08:00"
      reason: "初版"
```

**示例验收流程**：
1. Trace (总控) workboard_specify 创建卡
2. Orchestrator spawn maker → maker 读契约 + Art Bible + Hard Gates
3. Maker 修改 .gd + 跑 lint → attach 截图 + lint 输出 → workboard_proof
4. Orchestrator spawn verifier → verifier 独立 lint + 跑 godot + 检查截图
5. Verifier 出 PASS/CONDITIONAL/REJECT → workboard_complete
6. 如 REJECT → maker 再 attempt（但 attempt >= 2 同 issue_id 未改进 → 升级 Robert）