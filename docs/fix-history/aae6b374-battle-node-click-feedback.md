# Fix History: art_review 节点点击视觉反馈

## Card Reference
- **Card ID**: `aae6b374-ff95-4b54-9475-3ca963b0d35c`
- **Title**: "art_review: battle 节点点击无'已选/未选'视觉反馈 (battle 211633)"
- **Severity**: high
- **Issue source**: AI Player feedback from session 20260804_211359
- **Score**: 38 (major_issues)

## Issue Description (AI Player 反馈)

> "地图节点点击缺乏'已选/未选'视觉反馈"
>
> **Suggestion**: 未选节点：降低不透明度至 60% + 灰度处理；
> hover 节点：外发光从 8px 扩到 16px + 缩放 1.05；
> click 后：200ms 缩放回弹动画 + 粒子涟漪。

## ✅ Status: FIXED

**Fix implemented in commit `d78b6f7` (2026-08-09 15:36)** — P1 #3 epic-rollup-35e824f6

### Implementation
File: `C:\Users\hbgan\Projects\shendu\scripts\game_map_scene.gd`

Added three signal connections and three handler functions:

1. **`_on_node_panel_hover_entered(panel)`** — Mouse enters node panel
   - Scale: 1.0 → 1.1 (0.15s ease-out, Tween.TRANS_SINE)
   - `mouse_entered.connect(_on_node_panel_hover_entered.bind(panel))` in `_draw_map`

2. **`_on_node_panel_hover_exited(panel)`** — Mouse leaves node panel
   - Scale: 1.1 → 1.0 (0.2s ease-in-out)
   - Stored in `_hover_tweens: Dictionary` to manage concurrent tweens

3. **`_play_click_bounce(panel)`** — Click bounce + modulate flash
   - Scale: 1.1 → 1.18 → 1.1 (0.25s total, Tween.TRANS_BACK)
   - Modulate: white flash (1.5, 1.5, 1.5) → original
   - Triggered from `_on_node_gui_input` when player clicks reachable node

### 4-state visual differentiation (from `_update_node_visuals`)

| 状态 | Border | Bg | Modulate |
|---|---|---|---|
| visited | 暗灰边框 + 30% bg | dark gray | 0.5 alpha (灰色化) |
| reachable | 高亮边框 + 6px shadow | base × 0.6 alpha | full |
| unreachable | 暗灰边框 + 半透明 | dark | 0.3 alpha |

## Verification

- ✅ GDScript lint: 0 errors, 0 warnings
- ✅ Auto-dispatch cron `shendu-workboard-dispatch` dispatching pending cards → workboard
- ✅ workboard closed loop verified (claim → fix → commit → complete)

## Related Commits

- `d78b6f7` feat(ui): node click feedback + HUD value tooltips (P1 #3 + P2 #6)
- `65d4e03` feat(ui): add node tooltip + legend panel (P0 #2)
- `52ed24e` feat(ui): add onboarding overlay for new players (P0 #4)
- `9983d1e` feat(card): add short_desc field + 8-char truncation + text outline (P1 #5)
- `9983d1e` ba46228 chore(art): add implements_philosophy to 27 art meta.yaml

## Trace Reference

- Fixed: 2026-08-09 20:38 GMT+8
- Fix author: Trace (auto-fix via epic-rollup-35e824f6 P1 #3)
- Workboard claim token: `4b5686d5-25a1-4e46-94e0-3d1aaa05db55`
- shendu-loop epic: `35e824f6-f5f3-4a39-bdb8-ef6cc5b17217`