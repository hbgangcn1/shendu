## Reward Evaluator — 挑剔玩家视角的奖励评估器
## 评估奖励卡牌的元素覆盖、稀有度分布、类型比例、数值合理性、协同度

# implements: agent-infrastructure
# implements_philosophy: rule_5_real_agency
# agent-infrastructure: loop-engineering

extends Node

## 评估结果
class Evaluation:
	var score: int = 10  # 0-10
	var concerns: Array[String] = []
	var positives: Array[String] = []
	var recommendations: Array[String] = []
	var details: Dictionary = {}

	func to_dict() -> Dictionary:
		return {
			"score": score,
			"concerns": concerns,
			"positives": positives,
			"recommendations": recommendations,
			"details": details,
		}

## 评估奖励合理性
## reward_cards: Array[Dictionary] (CardDataResource dict)
## player_deck: Array[Dictionary] (CardDataResource dict)
## realm: int (0=炼气 1=筑基 2=金丹)
func evaluate(reward_cards: Array, player_deck: Array, realm: int) -> Evaluation:
	var eval := Evaluation.new()
	eval.score = 10

	if reward_cards.is_empty():
		eval.score = 0
		eval.concerns.append("奖励为空")
		return eval

	# 1. 元素覆盖检查
	var deck_elements: Array = []
	for c in player_deck:
		if c is Dictionary:
			deck_elements.append(int(c.get("element", 0)))
		elif c.has_method("get"):
			deck_elements.append(int(c.element))
	deck_elements = _unique(deck_elements)
	eval.details["deck_elements"] = deck_elements

	var new_elements: Array = []
	for c in reward_cards:
		var e: int = _card_element(c)
		if not deck_elements.has(e):
			new_elements.append(e)
	if new_elements.size() > 0:
		eval.positives.append("引入 %d 个新元素（扩展 %s）" % [new_elements.size(), _elements_to_names(new_elements)])
	else:
		# 没有新元素 — 检查是否强化主元素
		var main_element: int = _get_main_element(deck_elements)
		var has_main: bool = false
		for c in reward_cards:
			if _card_element(c) == main_element:
				has_main = true
				break
		if has_main:
			eval.positives.append("强化主元素")
		else:
			eval.concerns.append("奖励无主元素，无新元素，无协同")

	# 2. 稀有度合理性
	var rarities: Array[int] = []
	for c in reward_cards:
		rarities.append(_card_rarity(c))
	var legend_count: int = rarities.count(3)
	var epic_count: int = rarities.count(2)
	var rare_count: int = rarities.count(1)
	var common_count: int = rarities.count(0)
	eval.details["rarity_dist"] = {
		"common": common_count,
		"rare": rare_count,
		"epic": epic_count,
		"legend": legend_count,
	}
	if legend_count >= 2:
		eval.score -= 2
		eval.concerns.append("奖励出现 %d 张传说卡（保底太高或数据失衡）" % legend_count)
		eval.recommendations.append("降低传说卡出现概率")
	if common_count == 3 and realm >= 1:
		eval.score -= 1
		eval.concerns.append("筑基/金丹期仍全 common（境界权重未生效）" % common_count)
		eval.recommendations.append("后期增加 rare/epic 权重")

	# 3. 类型覆盖（攻击/防御/辅助/特殊）
	var kinds: Array[int] = []
	for c in reward_cards:
		kinds.append(_card_kind(c))
	var attack_count: int = kinds.count(0)
	var defense_count: int = kinds.count(1)
	var special_count: int = kinds.count(3)
	eval.details["kind_dist"] = {
		"attack": attack_count,
		"defense": defense_count,
		"support": kinds.count(2),
		"special": special_count,
	}
	if attack_count == 3:
		eval.score -= 1
		eval.concerns.append("3 张都是攻击牌（缺乏防御/功能）")
		eval.recommendations.append("增加防御牌出现率")
	if defense_count == 0 and _count_deck_defense(player_deck) < 3:
		eval.score -= 1
		eval.concerns.append("缺防御牌（牌组防御 < 3）")
		eval.recommendations.append("优先出防御牌奖励")

	# 4. 数值合理性（费用/伤害比）
	for c in reward_cards:
		var cost: int = _card_cost(c)
		var damage: int = _card_damage(c)
		var _block: int = _card_block(c)  # 备用：未使用
		if cost == 0:
			continue
		if damage > 0:
			var ratio: float = float(cost) / float(damage)
			if ratio > 0.5:
				eval.score -= 1
				eval.concerns.append("卡牌「%s」费伤比 %.2f 过高（cost=%d damage=%d）" % [_card_name(c), ratio, cost, damage])
				eval.recommendations.append("提升 %s 的伤害或降低费用" % _card_name(c))

	# 5. 协同度（相生链）
	var chain_potential: int = 0
	for c in reward_cards:
		if _can_chain(c, deck_elements):
			chain_potential += 1
	if chain_potential >= 2:
		eval.score += 1
		eval.positives.append("奖励可形成 %d 次相生链" % chain_potential)
	eval.details["chain_potential"] = chain_potential

	eval.score = clampi(eval.score, 0, 10)
	return eval

func _card_element(card) -> int:
	if card is Dictionary:
		return int(card.get("element", 0))
	if card.has_method("get"):
		return int(card.element)
	return 0

func _card_rarity(card) -> int:
	if card is Dictionary:
		return int(card.get("rarity", 0))
	if card.has_method("get"):
		return int(card.rarity)
	return 0

func _card_kind(card) -> int:
	if card is Dictionary:
		return int(card.get("card_kind", card.get("card_type", 0)))
	if card.has_method("get"):
		return int(card.card_kind)
	return 0

func _card_cost(card) -> int:
	if card is Dictionary:
		return int(card.get("cost", 0))
	if card.has_method("get"):
		return int(card.cost)
	return 0

func _card_damage(card) -> int:
	if card is Dictionary:
		return int(card.get("damage", 0))
	if card.has_method("get"):
		return int(card.damage)
	return 0

func _card_block(card) -> int:
	if card is Dictionary:
		return int(card.get("block", 0))
	if card.has_method("get"):
		return int(card.block)
	return 0

func _card_name(card) -> String:
	if card is Dictionary:
		return str(card.get("name", card.get("card_name", "?")))
	if card.has_method("get"):
		return str(card.name) if card.name != "" else "?"
	return "?"

func _unique(arr: Array) -> Array:
	var result: Array = []
	for item in arr:
		if not result.has(item):
			result.append(item)
	return result

func _elements_to_names(elements: Array) -> String:
	var names := ["金", "木", "水", "火", "土"]
	var parts: Array = []
	for e in elements:
		if e >= 0 and e < names.size():
			parts.append(names[e])
	return "、".join(parts)

func _get_main_element(elements: Array) -> int:
	if elements.is_empty():
		return -1
	var counts: Dictionary = {}
	for e in elements:
		counts[e] = int(counts.get(e, 0)) + 1
	var max_count: int = 0
	var main_e: int = -1
	for e in counts.keys():
		if counts[e] > max_count:
			max_count = counts[e]
			main_e = e
	return main_e

func _count_deck_defense(deck: Array) -> int:
	var count: int = 0
	for c in deck:
		if _card_kind(c) == 1:
			count += 1
	return count

## 检查是否能触发相生链（与现有元素相邻相生）
func _can_chain(card, deck_elements: Array) -> bool:
	var elem: int = _card_element(card)
	if elem < 0 or elem >= 5:
		return false
	# 五行相生：金→水→木→火→土→金
	# 检查这张卡的元素能否被某个 deck 元素"生"
	var _generates_to: int = elem  # 当前元素是 X，则 X 生 Y（占位）
	# 相生链：X 生 Y 当 Y = (X + 1) % 5
	var y: int = (elem + 1) % 5
	for e in deck_elements:
		if e == y:
			return true
	return false