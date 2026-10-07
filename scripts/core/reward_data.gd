## 奖励系统数据结构
## 定义战斗奖励、三选一逻辑、境界突破奖励
## 按 design/12-reward-system-spec.md 实现（v1.0, 2026-05-30）
## §1.3 触发矩阵, §3.2 稀有度分布, §2.1 降级兜底, §4.1 元素加权

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

extends RefCounted

const CardData := preload("res://scripts/core/card_data.gd")

# ==================== 奖励类型 ====================

enum RewardType { CARD, SPIRIT_STONES, DAO_XING, HP_RESTORE }
enum BreakthroughChoice { PO, LI, WU }  # 破/立/悟

# ==================== 灵石/道行（§1.3） ====================

const STONES_NORMAL := {"base": 8, "variance": 3}    ## 普通怪: 8±3 → 5~11
const STONES_ELITE := {"base": 18, "variance": 5}    ## 精英怪: 18±5 → 13~23
const STONES_BOSS := {"base": 35, "variance": 10}    ## Boss: 35±10 → 25~45

const DAO_XING_NORMAL := 2
const DAO_XING_ELITE := 5
const DAO_XING_BOSS := 10

# ==================== 稀有度分布（§3.2 + §10.2 验证表） ====================

## 普通怪：60% 普通 + 30% 稀有 + 8% 史诗 + 2% 传说 = 100%
const RARITY_WEIGHTS_NORMAL := {
	"common": 60, "rare": 30, "epic": 8, "legend": 2
}

## 精英怪：35% 普通 + 40% 稀有 + 20% 史诗 + 5% 传说 = 100%
const RARITY_WEIGHTS_ELITE := {
	"common": 35, "rare": 40, "epic": 20, "legend": 5
}

## Boss：10% 普通 + 40% 稀有 + 35% 史诗 + 15% 传说 = 100%
const RARITY_WEIGHTS_BOSS := {
	"common": 10, "rare": 40, "epic": 35, "legend": 15
}

# ==================== 元素加权（§4.1） ====================

const ELEMENT_BIAS := 1.2  ## 卡组主导元素权重 +20%

# ==================== 境界突破奖励（§5） ====================

const BREAKTHROUGH_DATA := {
	BreakthroughChoice.PO: {
		"name": "破",
		"description": "攻击之道：本境界内攻击牌伤害 +20%",
		"effect": "attack_bonus",
		"value": 0.20,
	},
	BreakthroughChoice.LI: {
		"name": "立",
		"description": "防御之道：每回合开始获得 3 格挡",
		"effect": "round_block",
		"value": 3,
	},
	BreakthroughChoice.WU: {
		"name": "悟",
		"description": "领悟之道：相生链触发后抽 1 张牌",
		"effect": "generation_draw",
		"value": 1,
	},
}

# ==================== 战斗奖励结构 ====================

var card_choices: Array = []         ## 3 张候选卡牌（CardData[]）
var spirit_stones: int = 0           ## 灵石奖励
var dao_xing: int = 0               ## 道行奖励
var is_elite: bool = false
var is_boss: bool = false

## 生成战斗奖励（按 spec §1.3）
static func generate(elite: bool = false, boss: bool = false, realm: int = 0):
	var reward = load("res://scripts/core/reward_data.gd").new()
	reward.is_elite = elite
	reward.is_boss = boss

	# 灵石奖励（§1.3）
	var stone_cfg: Dictionary
	if boss:
		stone_cfg = STONES_BOSS
	elif elite:
		stone_cfg = STONES_ELITE
	else:
		stone_cfg = STONES_NORMAL
	var stones: int = stone_cfg.base + randi_range(-stone_cfg.variance, stone_cfg.variance)
	reward.spirit_stones = maxi(0, stones)  # 不允许负数（§2.2 注释）

	# 道行奖励（§1.3）
	if boss:
		reward.dao_xing = DAO_XING_BOSS
	elif elite:
		reward.dao_xing = DAO_XING_ELITE
	else:
		reward.dao_xing = DAO_XING_NORMAL

	# 卡牌三选一（按境界切池 + 元素偏向）
	reward.card_choices = _generate_card_choices(3, elite, boss, realm)
	return reward

# ==================== 卡牌生成（§2.1 + §3.2 + §4.1） ====================

## 生成 N 张候选卡牌
## 流程（按 spec §2.1）：
##   1. 按敌人类型选稀有度分布（§3.2）
##   2. 滚 3 次稀有度
##   3. 按稀有度筛候选池（优先 realm 池，缺少时 fallback 到全池）
##   4. 元素加权（§4.1）：卡组主导元素 +20%
##   5. 加权随机
##   6. 降级兜底（§2.1）：Legend→Epic→Rare→Common
##   7. 去重保证 3 张 ID 不重复
static func _generate_card_choices(count: int, elite: bool, boss: bool, realm: int) -> Array:
	var choices: Array = []
	var used_ids: Dictionary = {}
	var realm_pool: Array = CardPool.get_realm_pool(realm)
	if realm_pool.is_empty():
		realm_pool = CardPool.get_mvp_pool_original()
	# 合池：跨境界全卡池（25 张）—— 降级兜底用
	var all_pool: Array = []
	for id in CardPool._mvp_pool + CardPool._zhuji_pool + CardPool._jindan_pool:
		if CardPool._cards.has(id):
			all_pool.append(CardPool._cards[id])

	var weights: Dictionary = _get_rarity_weights(elite, boss)
	var deck_elements: Dictionary = _count_deck_elements()
	var dominant: String = _get_dominant_element(deck_elements)

	for i in range(count):
		var rarity: String = _roll_rarity(weights)
		# 优先 realm 池，fallback 到全池
		var candidates: Array = _filter_by_rarity(realm_pool, rarity)
		if candidates.is_empty():
			candidates = _filter_by_rarity(all_pool, rarity)
		# §2.1 降级兜底
		if candidates.is_empty():
			candidates = _downgrade_rarity(all_pool, rarity)
		# §4.1 元素加权（加权后为空时回退到加权前，避免 filtered 为空导致取模零崩溃）
		var weighted: Array = _filter_by_element(candidates, dominant)
		if weighted.is_empty():
			weighted = candidates
		candidates = weighted
		# 去重（本场 3 选）
		var filtered: Array = []
		for c in candidates:
			if not used_ids.has(c.id):
				filtered.append(c)
		if filtered.is_empty():
			# 全部重复：仍允许重复
			filtered = candidates
		var selected: Variant = filtered[randi() % filtered.size()]
		choices.append(selected)
		used_ids[selected.id] = true

	return choices

## 选稀有度分布（§3.2）
static func _get_rarity_weights(elite: bool, boss: bool) -> Dictionary:
	if boss:
		return RARITY_WEIGHTS_BOSS.duplicate()
	elif elite:
		return RARITY_WEIGHTS_ELITE.duplicate()
	return RARITY_WEIGHTS_NORMAL.duplicate()

## 滚稀有度（加权随机）
static func _roll_rarity(weights: Dictionary) -> String:
	var total: int = 0
	for w in weights.values():
		total += w
	if total <= 0:
		return "common"
	var roll := randi() % total
	var cumulative := 0
	for rarity in ["common", "rare", "epic", "legend"]:
		if not weights.has(rarity):
			continue
		cumulative += weights[rarity]
		if roll < cumulative:
			return rarity
	return "common"

## 按稀有度过滤
static func _filter_by_rarity(pool: Array, rarity: String) -> Array:
	var result: Array = []
	var rarity_int: int = CardData.RARITY_STRING_TO_INT.get(rarity, 0)
	for card in pool:
		if card.rarity == rarity_int:
			result.append(card)
	return result

## §2.1 降级兜底：Legend→Epic→Rare→Common
static func _downgrade_rarity(pool: Array, rarity: String) -> Array:
	var chain: Array = ["legend", "epic", "rare", "common"]
	var idx: int = chain.find(rarity)
	if idx < 0:
		idx = 0
	# 沿降级链查找非空候选
	for i in range(idx + 1, chain.size()):
		var fallback: Array = _filter_by_rarity(pool, chain[i])
		if not fallback.is_empty():
			return fallback
	return pool  # 实在没有就用全池（极端兜底）

# ==================== 元素加权（§4.1） ====================

## 统计卡组五行数量
static func _count_deck_elements() -> Dictionary:
	var counts: Dictionary = {"metal": 0, "wood": 0, "water": 0, "fire": 0, "earth": 0}
	if GameState.deck.is_empty():
		return counts
	for ci in GameState.deck:
		var card: Variant = GameState.collection[ci] if ci < GameState.collection.size() else null
		if card == null:
			continue
		var elem_str: String = CardData.ELEMENT_INT_TO_STRING[card.get("element", 0)]
		if counts.has(elem_str):
			counts[elem_str] += 1
	return counts

## 取卡组主导元素
static func _get_dominant_element(counts: Dictionary) -> String:
	var dominant: String = ""
	var max_count: int = 0
	for elem in counts:
		if counts[elem] > max_count:
			max_count = counts[elem]
			dominant = str(elem)
	return dominant

## §4.1 元素加权过滤：主导元素 +20% 权重
static func _filter_by_element(candidates: Array, dominant: String) -> Array:
	if dominant == "" or candidates.is_empty():
		return candidates
	# 主导元素卡权重 ELEMENT_BIAS (1.2)，其他元素权重 1.0
	# 用加权随机选：1 张卡有 ELEMENT_BIAS/(1+α) 概率被选中
	# 简化实现：直接按权重复制候选（dominant 复制 N 次，其他原样）
	var weighted: Array = []
	var bias_int: int = int(ELEMENT_BIAS * 10)  # 12
	for c in candidates:
		var elem_str: String = CardData.ELEMENT_INT_TO_STRING[c.element]
		if elem_str == dominant:
			for _i in range(bias_int):
				weighted.append(c)
		else:
			weighted.append(c)
	return weighted

# ==================== 境界突破 ====================

## 应用突破选择
static func apply_breakthrough(choice: BreakthroughChoice, player_state: Dictionary) -> void:
	var data: Dictionary = BREAKTHROUGH_DATA.get(choice, {})
	var effect: String = data.get("effect", "")
	var value: Variant = data.get("value", 0)

	match effect:
		"attack_bonus":
			player_state["breakthrough_attack_bonus"] = value
		"round_block":
			player_state["breakthrough_round_block"] = value
		"generation_draw":
			player_state["breakthrough_generation_draw"] = value

	player_state["realm"] = mini(4, player_state.get("realm", 0) + 1)
	var mana_table := [10, 12, 15, 18, 20]
	player_state["max_mana"] = mana_table[player_state["realm"]] if player_state["realm"] < mana_table.size() else 15

	print("Player: 境界突破 → %s (%s)" % [data.get("name", "?"), data.get("description", "")])
