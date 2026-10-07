## 道统传承系统
## 管理跨局传承、解锁树、残页收集

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name InheritanceSystem
extends Node

signal inheritance_applied(inheritance: Dictionary)

## 传承数据（跨局持久化）
var dao_xing: int = 0                ## 累计道行
var completed_runs: int = 0          ## 通关次数
var characters_unlocked: Array = ["chenmo", "suwan"]  ## 已解锁角色
var pages_collected: Array = []      ## 已收集残页ID
var highest_realm_reached: int = 0   ## 最高到达境界
var total_enemies_defeated: int = 0  ## 累计击败敌人数
var total_cards_played: int = 0      ## 累计出牌数
var total_damage_dealt: int = 0      ## 累计造成伤害

## 残页系统（隐藏结局相关）
const TOTAL_PAGES := 7               ## 总残页数
const HIDDEN_ENDING_PAGES := 5       ## 触发隐藏结局所需残页数

## 传承奖励（每层境界突破给予）
const REALM_INHERITANCE := {
	0: {"name": "炼气传承", "bonuses": ["初始灵石+5"]},
	1: {"name": "筑基传承", "bonuses": ["初始灵石+10", "解锁刻印槽"]},
	2: {"name": "金丹传承", "bonuses": ["初始灵石+15", "初始卡组+1牌"]},
	3: {"name": "元婴传承", "bonuses": ["初始灵石+20", "解锁隐藏事件"]},
	4: {"name": "化神传承", "bonuses": ["全属性+5%", "解锁隐藏结局"]},
}

## 记录单局结束
func record_run_end(player_state: Dictionary) -> void:
	completed_runs += 1
	total_enemies_defeated += player_state.get("enemies_defeated", 0)
	total_cards_played += player_state.get("cards_played", 0)
	total_damage_dealt += player_state.get("damage_dealt", 0)

	var realm: int = player_state.get("realm", 0)
	if realm > highest_realm_reached:
		highest_realm_reached = realm

	# 通关奖励
	if player_state.get("victory", false):
		dao_xing += 10  # 通关基础道行
		print("Inheritance: 通关奖励 道行+10")

	print("Inheritance: 第%d局结束，累计道行 %d" % [completed_runs, dao_xing])

## 获取当前传承等级（基于境界）
func get_inheritance_level() -> int:
	return highest_realm_reached

## 获取传承奖励描述
func get_inheritance_bonuses(level: int) -> Array:
	var data: Dictionary = REALM_INHERITANCE.get(level, {})
	return data.get("bonuses", [])

## 收集残页
func collect_page(page_id: String) -> bool:
	if page_id in pages_collected:
		return false
	pages_collected.append(page_id)
	print("Inheritance: 收集残页 %s (%d/%d)" % [page_id, pages_collected.size(), TOTAL_PAGES])
	return true

## 检查隐藏结局条件
func check_hidden_ending() -> bool:
	return pages_collected.size() >= HIDDEN_ENDING_PAGES

## 获取统计信息
func get_stats() -> Dictionary:
	return {
		"dao_xing": dao_xing,
		"completed_runs": completed_runs,
		"characters_unlocked": characters_unlocked.duplicate(),
		"pages_collected": pages_collected.size(),
		"total_pages": TOTAL_PAGES,
		"highest_realm": highest_realm_reached,
		"hidden_ending_unlocked": check_hidden_ending(),
		"total_enemies_defeated": total_enemies_defeated,
		"total_cards_played": total_cards_played,
		"total_damage_dealt": total_damage_dealt,
	}

## 保存/加载
func save_data() -> Dictionary:
	return {
		"dao_xing": dao_xing,
		"completed_runs": completed_runs,
		"characters_unlocked": characters_unlocked.duplicate(),
		"pages_collected": pages_collected.duplicate(),
		"highest_realm_reached": highest_realm_reached,
		"total_enemies_defeated": total_enemies_defeated,
		"total_cards_played": total_cards_played,
		"total_damage_dealt": total_damage_dealt,
	}

func load_data(data: Dictionary) -> void:
	dao_xing = data.get("dao_xing", 0)
	completed_runs = data.get("completed_runs", 0)
	characters_unlocked = data.get("characters_unlocked", ["chenmo", "suwan"])
	pages_collected = data.get("pages_collected", [])
	highest_realm_reached = data.get("highest_realm_reached", 0)
	total_enemies_defeated = data.get("total_enemies_defeated", 0)
	total_cards_played = data.get("total_cards_played", 0)
	total_damage_dealt = data.get("total_damage_dealt", 0)
