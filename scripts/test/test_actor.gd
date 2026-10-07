## Actor 基类单元测试
## 测试 Actor 的生命值、护盾、伤害计算
# implements: design/07-combat-system-spec §三.1 Actor 基础属性
# implements_philosophy: rule_1_core_loop_first

extends Node

func run_all_tests() -> void:
	print("\n=== Actor 测试 ===")
	test_actor_creation()
	test_take_damage()
	test_shield_absorption()
	test_heal()
	test_death()
	test_element_effects()
	test_status_summary()
	print("=== Actor 测试完成 ===\n")

func test_actor_creation() -> void:
	print("\n--- 测试 Actor 创建 ---")
	var actor := Actor.new("测试单位", 100, WuXing.Element.FIRE)
	assert(actor.actor_name == "测试单位", "名称错误")
	assert(actor.max_hp == 100, "最大 HP 错误")
	assert(actor.current_hp == 100, "当前 HP 错误")
	assert(actor.shield == 0, "初始护盾应为 0")
	assert(actor.is_alive == true, "初始应存活")
	assert(actor.element == WuXing.Element.FIRE, "元素错误")
	print("  ✓ Actor 创建正确")

func test_take_damage() -> void:
	print("\n--- 测试受到伤害 ---")
	var actor := Actor.new("测试", 100, WuXing.Element.FIRE)
	
	# 基础伤害
	var dmg1 := actor.take_damage(10, WuXing.Element.FIRE, false)
	assert(dmg1 == 10, "基础伤害应为 10，实际为 %d" % dmg1)
	assert(actor.current_hp == 90, "HP 应为 90，实际为 %d" % actor.current_hp)
	
	# 克制伤害（火打金）
	var actor2 := Actor.new("金单位", 100, WuXing.Element.METAL)
	var dmg2 := actor2.take_damage(10, WuXing.Element.FIRE, false)
	assert(dmg2 == 20, "克制伤害应为 20，实际为 %d" % dmg2)
	assert(actor2.current_hp == 80, "HP 应为 80")
	
	# 被克伤害（火打水）
	var actor3 := Actor.new("水单位", 100, WuXing.Element.WATER)
	var dmg3 := actor3.take_damage(10, WuXing.Element.FIRE, false)
	assert(dmg3 == 5, "被克伤害应为 5，实际为 %d" % dmg3)
	assert(actor3.current_hp == 95, "HP 应为 95")
	print("  ✓ 伤害计算正确")

func test_shield_absorption() -> void:
	print("\n--- 测试护盾吸收 ---")
	var actor := Actor.new("测试", 100, WuXing.Element.FIRE)
	
	# 获得护盾
	actor.gain_shield(10)
	assert(actor.shield == 10, "护盾应为 10")
	
	# 伤害小于护盾
	actor.take_damage(5, WuXing.Element.FIRE, false)
	assert(actor.shield == 5, "护盾应为 5")
	assert(actor.current_hp == 100, "HP 不应减少")
	
	# 伤害大于护盾
	actor.take_damage(10, WuXing.Element.FIRE, false)
	assert(actor.shield == 0, "护盾应为 0")
	assert(actor.current_hp == 95, "HP 应为 95")
	print("  ✓ 护盾吸收正确")

func test_heal() -> void:
	print("\n--- 测试治疗 ---")
	var actor := Actor.new("测试", 100, WuXing.Element.FIRE)
	actor.take_damage(50, WuXing.Element.FIRE, false)
	assert(actor.current_hp == 50, "HP 应为 50")
	
	# 正常治疗
	var healed := actor.heal(20)
	assert(healed == 20, "治疗量应为 20，实际为 %d" % healed)
	assert(actor.current_hp == 70, "HP 应为 70")
	
	# 溢出治疗
	var healed2 := actor.heal(50)
	assert(healed2 == 30, "溢出治疗应为 30，实际为 %d" % healed2)
	assert(actor.current_hp == 100, "HP 不应超过最大值")
	print("  ✓ 治疗正确")

func test_death() -> void:
	print("\n--- 测试死亡 ---")
	var actor := Actor.new("测试", 10, WuXing.Element.FIRE)
	actor.take_damage(15, WuXing.Element.FIRE, false)
	assert(actor.is_alive == false, "单位应死亡")
	assert(actor.current_hp == 0, "HP 应为 0")
	
	# 死亡后不应再受伤
	var dmg := actor.take_damage(10, WuXing.Element.FIRE, false)
	assert(dmg == 0, "死亡后伤害应为 0")
	assert(actor.current_hp == 0, "HP 应保持 0")
	
	# 死亡后不应治疗
	var healed := actor.heal(10)
	assert(healed == 0, "死亡后治疗应为 0")
	print("  ✓ 死亡处理正确")

func test_element_effects() -> void:
	print("\n--- 测试元素效果 ---")
	# 相生链加成（actor.take_damage 仍含相生加成 1.5×，TODO 重构移至 battle_manager）
	var actor := Actor.new("测试", 100, WuXing.Element.METAL)
	var dmg := actor.take_damage(10, WuXing.Element.FIRE, true)
	# 火克金 2.0 × 相生 1.5 = 3.0
	assert(dmg == 30, "相生+克制应为 30，实际为 %d" % dmg)

	# 不带相生时只有克制 2.0
	var actor2 := Actor.new("测试", 100, WuXing.Element.METAL)
	var dmg2 := actor2.take_damage(10, WuXing.Element.FIRE, false)
	assert(dmg2 == 20, "仅克制应为 20，实际为 %d" % dmg2)
	print("  ✓ 元素效果正确")

func test_status_summary() -> void:
	print("\n--- 测试状态摘要 ---")
	var actor := Actor.new("测试", 100, WuXing.Element.FIRE)
	var summary := actor.get_status_summary()
	assert(summary.find("测试") != -1, "摘要应包含名称")
	assert(summary.find("100/100") != -1, "摘要应包含 HP")
	assert(summary.find("火") != -1, "摘要应包含元素")
	print("  ✓ 状态摘要正确")
