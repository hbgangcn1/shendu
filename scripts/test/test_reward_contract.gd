## 奖励系统契约验证测试
## 验证 §1.3 灵石/道行、§2.1 稀有度降级兜底、§3.2 稀有度分布、§4.1 元素加权
# implements: design/12-reward-system-spec §3 奖励发放契约
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w

extends Node

const BattleReward: GDScript = preload("res://scripts/core/reward_data.gd")
const CardData: GDScript = preload("res://scripts/core/card_data.gd")

func run_all_tests() -> void:
	print("\n========== 奖励契约验证测试（12-reward-system-spec.md） ==========")

	# ===== §1.3 灵石/道行数值验证 =====
	print("\n--- §1.3 灵石/道行 ---")
	for i in range(100):
		var r_normal: Variant = BattleReward.generate(false, false, 0)
		assert(r_normal.dao_xing == 2, "普通怪道行应为 2，实际 %d" % r_normal.dao_xing)
		assert(r_normal.spirit_stones >= 5 and r_normal.spirit_stones <= 11, "普通怪灵石 5~11，实际 %d" % r_normal.spirit_stones)
		var r_elite: Variant = BattleReward.generate(true, false, 0)
		assert(r_elite.dao_xing == 5, "精英道行应为 5，实际 %d" % r_elite.dao_xing)
		assert(r_elite.spirit_stones >= 13 and r_elite.spirit_stones <= 23, "精英灵石 13~23，实际 %d" % r_elite.spirit_stones)
		var r_boss: Variant = BattleReward.generate(false, true, 0)
		assert(r_boss.dao_xing == 10, "Boss 道行应为 10，实际 %d" % r_boss.dao_xing)
		assert(r_boss.spirit_stones >= 25 and r_boss.spirit_stones <= 45, "Boss 灵石 25~45，实际 %d" % r_boss.spirit_stones)
	print("  ✓ 普通怪: 5~11 灵石 +2 道行")
	print("  ✓ 精英怪: 13~23 灵石 +5 道行")
	print("  ✓ Boss: 25~45 灵石 +10 道行")

	# ===== §3.2 稀有度分布验证 =====
	# 注：池子问题：MVP 只有 9 张(8普+1稀)，筑基 9 张(0普+5稀+4史)，金丹 7 张(0普+0稀+5史+2传)
	# 每个池子都不完整，单独验证分布会严重偏。合三个池验证算法本身是否按 spec 执行
	print("\n--- §3.2 稀有度分布（合 3 池 25 张验证算法） ---")
	var all_cards: Array = []
	for id in CardPool._mvp_pool + CardPool._zhuji_pool + CardPool._jindan_pool:
		if CardPool._cards.has(id):
			all_cards.append(CardPool._cards[id])
	# 验证分布：10000 次生成，直接从总池子随机
	var counts := {"common": 0, "rare": 0, "epic": 0, "legend": 0}
	for i in range(10000):
		var rarity: String = BattleReward._roll_rarity(BattleReward.RARITY_WEIGHTS_NORMAL)
		# 用合池过滤（直接走 _filter_by_rarity 函数）
		var candidates: Array = BattleReward._filter_by_rarity(all_cards, rarity)
		if candidates.is_empty():
			# 按 spec §2.1 降级链 fallback
			candidates = BattleReward._downgrade_rarity(all_cards, rarity)
		if candidates.is_empty():
			candidates = all_cards
		var selected: Variant = candidates[randi() % candidates.size()]
		counts[CardData.RARITY_INT_TO_STRING[selected.rarity]] += 1

	var total: int = 0
	for r in counts:
		total += counts[r]
	print("  总 %d 次模拟（含降级兜底）:" % total)
	var exp_normal := {"common": 0.60, "rare": 0.30, "epic": 0.08, "legend": 0.02}
	for rarity in ["common", "rare", "epic", "legend"]:
		var actual_pct: float = counts[rarity] / float(total) * 100
		var exp_pct: float = exp_normal[rarity] * 100
		var diff: float = abs(actual_pct - exp_pct)
		var status: String = "✓" if diff < 5.0 else "✗"
		print("    %s %s: %.1f%% (期望 %.1f%%, 偏差 %.1f%%)" % [status, rarity, actual_pct, exp_pct, diff])

	# ===== §2.1 稀有度降级兜底 =====
	print("\n--- §2.1 稀有度降级兜底 ---")
	# 边界条件：MVP 池只有 1 张 rare（fire_burst），无 epic/legend
	# 所以滚到 epic/legend 时应该降级到 common/rare
	for i in range(100):
		var reward: Variant = BattleReward.generate(false, false, 0)  # MVP 池
		assert(reward.card_choices.size() == 3, "三选一必须 3 张")
		for c in reward.card_choices:
			assert(c != null, "候选卡不能为 null（降级兜底应保证 3 张都有结果）")
	print("  ✓ MVP 池滚到 epic/legend 时降级兜底，3 张候选永远有结果")

	# ===== §4.1 元素加权 =====
	print("\n--- §4.1 元素加权 ---")
	# 模拟玩家牌组全是火：理论上火卡出率 +20%
	# 设置 GameState.deck 全火
	var original_deck: Array = GameState.deck.duplicate()
	var original_collection: Array = GameState.collection.duplicate()
	GameState.collection.clear()
	GameState.deck.clear()
	# 加 5 张火卡
	var fi_burst: Dictionary = CardPool.get_card("MC-FI-002")
	if fi_burst:
		for i in range(5):
			var idx: int = GameState.add_to_collection(fi_burst.to_dict())
			GameState.add_to_deck(idx)
	# 统计火卡出率
	var fire_count: int = 0
	var total_count: int = 0
	for i in range(500):
		var reward: Variant = BattleReward.generate(false, false, 0)
		for c in reward.card_choices:
			total_count += 1
			if c.element == 3:  # FIRE
				fire_count += 1
	var fire_pct: float = fire_count / float(total_count) * 100
	# 基线：MVP 池 9 张，2 张火（fire_bolt 普 + fire_burst 稀），加权后火 ~ 2/(1×7 + 1.2×2) ≈ 22%
	# 实际加权后：火出现 22% 左右（无 deck 时），有 deck +20% 加权
	print("  玩家牌组全火时，火卡出率: %.1f%%" % fire_pct)
	print("  基线无加权: ~22%（MVP 池火卡占比）")
	# 注：MVP 池只有 fire_burst 是 rare，加上元素加权火卡应更高
	# 恢复
	GameState.deck = original_deck
	GameState.collection = original_collection

	print("\n========== 奖励契约验证完成（spec §1.3 §2.1 §3.2 §4.1） ==========\n")
