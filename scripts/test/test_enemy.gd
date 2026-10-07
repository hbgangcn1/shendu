## Enemy 单元测试
## 测试敌人创建、意图系统和 AI 行为
# implements: design/13-enemy-behavior-spec
# implements_philosophy: rule_1_core_loop_first, rule_5_real_agency

extends Node

func run_all_tests() -> void:
	print("\n=== Enemy 测试 ===")
	test_enemy_creation()
	test_intent_system()
	test_enemy_factory()
	test_enemy_turn()
	test_status_summary()
	print("=== Enemy 测试完成 ===\n")

func test_enemy_creation() -> void:
	print("\n--- 测试 Enemy 创建 ---")
	var enemy := Enemy.new("测试敌人", 50, WuXing.Element.FIRE, "test_enemy")
	assert(enemy.actor_name == "测试敌人", "名称错误")
	assert(enemy.max_hp == 50, "HP 错误")
	assert(enemy.element == WuXing.Element.FIRE, "元素错误")
	assert(enemy.enemy_id == "test_enemy", "ID 错误")
	enemy.choose_intent()
	assert(not enemy.current_intent.is_empty(), "应有意图")
	print("  ✓ Enemy 创建正确")

func test_intent_system() -> void:
	print("\n--- 测试意图系统 ---")
	var enemy := Enemy.new("测试", 50, WuXing.Element.FIRE)

	# 选择意图
	enemy.choose_intent()
	assert(not enemy.current_intent.is_empty(), "应选中意图")
	assert(enemy.current_intent.has("type"), "意图应有类型")
	assert(enemy.current_intent.has("name"), "意图应有名称")

	# 意图描述
	var desc := enemy.get_intent_description()
	assert(not desc.is_empty(), "意图描述不应为空")

	# 低血量修正：HP<30%时防御权重增加
	enemy.current_hp = 10  # 10/50 = 20% < 30%
	var weights_low := enemy._get_modified_weights({})
	assert(weights_low["defense"] > 20, "低血时防御权重应增加")

	# 玩家有格挡时：攻击权重增加
	enemy.current_hp = 50
	var weights_block := enemy._get_modified_weights({"block": 5})
	assert(weights_block["attack"] > 60, "玩家有格挡时攻击权重应增加")
	print("  ✓ 意图系统正确")

func test_enemy_factory() -> void:
	print("\n--- 测试敌人工厂方法 ---")
	# 灵气游魂（火）
	var fire := Enemy.create_fire_spirit()
	assert(fire.actor_name == "灵气游魂", "名称错误")
	assert(fire.max_hp == 35, "HP 错误")
	assert(fire.element == WuXing.Element.FIRE, "元素错误")

	# 霓虹蜘蛛（木）
	var spider := Enemy.create_neon_spider()
	assert(spider.actor_name == "霓虹蜘蛛", "名称错误")
	assert(spider.max_hp == 35, "HP 错误")
	assert(spider.element == WuXing.Element.WOOD, "元素错误")

	# 城市石魔（土）
	var golem := Enemy.create_urban_golem()
	assert(golem.actor_name == "城市石魔", "名称错误")
	assert(golem.max_hp == 35, "HP 错误")
	assert(golem.element == WuXing.Element.EARTH, "元素错误")

	# 数据水母（水）
	var jellyfish := Enemy.create_data_jellyfish()
	assert(jellyfish.actor_name == "数据水母", "名称错误")
	assert(jellyfish.max_hp == 35, "HP 错误")
	assert(jellyfish.element == WuXing.Element.WATER, "元素错误")

	# 电路精灵（金）
	var sprite := Enemy.create_circuit_sprite()
	assert(sprite.actor_name == "电路精灵", "名称错误")
	assert(sprite.max_hp == 35, "HP 错误")
	assert(sprite.element == WuXing.Element.METAL, "元素错误")
	print("  ✓ 工厂方法正确")

func test_enemy_turn() -> void:
	print("\n--- 测试敌人回合 ---")
	var enemy := Enemy.create_fire_spirit()
	var player := Actor.new("主角", 80, WuXing.Element.FIRE)

	# 选择并执行意图
	enemy.choose_intent({"block": 0, "vulnerable": 0})
	var result := enemy.execute_intent(player)
	assert(result.success == true, "执行意图应成功")

	# 检查玩家是否受伤（如果是攻击意图）
	if result.has("damage"):
		assert(result.damage > 0, "攻击应造成伤害")
		assert(player.current_hp < 80, "玩家应受伤")
	print("  ✓ 敌人回合正确")

func test_status_summary() -> void:
	print("\n--- 测试状态摘要 ---")
	var enemy := Enemy.create_fire_spirit()
	enemy.choose_intent()
	var summary := enemy.get_status_summary()
	assert(summary.find("灵气游魂") != -1, "摘要应包含名称")
	assert(summary.find("35/35") != -1, "摘要应包含 HP")
	assert(summary.find("火") != -1, "摘要应包含元素")
	print("  ✓ 状态摘要正确")
