## 主场景入口脚本
## 启动时打印五行系统自测，确认核心模块正常

# implements: design/01-player-experience.md
# implements_philosophy: rule_1_core_loop_first
# avoids_red_line: red_8_tutorial_hell

extends Node2D

func _ready() -> void:
	print("========================================")
	print("  蜃都 — 项目启动")
	print("========================================")
	_test_wuxing()
	_test_card_pool()
	print("========================================")
	print("  所有自测通过 ✓")
	print("========================================")
	# 自测完成后进入主菜单
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")

## 五行系统自测
func _test_wuxing() -> void:
	print("\n--- 五行系统自测 ---")

	# 测试相生
	assert(WuXing.is_generation(WuXing.Element.WOOD, WuXing.Element.FIRE) == true, "木→火 应为相生")
	assert(WuXing.is_generation(WuXing.Element.FIRE, WuXing.Element.EARTH) == true, "火→土 应为相生")
	assert(WuXing.is_generation(WuXing.Element.EARTH, WuXing.Element.METAL) == true, "土→金 应为相生")
	assert(WuXing.is_generation(WuXing.Element.METAL, WuXing.Element.WATER) == true, "金→水 应为相生")
	assert(WuXing.is_generation(WuXing.Element.WATER, WuXing.Element.WOOD) == true, "水→木 应为相生")
	assert(WuXing.is_generation(WuXing.Element.WOOD, WuXing.Element.METAL) == false, "木→金 不应相生")
	print("  ✓ 相生判定正确")

	# 测试相克
	assert(WuXing.is_counter(WuXing.Element.METAL, WuXing.Element.WOOD) == true, "金克木")
	assert(WuXing.is_counter(WuXing.Element.WOOD, WuXing.Element.EARTH) == true, "木克土")
	assert(WuXing.is_counter(WuXing.Element.EARTH, WuXing.Element.WATER) == true, "土克水")
	assert(WuXing.is_counter(WuXing.Element.WATER, WuXing.Element.FIRE) == true, "水克火")
	assert(WuXing.is_counter(WuXing.Element.FIRE, WuXing.Element.METAL) == true, "火克金")
	print("  ✓ 相克判定正确")

	# 测试伤害计算
	var dmg1: int = WuXing.calculate_final_damage(10, WuXing.Element.FIRE, WuXing.Element.METAL, false)
	assert(dmg1 == 20, "火打金（克制）应为 20，实际为 %d" % dmg1)

	var dmg2: int = WuXing.calculate_final_damage(10, WuXing.Element.FIRE, WuXing.Element.WATER, false)
	assert(dmg2 == 5, "火打水（被克）应为 5，实际为 %d" % dmg2)

	var dmg3: int = WuXing.calculate_final_damage(10, WuXing.Element.WOOD, WuXing.Element.FIRE, true)
	assert(dmg3 == 15, "木→火（相生）应为 15，实际为 %d" % dmg3)

	print("  ✓ 伤害计算正确")

## 卡池自测（card_pool.gd 现加载 mvp+zhuji+jindan 三池共 45 张）
## 注：EA 范围 45 张（5属性×9张），详见 design/00-MASTER.md §十
## 补卡记录 2026-06-29：mvp 9→17（+8 common），zhuji 9→15（+4 common+2 rare），jindan 7→13（+2 common+1 rare+2 epic+1 legend）
func _test_card_pool() -> void:
	print("\n--- 卡池自测 ---")
	var pool_size: int = CardPool.get_pool_size()
	assert(pool_size == 45, "总卡池应为 45 张（EA 范围），实际为 %d" % pool_size)

	var fire_bolt = CardPool.get_card("MC-FI-001")
	assert(fire_bolt != null, "MC-FI-001 烈焰弹应存在")
	assert(fire_bolt.damage == 10, "烈焰弹伤害应为 10")
	assert(fire_bolt.element == WuXing.Element.FIRE, "烈焰弹应为火属性")

	# 验证补的 0 费卡
	var jin_jing = CardPool.get_card("MC-ME-003")
	assert(jin_jing != null, "MC-ME-003 金精聚应存在（0 费 support）")
	assert(jin_jing.cost == 0, "金精聚费用应为 0")

	# 验证补的传说卡（card_pool.gd 已做 rarity 偏移 -1，jindan 4 → spec 3）
	var ye_huo = CardPool.get_card("MC-FI-006")
	assert(ye_huo != null, "MC-FI-006 业火焚天应存在（legend）")
	assert(ye_huo.rarity == 3, "业火焚天应为传说（spec rarity=3）")

	print("  ✓ 卡池加载正确（%d 张卡牌）" % pool_size)
