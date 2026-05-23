## 主场景入口脚本
## 启动时打印五行系统自测，确认核心模块正常

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

## 卡池自测
func _test_card_pool() -> void:
	print("\n--- 卡池自测 ---")
	var pool_size: int = CardPool.get_pool_size()
	assert(pool_size == 9, "MVP 卡池应为 9 张，实际为 %d" % pool_size)

	var fire_bolt: CardData = CardPool.get_card("fire_bolt")
	assert(fire_bolt != null, "fire_bolt 应存在")
	assert(fire_bolt.damage == 10, "fire_bolt 伤害应为 10")
	assert(fire_bolt.element == WuXing.Element.FIRE, "fire_bolt 应为火属性")

	print("  ✓ 卡池加载正确（%d 张卡牌）" % pool_size)
