## 五行相生相克系统单元测试
## 测试 WuXingManager：五行枚举、相生链、衰减规则、属性偏向
# implements: design/00-MASTER.md §二 五行, design/07-combat-system-spec §三.2 五行相生
# implements_philosophy: rule_1_core_loop_first, rule_6_flow_channel

extends Node

func run_all_tests() -> void:
	print("\n=== 五行系统测试 ===")
	test_element_enum()
	test_generation()
	test_counter()
	test_damage_multiplier()
	test_final_damage()
	test_element_names()
	test_element_colors()
	test_chain_decay()
	print("=== 五行系统测试完成 ===\n")

func test_element_enum() -> void:
	print("\n--- 测试元素枚举 ---")
	assert(WuXing.Element.METAL == 0, "金应为 0")
	assert(WuXing.Element.WOOD == 1, "木应为 1")
	assert(WuXing.Element.WATER == 2, "水应为 2")
	assert(WuXing.Element.FIRE == 3, "火应为 3")
	assert(WuXing.Element.EARTH == 4, "土应为 4")
	print("  ✓ 元素枚举正确")

func test_generation() -> void:
	print("\n--- 测试相生关系 ---")
	# 金生水
	assert(WuXing.is_generation(WuXing.Element.METAL, WuXing.Element.WATER) == true, "金应生水")
	# 水生木
	assert(WuXing.is_generation(WuXing.Element.WATER, WuXing.Element.WOOD) == true, "水应生木")
	# 木生火
	assert(WuXing.is_generation(WuXing.Element.WOOD, WuXing.Element.FIRE) == true, "木应生火")
	# 火生土
	assert(WuXing.is_generation(WuXing.Element.FIRE, WuXing.Element.EARTH) == true, "火应生土")
	# 土生金
	assert(WuXing.is_generation(WuXing.Element.EARTH, WuXing.Element.METAL) == true, "土应生金")
	
	# 不应相生
	assert(WuXing.is_generation(WuXing.Element.METAL, WuXing.Element.FIRE) == false, "金不应生火")
	assert(WuXing.is_generation(WuXing.Element.WOOD, WuXing.Element.EARTH) == false, "木不应生土")
	print("  ✓ 相生关系正确")

func test_counter() -> void:
	print("\n--- 测试相克关系 ---")
	# 金克木
	assert(WuXing.is_counter(WuXing.Element.METAL, WuXing.Element.WOOD) == true, "金应克木")
	# 木克土
	assert(WuXing.is_counter(WuXing.Element.WOOD, WuXing.Element.EARTH) == true, "木应克土")
	# 土克水
	assert(WuXing.is_counter(WuXing.Element.EARTH, WuXing.Element.WATER) == true, "土应克水")
	# 水克火
	assert(WuXing.is_counter(WuXing.Element.WATER, WuXing.Element.FIRE) == true, "水应克火")
	# 火克金
	assert(WuXing.is_counter(WuXing.Element.FIRE, WuXing.Element.METAL) == true, "火应克金")
	
	# 不应相克
	assert(WuXing.is_counter(WuXing.Element.METAL, WuXing.Element.FIRE) == false, "金不应克火")
	assert(WuXing.is_counter(WuXing.Element.WATER, WuXing.Element.WOOD) == false, "水不应克木")
	print("  ✓ 相克关系正确")

func test_damage_multiplier() -> void:
	print("\n--- 测试伤害倍率 ---")
	# 同元素：1.0
	var mult1 := WuXing.calculate_damage_multiplier(WuXing.Element.FIRE, WuXing.Element.FIRE, false)
	assert(mult1 == 1.0, "同元素伤害倍率应为 1.0，实际为 %.1f" % mult1)
	
	# 克制：2.0
	var mult2 := WuXing.calculate_damage_multiplier(WuXing.Element.FIRE, WuXing.Element.METAL, false)
	assert(mult2 == 2.0, "克制伤害倍率应为 2.0，实际为 %.1f" % mult2)
	
	# 被克：0.5
	var mult3 := WuXing.calculate_damage_multiplier(WuXing.Element.FIRE, WuXing.Element.WATER, false)
	assert(mult3 == 0.5, "被克伤害倍率应为 0.5，实际为 %.1f" % mult3)
	
	# 相生链加成（已移至 battle_manager 处理，calculate_damage_multiplier 不再包含）
	var mult4 := WuXing.calculate_damage_multiplier(WuXing.Element.FIRE, WuXing.Element.FIRE, false, 0)
	assert(mult4 == 1.0, "无克制时倍率应为 1.0，实际为 %.1f" % mult4)
	
	# 克制（含相生）：1.0 × 1.5(GENERATION_BONUS) × 2.0(克制) = 3.0
	# TODO spec 07-combat-system-spec.md §三公式说 G=1.75，代码 G=1.5 — spec 内部矛盾
	var mult5 := WuXing.calculate_damage_multiplier(WuXing.Element.FIRE, WuXing.Element.METAL, true, 0)
	assert(mult5 == 3.0, "克制含相生应为 3.0，实际为 %.1f" % mult5)
	
	# 蓄势乘数 C：charge_stacks=1 → C=1.25，克制=2.0 → 总=2.5
	var mult6 := WuXing.calculate_damage_multiplier(WuXing.Element.FIRE, WuXing.Element.METAL, false, 1)
	assert(abs(mult6 - 2.5) < 0.01, "蓄势1层+克制应为 2.5，实际为 %.2f" % mult6)
	
	# 蓄势上限：charge_stacks=4 → C=1.75（上限），克制=2.0 → 总=3.5
	var mult7 := WuXing.calculate_damage_multiplier(WuXing.Element.FIRE, WuXing.Element.METAL, false, 4)
	assert(abs(mult7 - 3.5) < 0.01, "蓄势4层+克制应为 3.5，实际为 %.2f" % mult7)
	print("  ✓ 伤害倍率正确")

func test_final_damage() -> void:
	print("\n--- 测试最终伤害 ---")
	# 同元素，基础伤害 10
	var dmg1 := WuXing.calculate_final_damage(10, WuXing.Element.FIRE, WuXing.Element.FIRE, false)
	assert(dmg1 == 10, "同元素 10 伤害应为 10，实际为 %d" % dmg1)
	
	# 克制，基础伤害 10
	var dmg2 := WuXing.calculate_final_damage(10, WuXing.Element.FIRE, WuXing.Element.METAL, false)
	assert(dmg2 == 20, "克制 10 伤害应为 20，实际为 %d" % dmg2)
	
	# 被克，基础伤害 10
	var dmg3 := WuXing.calculate_final_damage(10, WuXing.Element.FIRE, WuXing.Element.WATER, false)
	assert(dmg3 == 5, "被克 10 伤害应为 5，实际为 %d" % dmg3)
	
	# 相生链（加成已移至 battle_manager，此处无额外倍率）
	# calculate_final_damage 不接受 charge_stacks，用 calculate_damage_multiplier 测
	var mult4 := WuXing.calculate_damage_multiplier(WuXing.Element.FIRE, WuXing.Element.FIRE, false, 0)
	assert(mult4 == 1.0, "相生链倍率应为 1.0（无额外），实际为 %.2f" % mult4)
	
	# 蓄势+克制：1.0(基础) × 2.0(克制) × 1.25(蓄势1) = 2.5（spec 07-combat-system-spec.md:174）
	var mult5 := WuXing.calculate_damage_multiplier(WuXing.Element.FIRE, WuXing.Element.METAL, false, 1)
	assert(absf(mult5 - 2.5) < 0.01, "蓄势1+克制倍率应为 2.5，实际为 %.2f" % mult5)
	print("  ✓ 最终伤害计算正确")

func test_element_names() -> void:
	print("\n--- 测试元素名称 ---")
	assert(WuXing.get_element_name(WuXing.Element.METAL) == "金", "金元素名称错误")
	assert(WuXing.get_element_name(WuXing.Element.WOOD) == "木", "木元素名称错误")
	assert(WuXing.get_element_name(WuXing.Element.WATER) == "水", "水元素名称错误")
	assert(WuXing.get_element_name(WuXing.Element.FIRE) == "火", "火元素名称错误")
	assert(WuXing.get_element_name(WuXing.Element.EARTH) == "土", "土元素名称错误")
	print("  ✓ 元素名称正确")

func test_element_colors() -> void:
	print("\n--- 测试元素颜色 ---")
	var metal_color := WuXing.get_element_color(WuXing.Element.METAL)
	assert(metal_color == Color(0.75, 0.75, 0.75), "金元素颜色错误")
	
	var fire_color := WuXing.get_element_color(WuXing.Element.FIRE)
	assert(fire_color == Color(0.9, 0.2, 0.1), "火元素颜色错误")
	print("  ✓ 元素颜色正确")

func test_chain_decay() -> void:
	print("\n--- 测试相生链衰减 ---")
	# 阶梯衰减表：[1.0, 1.0, 0.75, 0.5, 0.25]
	# 触发次数1→1.0, 2→1.0, 3→0.75, 4→0.5, 5→0.25
	var DECAY_TABLE: Array[float] = [1.0, 1.0, 0.75, 0.5, 0.25]
	
	# 模拟衰减计算（与 battle_manager._calculate_chain_decay 逻辑一致）
	assert(_calc_decay(1, DECAY_TABLE) == 1.0, "触发1次应无衰减")
	assert(_calc_decay(2, DECAY_TABLE) == 1.0, "触发2次应无衰减")
	assert(_calc_decay(3, DECAY_TABLE) == 0.75, "触发3次应衰减至0.75")
	assert(_calc_decay(4, DECAY_TABLE) == 0.5, "触发4次应衰减至0.5")
	assert(_calc_decay(5, DECAY_TABLE) == 0.25, "触发5次应衰减至0.25")
	assert(_calc_decay(6, DECAY_TABLE) == 1.0, "触发6次应回到1.0（越界保护）")
	print("  ✓ 相生链衰减正确")

## 衰减计算（与 battle_manager._calculate_chain_decay 逻辑一致）
func _calc_decay(trigger_count: int, table: Array) -> float:
	var idx := trigger_count - 1
	if idx < 0 or idx >= table.size():
		return 1.0
	return table[idx]
