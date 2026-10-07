## 道行系统数据结构
## 定义道行获取规则、解锁条件、境界里程碑

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

class_name DaoXingManager
extends RefCounted

# ==================== 道行获取来源 ====================

const DAO_XING_SOURCES := {
	"enemy_normal": 1,        ## 击败普通敌人
	"enemy_elite": 3,         ## 击败精英
	"enemy_boss": 10,         ## 击败Boss
	"event_narrative": 2,     ## 叙事事件探索
	"event放弃": 1,            ## 放弃事件交易
	"event_risk_success": 3,  ## 风险事件成功
	"event_risk_fail": 0,     ## 风险事件失败（无道行）
	"shop_first_visit": 1,    ## 首次访问商店
	"rest_meditate": 1,       ## 休息节点选择冥想
}

# ==================== 境界里程碑 ====================

const REALM_MILESTONES := {
	0: {"name": "炼气散修", "min_dao_xing": 0, "max_dao_xing": 50},
	1: {"name": "筑基修士", "min_dao_xing": 50, "max_dao_xing": 150},
	2: {"name": "金丹真人", "min_dao_xing": 150, "max_dao_xing": 300},
	3: {"name": "元婴宗师", "min_dao_xing": 300, "max_dao_xing": 600},
	4: {"name": "化神道祖", "min_dao_xing": 600, "max_dao_xing": 9999},
}

# ==================== 解锁条件 ====================

const UNLOCK_CONDITIONS := {
	"character_lumingyuan": {"type": "dao_xing", "value": 60, "description": "累计道行达到60解锁陆明yuan"},
	"character_alian": {"type": "dao_xing", "value": 100, "description": "累计道行达到100解锁阿莲"},
	"character_zhouxiaoman": {"type": "dao_xing", "value": 200, "description": "累计道行达到200解锁周小满"},
	"engrave_system": {"type": "dao_xing", "value": 140, "description": "累计道行达到140解锁刻印系统"},
	"hidden_ending": {"type": "special", "value": 0, "description": "丢弃全部手牌触发隐藏结局前置"},
}

# ==================== 道行管理器 ====================

var total_dao_xing: int = 0      ## 累计道行（跨局）
var current_realm: int = 0       ## 当前境界索引
var unlocked_features: Array = [] ## 已解锁功能ID

## 获取道行（战斗/事件调用）
func gain_dao_xing(amount: int, source: String = "") -> void:
	var old := total_dao_xing
	total_dao_xing += amount
	print("DaoXing: +%d → %d [%s]" % [amount, total_dao_xing, source])
	_check_unlocks()

## 检查解锁
func _check_unlocks() -> void:
	for feature_id in UNLOCK_CONDITIONS:
		if feature_id in unlocked_features:
			continue
		var cond: Dictionary = UNLOCK_CONDITIONS[feature_id]
		if cond["type"] == "dao_xing" and total_dao_xing >= cond["value"]:
			unlocked_features.append(feature_id)
			print("DaoXing: 解锁 %s — %s" % [feature_id, cond["description"]])

## 获取当前境界名称
func get_realm_name() -> String:
	var milestone: Dictionary = REALM_MILESTONES.get(current_realm, REALM_MILESTONES[0])
	return milestone["name"]

## 获取境界进度（0.0~1.0）
func get_realm_progress() -> float:
	var milestone: Dictionary = REALM_MILESTONES.get(current_realm, REALM_MILESTONES[0])
	var min_val: int = milestone["min_dao_xing"]
	var max_val: int = milestone["max_dao_xing"]
	var range_val: int = max_val - min_val
	if range_val <= 0:
		return 1.0
	return clampf(float(total_dao_xing - min_val) / float(range_val), 0.0, 1.0)

## 检查境界突破
func check_breakthrough() -> bool:
	var next_realm: int = current_realm + 1
	if not REALM_MILESTONES.has(next_realm):
		return false
	var milestone: Dictionary = REALM_MILESTONES[next_realm]
	return total_dao_xing >= milestone["min_dao_xing"]

## 执行境界突破
func do_breakthrough() -> bool:
	if not check_breakthrough():
		return false
	current_realm += 1
	print("DaoXing: 境界突破 → %s" % get_realm_name())
	return true

## 获取统计信息
func get_stats() -> Dictionary:
	return {
		"total_dao_xing": total_dao_xing,
		"current_realm": current_realm,
		"realm_name": get_realm_name(),
		"realm_progress": get_realm_progress(),
		"unlocked": unlocked_features.duplicate(),
	}
