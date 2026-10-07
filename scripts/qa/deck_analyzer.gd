## Deck Analyzer — 卡组健康度分析器
## 评估牌组的费用分布、元素覆盖、类型比例、combo 潜力

# implements: agent-infrastructure
# implements_philosophy: rule_5_real_agency
# agent-infrastructure: loop-engineering

extends Node

## 分析结果
class Analysis:
	var health_score: int = 100  # 0-100
	var avg_cost: float = 0.0
	var cost_distribution: Dictionary = {}  # cost: count
	var element_distribution: Dictionary = {}
	var kind_distribution: Dictionary = {}
	var rarity_distribution: Dictionary = {}
	var has_zero_cost: bool = false
	var has_high_cost: bool = false
	var defense_ratio: float = 0.0
	var attack_ratio: float = 0.0
	var issues: Array[String] = []
	var recommendations: Array[String] = []

	func to_dict() -> Dictionary:
		return {
			"health_score": health_score,
			"avg_cost": avg_cost,
			"cost_distribution": cost_distribution,
			"element_distribution": element_distribution,
			"kind_distribution": kind_distribution,
			"rarity_distribution": rarity_distribution,
			"has_zero_cost": has_zero_cost,
			"has_high_cost": has_high_cost,
			"defense_ratio": defense_ratio,
			"attack_ratio": attack_ratio,
			"issues": issues,
			"recommendations": recommendations,
		}

## 分析卡组
## deck: Array[Dictionary] 或 Array[CardDataResource]
func analyze(deck: Array) -> Analysis:
	var result := Analysis.new()
	if deck.is_empty():
		result.health_score = 0
		result.issues.append("牌组为空")
		return result

	var total_cost: int = 0
	var cost_dist: Dictionary = {}
	var element_dist: Dictionary = {}
	var kind_dist: Dictionary = {}
	var rarity_dist: Dictionary = {}
	var attack_count: int = 0
	var defense_count: int = 0

	for card in deck:
		var cost: int = _get_cost(card)
		total_cost += cost
		cost_dist[cost] = int(cost_dist.get(cost, 0)) + 1

		var element: int = _get_element(card)
		element_dist[element] = int(element_dist.get(element, 0)) + 1

		var kind: int = _get_kind(card)
		kind_dist[kind] = int(kind_dist.get(kind, 0)) + 1

		var rarity: int = _get_rarity(card)
		rarity_dist[rarity] = int(rarity_dist.get(rarity, 0)) + 1

		match kind:
			0: attack_count += 1
			1: defense_count += 1

	result.avg_cost = float(total_cost) / float(deck.size())
	result.cost_distribution = cost_dist
	result.element_distribution = element_dist
	result.kind_distribution = kind_dist
	result.rarity_distribution = rarity_dist
	result.attack_ratio = float(attack_count) / float(deck.size())
	result.defense_ratio = float(defense_count) / float(deck.size())
	result.has_zero_cost = cost_dist.get(0, 0) > 0
	result.has_high_cost = cost_dist.get(4, 0) > 0

	# 健康度评估
	var score: int = 100

	# 费用分布
	if result.avg_cost > 2.5:
		score -= 10
		result.issues.append("平均费用过高 (%.2f)" % result.avg_cost)
		result.recommendations.append("增加低费牌或减少高费牌")
	if result.avg_cost < 1.0:
		score -= 5
		result.issues.append("平均费用过低 (%.2f)" % result.avg_cost)
		result.recommendations.append("增加功能性中费牌")

	if not result.has_zero_cost:
		score -= 10
		result.issues.append("无 0 费牌（combo 启动困难）")
		result.recommendations.append("补充 0 费功能牌")
	if not result.has_high_cost and deck.size() >= 15:
		score -= 5
		result.issues.append("无 4+ 费高伤害牌")
		result.recommendations.append("补充爆发型高费牌")

	# 攻击/防御比
	if result.attack_ratio > 0.7:
		score -= 15
		result.issues.append("攻击牌过多（%.0f%%）" % (result.attack_ratio * 100))
		result.recommendations.append("增加防御牌")
	if result.defense_ratio < 0.15 and deck.size() >= 10:
		score -= 10
		result.issues.append("防御牌过少（%.0f%%）" % (result.defense_ratio * 100))
		result.recommendations.append("至少 3 张防御牌")

	# 元素覆盖
	if element_dist.size() <= 1:
		score -= 10
		result.issues.append("元素单一（%d 种）" % element_dist.size())
		result.recommendations.append("引入其他元素牌")

	# 牌组大小
	if deck.size() < 10:
		score -= 15
		result.issues.append("牌组过小（%d 张）" % deck.size())
	elif deck.size() > 25:
		score -= 5
		result.issues.append("牌组超过上限（%d/25）" % deck.size())

	result.health_score = clampi(score, 0, 100)
	return result

func _get_cost(card) -> int:
	if card is Dictionary:
		return int(card.get("cost", 0))
	if card.has_method("get"):
		return int(card.cost)
	return 0

func _get_element(card) -> int:
	if card is Dictionary:
		return int(card.get("element", 0))
	if card.has_method("get"):
		return int(card.element)
	return 0

func _get_kind(card) -> int:
	if card is Dictionary:
		return int(card.get("card_kind", card.get("card_type", 0)))
	if card.has_method("get"):
		return int(card.card_kind)
	return 0

func _get_rarity(card) -> int:
	if card is Dictionary:
		return int(card.get("rarity", 0))
	if card.has_method("get"):
		return int(card.rarity)
	return 0