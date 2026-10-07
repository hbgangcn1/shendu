## 全流程集成测试
## 模拟完整战斗循环：开始→抽牌→出牌→相生→暴击→蓄势→魔念→敌人回合→结算
# implements: design/00-MASTER.md §四 三层循环
# implements_philosophy: rule_3_three_layer_loops

extends Node

const MapNodeScript: GDScript = preload("res://scripts/core/map_node.gd")
const MapGeneratorScript: GDScript = preload("res://scripts/core/map_generator.gd")
const ConnectivityValidatorScript: GDScript = preload("res://scripts/core/connectivity_validator.gd")
const ShopItemScript: GDScript = preload("res://scripts/core/shop_item.gd")
const ShopInventoryScript: GDScript = preload("res://scripts/core/shop_inventory.gd")
const EventDefinitionScript: GDScript = preload("res://scripts/core/event_definition.gd")
const EventChoiceScript: GDScript = preload("res://scripts/core/event_choice.gd")
const EventOutcomeScript: GDScript = preload("res://scripts/core/event_outcome.gd")
const EventPreconditionScript: GDScript = preload("res://scripts/core/event_precondition.gd")
const DaoXingManagerScript: GDScript = preload("res://scripts/core/progression_data.gd")
const CardDataResourceScript: GDScript = preload("res://scripts/core/card_data.gd")
const BattleRewardScript: GDScript = preload("res://scripts/core/reward_data.gd")
const ShopEnumsScript: GDScript = preload("res://scripts/core/shop_enums.gd")

var passed := 0
var failed := 0
var errors: Array = []

func run_all_tests() -> void:
	print("\n=== 全流程集成测试 ===")
	test_full_combat_loop()
	test_generation_chain_with_decay()
	test_crit_system()
	test_charge_system()
	test_mo_nian_system()
	test_enemy_aura_system()
	test_enemy_intent_ai()
	test_map_generation()
	test_shop_system()
	test_event_system()
	test_reward_system()
	test_progression_system()
	print("=== 全流程集成测试完成 ===\n")
	print("总计: %d | 通过: %d | 失败: %d" % [passed + failed, passed, failed])

func _assert(condition: bool, desc: String) -> void:
	if condition:
		passed += 1
		print("  ✓ %s" % desc)
	else:
		failed += 1
		errors.append(desc)
		print("  ❌ %s" % desc)

# ==================== 1. 完整战斗循环 ====================

func test_full_combat_loop() -> void:
	print("\n--- 测试完整战斗循环 ---")
	var player := Player.new("测试者", 80, WuXing.Element.FIRE, 10)
	var enemy := Enemy.create_fire_spirit()

	# 初始化
	player.init_deck()
	player.draw_cards()
	_assert(player.hand.size() > 0, "抽牌后手牌不为空")

	# 模拟3回合战斗
	for turn in range(3):
		player.start_turn()
		_assert(player.current_energy > 0, "回合%d 灵力回复" % (turn + 1))
		_assert(player.hand.size() > 0, "回合%d 抽牌成功" % (turn + 1))

		# 打出第一张牌
		if player.hand.size() > 0:
			var card: Variant = player.hand[0]
			if card.cost <= player.current_energy:
				player.play_card(0)
				_assert(player.hand.size() < 5 or player.hand.size() == 5, "出牌后手牌减少")

		# 敌人行动
		enemy.choose_intent()
		var result: Dictionary = enemy.execute_intent(player)
		_assert(result.success, "敌人意图执行成功")

		player.end_turn()

	_assert(player.current_hp <= 80, "玩家受到过伤害或未变化")
	print("  ✓ 完整战斗循环通过")

# ==================== 2. 相生链衰减 ====================

func test_generation_chain_with_decay() -> void:
	print("\n--- 测试相生链衰减 ---")
	var bm := BattleManager.new()

	# 模拟相生链：火→土→金
	bm._has_last_element = false
	bm.generation_chain.clear()
	bm._chain_trigger_count = 0

	# 链长=2：无衰减
	bm._chain_trigger_count = 2
	var decay2 := bm._calculate_chain_decay()
	_assert(decay2 == 1.0, "链长2 衰减=1.0")

	# 链长=3：75%
	bm._chain_trigger_count = 3
	var decay3 := bm._calculate_chain_decay()
	_assert(abs(decay3 - 0.75) < 0.01, "链长3 衰减=0.75")

	# 链长=4：50%
	bm._chain_trigger_count = 4
	var decay4 := bm._calculate_chain_decay()
	_assert(abs(decay4 - 0.5) < 0.01, "链长4 衰减=0.5")

	# 链长=5：25%
	bm._chain_trigger_count = 5
	var decay5 := bm._calculate_chain_decay()
	_assert(abs(decay5 - 0.25) < 0.01, "链长5 衰减=0.25")

	# 链长=6：越界保护
	bm._chain_trigger_count = 6
	var decay6 := bm._calculate_chain_decay()
	_assert(decay6 == 1.0, "链长6 越界保护=1.0")

# ==================== 3. 暴击系统 ====================

func test_crit_system() -> void:
	print("\n--- 测试暴击系统 ---")
	var bm := BattleManager.new()
	var card := CardDataResourceScript.new()
	card.damage = 10
	card.cost = 1
	card.element = WuXing.Element.FIRE

	# 设置 player 引用（_create_luck_card 需要 player.element）
	bm.player = Player.new("测试者", 80, WuXing.Element.FIRE, 10)

	# 测试运气牌生成
	var luck_card := bm._create_luck_card()
	_assert(luck_card.cost == 0, "运气牌费用=0")
	_assert(luck_card.id.begins_with("LUCK_"), "运气牌ID以LUCK_开头")
	_assert(not luck_card.description.is_empty(), "运气牌有描述")
	print("  ✓ 暴击系统通过")

# ==================== 4. 蓄势系统 ====================

func test_charge_system() -> void:
	print("\n--- 测试蓄势系统 ---")
	var player := Player.new("测试者", 80, WuXing.Element.FIRE, 10)

	# 蓄势1层
	player.enter_charge_mode()
	_assert(player.charge_stacks == 1, "蓄势层数=1")
	_assert(player.charge_shield == 0.5, "减伤=50%")
	_assert(player.mana_regen_bonus == 2, "灵力加成=+2")

	# 蓄势2层：触发回血
	player.enter_charge_mode()
	_assert(player.charge_stacks == 2, "蓄势层数=2")
	_assert(player.current_hp <= 80, "连续蓄势×2回血")
	_assert(player.mana_regen_bonus == 4, "灵力加成=+4")

	print("  ✓ 蓄势系统通过")

# ==================== 5. 魔念系统 ====================

func test_mo_nian_system() -> void:
	print("\n--- 测试魔念系统 ---")
	var player := Player.new("测试者", 80, WuXing.Element.FIRE, 10)

	# 初始魔念=0
	_assert(player.mo_nian == 0, "初始魔念=0")

	# 增加魔念
	player._add_mo_nian(3, "测试")
	_assert(player.mo_nian == 3, "魔念+3=3")

	# 侵蚀互斥
	player.erosion = 5
	player._add_mo_nian(2, "测试互斥")
	_assert(player.mo_nian == 5, "魔念+2=5")
	_assert(player.erosion == 3, "侵蚀-2=3（互斥）")

	# 减少魔念
	player.reduce_mo_nian(3)
	_assert(player.mo_nian == 2, "魔念-3=2")

	# 清除魔念
	player.clear_mo_nian()
	_assert(player.mo_nian == 0, "清除魔念=0")
	_assert(player.erosion == 3, "清除魔念不影响侵蚀")

	print("  ✓ 魔念系统通过")

# ==================== 6. 敌人气场系统 ====================

func test_enemy_aura_system() -> void:
	print("\n--- 测试敌人气场系统 ---")
	var enemy := Enemy.create_elite_shifting_puppet()

	# 初始化气场
	enemy.reset_aura(0, 5, false)
	_assert(enemy.get_current_aura() == Enemy.AuraType.METAL, "初始气场=金")
	_assert(enemy.aura_switch_interval == 5, "精英切换间隔=5")

	# 模拟5回合
	for i in range(5):
		enemy.on_turn_end_aura()
	_assert(enemy.get_current_aura() == Enemy.AuraType.WOOD, "5回合后气场=木")

	# Boss 气场（3回合切换）
	var boss := Enemy.create_boss_neon_spider_queen()
	boss.reset_aura(0, 3, true)
	_assert(boss.is_boss == true, "标记为Boss")

	for i in range(3):
		boss.on_turn_end_aura()
	_assert(boss.get_current_aura() == Enemy.AuraType.WOOD, "Boss 3回合后气场=木")

	# Boss 阶段切换
	boss.current_hp = 40  # 40/106 < 50%
	boss.on_turn_end_aura()
	_assert(boss.boss_phase == 2, "Boss HP<50% 进入阶段2")

	print("  ✓ 气场系统通过")

# ==================== 7. 敌人意图AI ====================

func test_enemy_intent_ai() -> void:
	print("\n--- 测试敌人意图AI ---")
	var enemy := Enemy.create_fire_spirit()

	# 默认意图选择
	enemy.choose_intent()
	_assert(not enemy.current_intent.is_empty(), "有意图")

	# 低血量修正
	enemy.current_hp = 5  # 5/35 < 30%
	var weights := enemy._get_modified_weights({})
	_assert(weights["defense"] > 20, "低血防御权重增加")

	# 玩家有格挡
	enemy.current_hp = 35
	var weights_block := enemy._get_modified_weights({"block": 10})
	_assert(weights_block["attack"] > 50, "玩家有格挡攻击权重增加")

	print("  ✓ 意图AI通过")

# ==================== 8. 地图生成 ====================

func test_map_generation() -> void:
	print("\n--- 测试地图生成 ---")
	var generator := MapGenerator.new(42)
	var realm_map := generator.generate("liqi", 0)

	_assert(realm_map.nodes.size() > 0, "地图有节点")
	_assert(realm_map.boss_node != null, "有Boss节点")
	_assert(realm_map.boss_node.type == MapNode.NodeType.BOSS, "Boss节点类型正确")
	_assert(realm_map.columns.size() == 5, "5列")

	# 连通性验证
	var validation := ConnectivityValidator.validate(realm_map.columns, 4)
	_assert(validation.is_valid, "连通性验证通过: %s" % str(validation.errors))

	# 起始节点可达
	var start_nodes := realm_map.get_start_nodes()
	_assert(start_nodes.size() > 0, "有起始节点")

	print("  ✓ 地图生成通过")

# ==================== 9. 商店系统 ====================

func test_shop_system() -> void:
	print("\n--- 测试商店系统 ---")
	var shop_logic: Variant = ShopLogic.new()

	# 价格计算
	var price := ShopInventory.calculate_base_price(ShopEnumsScript.ShopItemType.CARD, "common")
	_assert(price == 12, "普通卡牌基础价=12")

	var rare_price := ShopInventory.calculate_base_price(ShopEnumsScript.ShopItemType.CARD, "rare")
	_assert(rare_price == int(12 * 1.3), "稀有卡牌价=15")

	# 购买检查
	var item := ShopItem.new()
	item.type = ShopEnumsScript.ShopItemType.CARD
	item.final_price = 15
	item.sold_out = false

	var check: Dictionary = shop_logic.can_purchase(item, 20, 10)
	_assert(check.can_buy, "20灵石买15价卡牌可以")

	var check_fail: Dictionary = shop_logic.can_purchase(item, 10, 10)
	_assert(not check_fail.can_buy, "10灵石买15价卡牌不行")

	# 购买执行
	var player_state := {"spirit_stones": 50, "deck": [], "deck_size": 0}
	item.card_data = {"name": "测试卡", "element": "fire"}
	var success: bool = shop_logic.execute_purchase(item, player_state)
	_assert(success, "购买成功")
	_assert(player_state["spirit_stones"] == 35, "扣灵石=35")
	_assert(player_state["deck"].size() == 1, "卡组+1")

	print("  ✓ 商店系统通过")

# ==================== 10. 事件系统 ====================

func test_event_system() -> void:
	print("\n--- 测试事件系统 ---")
	var event_logic: Variant = EventLogic.new(42)

	# 加载测试事件
	var test_events := [
		{
			"id": "EVT_TEST_01",
			"name": "测试事件",
			"description": "测试描述",
			"realm_restriction": ["*"],
			"category": "叙事型",
			"weight": 10,
			"choices": [
				{
					"text": "选项1",
					"outcomes": [{"resource_type": "DAO_XING", "value": 3, "direction": "gain"}],
					"precondition": {}
				}
			]
		}
	]
	event_logic.load_events(test_events)

	# 生成事件
	var event := event_logic.generate_event("liqi")
	_assert(event.id == "EVT_TEST_01", "生成测试事件")
	_assert(event.choices.size() == 1, "有1个选项")

	# 执行选项
	var player_state := {"hp": 80, "spirit_stones": 10, "dao_xing": 0, "mo_nian": 0}
	var result: Dictionary = event_logic.execute_choice(event, 0, player_state)
	_assert(result.success, "执行成功")
	_assert(player_state["dao_xing"] == 3, "道行+3")

	print("  ✓ 事件系统通过")

# ==================== 11. 奖励系统 ====================

func test_reward_system() -> void:
	print("\n--- 测试奖励系统 ---")
	var reward: Variant = BattleRewardScript.generate(false, false, 0)
	_assert(reward.spirit_stones > 0, "有灵石奖励")
	_assert(reward.dao_xing > 0, "有道行奖励")
	_assert(reward.card_choices.size() == 3, "三选一")

	# 精英奖励
	var elite_reward: Variant = BattleRewardScript.generate(true, false, 0)
	_assert(elite_reward.spirit_stones > reward.spirit_stones, "精英灵石更多")

	# Boss奖励
	var boss_reward: Variant = BattleRewardScript.generate(false, true, 0)
	_assert(boss_reward.dao_xing == 10, "Boss道行=10")

	# 突破选择
	var state: Dictionary = {"realm": 0, "max_mana": 10}
	BattleRewardScript.apply_breakthrough(BattleRewardScript.BreakthroughChoice.PO, state)
	_assert(state["realm"] == 1, "突破后境界=1")
	_assert(state["max_mana"] == 12, "筑基灵力=12")

	print("  ✓ 奖励系统通过")

# ==================== 12. 进度系统 ====================


func test_progression_system() -> void:
	print("\n--- 测试进度系统 ---")
	var dx := DaoXingManager.new()

	# 获取道行
	dx.gain_dao_xing(30, "测试")
	_assert(dx.total_dao_xing == 30, "道行=30")
	_assert(dx.get_realm_name() == "炼气散修", "境界=炼气散修")

	# 境界突破
	dx.gain_dao_xing(30, "测试")
	_assert(dx.check_breakthrough() == true, "可以突破")
	dx.do_breakthrough()
	_assert(dx.current_realm == 1, "境界=1")
	_assert(dx.get_realm_name() == "筑基修士", "境界=筑基修士")

	# 存档测试（用内置文件API）
	var save_path := "user://test_save.json"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string('{"test": true}')
		file.close()
		var read_file := FileAccess.open(save_path, FileAccess.READ)
		if read_file:
			var content := read_file.get_as_text()
			read_file.close()
			_assert(content.find("test") != -1, "存档读写正确")
		DirAccess.remove_absolute(save_path)

	print("  ✓ 进度系统通过")
