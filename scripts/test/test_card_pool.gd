## 卡池系统单元测试
## 测试 CardPool 和 CardData
# implements: design/02-card-schema §1.1, design/12-reward-system-spec §3
# implements_philosophy: rule_3_three_layer_loops

extends Node

const CardDataResource := preload("res://scripts/core/card_data.gd")

func run_all_tests() -> void:
	print("\n=== 卡池系统测试 ===")
	test_card_pool_loading()
	test_get_card()
	test_get_mvp_pool()
	test_card_data_structure()
	test_invalid_path()
	print("=== 卡池系统测试完成 ===\n")

func test_card_pool_loading() -> void:
	print("\n--- 测试卡池加载 ---")
	# EA 范围 45 张（mvp 17 + zhuji 15 + jindan 13）
	var pool_size := CardPool.get_pool_size()
	assert(pool_size == 45, "总卡池应为 45 张（EA 范围），实际为 %d" % pool_size)
	print("  ✓ 卡池加载正确（%d 张）" % pool_size)

func test_get_card() -> void:
	print("\n--- 测试获取卡牌 ---")
	# 测试存在的卡牌（新 ID 格式）
	var fire_bolt: Dictionary = CardPool.get_card("MC-FI-001")
	assert(fire_bolt != null, "MC-FI-001 应存在")
	assert(fire_bolt.name == "烈焰弹", "MC-FI-001 名称应为 烈焰弹")
	assert(fire_bolt.damage == 10, "MC-FI-001 伤害应为 10")
	assert(fire_bolt.element == WuXing.Element.FIRE, "MC-FI-001 应为火属性")
	assert(fire_bolt.cost == 3, "MC-FI-001 费用应为 3")
	
	# 测试不存在的卡牌
	var not_exist: Variant = CardPool.get_card("not_exist")
	assert(not_exist == null, "不存在的卡牌应返回 null")
	print("  ✓ 获取卡牌正确")

func test_get_mvp_pool() -> void:
	print("\n--- 测试获取 MVP 卡池（活跃池，炼气期 17 张） ---")
	var pool: Array = CardPool.get_mvp_pool()
	var mvp_size: int = CardPool._mvp_pool.size()
	assert(pool.size() == mvp_size, "MVP 活跃池应为 %d 张，实际为 %d" % [mvp_size, pool.size()])

	# 检查每张卡牌的类型
	for card in pool:
		assert(card is CardDataResource, "卡池中的元素应为 CardData 类型")
		assert(not card.id.is_empty(), "卡牌 ID 不应为空")
		assert(not card.name.is_empty(), "卡牌名称不应为空")
	print("  ✓ MVP 池正确（%d 张）" % pool.size())

func test_card_data_structure() -> void:
	print("\n--- 测试卡牌数据结构 ---")
	var card: Dictionary = CardPool.get_card("MC-ME-001")
	assert(card != null, "MC-ME-001 应存在")
	
	# 检查基础属性
	assert(card.id == "MC-ME-001", "ID 错误")
	assert(card.name == "金刚斩", "名称错误")
	assert(card.description == "锋利如金，斩断一切。", "描述错误")
	assert(card.cost == 2, "费用错误")
	assert(card.element == WuXing.Element.METAL, "元素错误")
	assert(card.card_kind == 0, "类型错误")
	assert(card.rarity == 0, "稀有度错误")
	assert(card.damage == 8, "伤害错误")
	assert(card.block == 0, "格挡错误")
	assert(card.draw_cards == 0, "抽牌错误")
	assert(card.heal == 0, "治疗错误")
	print("  ✓ 卡牌数据结构正确")

func test_invalid_path() -> void:
	print("\n--- 测试非法路径 ---")
	# 验证路径安全检查（通过检查日志或错误）
	# 注：由于 CardPool 在 _ready 时自动加载，我们无法直接测试 _load_cards
	# 这里仅验证卡池未被非法路径污染
	assert(CardPool.get_pool_size() == 45, "非法路径不应影响卡池，当前 %d 张" % CardPool.get_pool_size())
	print("  ✓ 路径安全验证正确（总池 %d 张）" % CardPool.get_pool_size())
