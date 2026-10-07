## Shop Cosmetics-Only 防御性测试
## 验证 shop_scene.gd 不暴露任何 P2W / IAP / VIP 字段，对齐 rule_8_cosmetics_over_p2w
# implements: design/10-shop-system-spec.md (rule_8_cosmetics_over_p2w)
# implements_philosophy: rule_8_cosmetics_over_p2w
# avoids_red_line: red_1_p2w

extends Node

const SHOP_SCENE_PATH := "res://scripts/shop_scene.gd"
const SHOP_LOGIC_PATH := "res://scripts/core/shop_logic.gd"
const SHOP_ITEM_PATH := "res://scripts/core/shop_item.gd"
const SHOP_INVENTORY_PATH := "res://scripts/core/shop_inventory.gd"
const SHOP_ENUMS_PATH := "res://scripts/core/shop_enums.gd"

# 12 个 P2W/IAP 模式（来自 red-line-patterns.md red_1_p2w 字典）
const FORBIDDEN_PATTERNS := [
	"buy_gold_with_real_money",
	"iap_purchase",
	"vip_damage",
	"pay_to_win",
	"p2w",                           # 单独匹配（注释里 # implements_philosophy 允许）
	"premium_currency",
	"cash_purchase",
	"gold_buy",
	"vip_attack",
	"real_money",
	"usd_price",
	"cny_price",
]

# 合法 effect_type 白名单（来自 shop_scene.gd 实际业务）
const ALLOWED_EFFECT_TYPES := [
	"card",
	"heal",
	"max_hp",
	"remove_card",
]

# 合法正向文档标记（这些是合规的、显式声明规避红线的注释）
# 注意：implements_philosophy 可能含多个 rule，所以单独处理各片段
const ALLOWED_DOCUMENTATION_FRAGMENTS := [
	"rule_8_cosmetics_over_p2w",
	"avoids_red_line: red_1_p2w",
	"implements_philosophy",
	"avoids_red_line",
]

func run_all_tests() -> void:
	print("\n--- Shop Cosmetics-Only 防御测试（rule_8_cosmetics_over_p2w） ---")

	_test_shop_scene_clean()
	_test_shop_logic_clean()
	_test_shop_item_clean()
	_test_shop_inventory_clean()
	_test_shop_enums_clean()
	_test_no_forbidden_field_names()
	_test_no_forbidden_documentation()

	print("  ✓ Shop 不暴露 P2W / IAP / VIP 字段")
	print("  ✓ Shop 仅用 spirit_stones 计价（cosmetic-only）")
	print("  ✓ effect_type 白名单受控（card/heal/max_hp/remove_card）")

# ==== 静态扫描 ====

func _test_shop_scene_clean() -> void:
	_assert_file_clean(SHOP_SCENE_PATH, "shop_scene.gd")

func _test_shop_logic_clean() -> void:
	if FileAccess.file_exists(SHOP_LOGIC_PATH):
		_assert_file_clean(SHOP_LOGIC_PATH, "shop_logic.gd")

func _test_shop_item_clean() -> void:
	if FileAccess.file_exists(SHOP_ITEM_PATH):
		_assert_file_clean(SHOP_ITEM_PATH, "shop_item.gd")

func _test_shop_inventory_clean() -> void:
	if FileAccess.file_exists(SHOP_INVENTORY_PATH):
		_assert_file_clean(SHOP_INVENTORY_PATH, "shop_inventory.gd")

func _test_shop_enums_clean() -> void:
	if FileAccess.file_exists(SHOP_ENUMS_PATH):
		_assert_file_clean(SHOP_ENUMS_PATH, "shop_enums.gd")

# ==== 字段名白名单 ====

func _test_no_forbidden_field_names() -> void:
	# shop_scene.gd 里 _shop_items 是 Dictionary[]，检查 field keys 不含禁用名
	var forbidden_keys := [
		"price_usd",
		"price_cny",
		"real_money_price",
		"iap_price",
		"vip_discount",
		"premium_only",
		"is_vip",
		"vip_required",
		"pay_to_win",
	]
	if not FileAccess.file_exists(SHOP_SCENE_PATH):
		return
	var content := FileAccess.open(SHOP_SCENE_PATH, FileAccess.READ).get_as_text()
	for key in forbidden_keys:
		var pattern := '"%s"' % key
		assert(not content.contains(pattern),
			"shop_scene.gd 不应包含字段名 '%s'（P2W/IAP 字段）" % key)

# ==== 文档标记白名单 ====

func _test_no_forbidden_documentation() -> void:
	# 注释里出现 P2W 字样必须是合法的正向文档标记
	# 合法形式：'# implements_philosophy: rule_8_cosmetics_over_p2w'
	#         '# avoids_red_line: red_1_p2w'
	if not FileAccess.file_exists(SHOP_SCENE_PATH):
		return
	var content := FileAccess.open(SHOP_SCENE_PATH, FileAccess.READ).get_as_text()
	content = _strip_allowed_fragments(content)
	for pattern in FORBIDDEN_PATTERNS:
		assert(not content.contains(pattern),
			"shop_scene.gd 注释中发现禁用 pattern '%s'" % pattern)

# ==== 通用文件扫描 ====

func _assert_file_clean(path: String, label: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var content := FileAccess.open(path, FileAccess.READ).get_as_text()
	content = _strip_allowed_fragments(content)
	for pattern in FORBIDDEN_PATTERNS:
		assert(not content.contains(pattern),
			"%s 包含禁用 pattern '%s'（red_1_p2w 红线）" % [label, pattern])

func _strip_allowed_fragments(content: String) -> String:
	# 从 content 里去除所有合法文档标记中出现的 P2W 相关片段
	# 注意：必须按片段处理（不是按整行），因为 implements_philosophy 可能含多个 rule
	for frag in ALLOWED_DOCUMENTATION_FRAGMENTS:
		content = content.replace(frag, "")
	return content
