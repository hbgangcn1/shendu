## 卡牌数据资源类
## 定义单张卡牌的所有属性（按 design/core-loop/02-card-schema.md §1.1）
## JSON 加载时按 spec 字段读取，运行时用 int enum 提升性能
## 使用 Resource 而非 Node，支持 JSON 序列化

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

extends Resource

# ==================== 基础属性（spec 字段名） ====================

var id: String = ""                            ## 格式 MC-{ABBR}-{SEQ}
var name: String = ""                          ## 显示名（按 spec，不是 card_name）
var description: String = ""
var short_desc: String = ""                    ## 8 字内简写（手牌直接显示），可选；为空时从 description 自动截取
var cost: int = 0
var element: WuXing.Element = 0 as WuXing.Element  ## 0=金 1=木 2=水 3=火 4=土（JSON 是 string）
var card_kind: int = 0                         ## 0=攻击 1=防御 2=特殊 3=辅助（JSON 是 string）
var rarity: int = 0                            ## 0=普通 1=稀有 2=史诗 3=传说（JSON 是 string）
var art_path: String = ""                      ## 卡牌立绘图片路径（spec 字段）

# ==================== PCG 命名字段（spec 02-card-schema.md §4） ====================

var name_prefix: String = ""
var name_core: String = ""
var name_suffix: String = ""

# ==================== 效果数值（从 effects[] 同步） ====================

var damage: int = 0
var block: int = 0
var draw_cards: int = 0
var heal: int = 0

# ==================== 进阶字段（spec §1.1） ====================

var upgrade_id: String = ""                    ## 升级后卡牌 ID
var character_lock: String = ""                ## 限定角色 ID（空=通用）
var engraving_slot_count: int = 0              ## 刻印槽上限（按稀有度）
var erosion_tolerance: int = 0                 ## 侵蚀耐受层数
var tags: Array = []                           ## 功能标签
var effects: Array = []                        ## 卡牌效果列表（spec trigger/action 格式）

# ==================== 字符串常量（spec enum 映射） ====================

const ELEMENT_STRING_TO_INT := {
	"metal": 0,
	"wood": 1,
	"water": 2,
	"fire": 3,
	"earth": 4,
}

const ELEMENT_INT_TO_STRING := ["metal", "wood", "water", "fire", "earth"]

const KIND_STRING_TO_INT := {
	"attack": 0,
	"defense": 1,
	"special": 2,
	"support": 3,
}

const KIND_INT_TO_STRING := ["attack", "defense", "special", "support"]

const RARITY_STRING_TO_INT := {
	"common": 0,
	"rare": 1,
	"epic": 2,
	"legend": 3,
}

const RARITY_INT_TO_STRING := ["common", "rare", "epic", "legend"]

## 刻印槽默认按稀有度（spec §1.4）
const ENGRAVING_SLOTS_BY_RARITY := [2, 3, 4, 4]
## 侵蚀耐受默认按稀有度（spec §1.4）
const EROSION_TOLERANCE_BY_RARITY := [3, 4, 5, 5]

# ==================== 辅助方法 ====================

## 从 spec string 转 int enum（加载时调用）
func set_element_from_string(s: String) -> void:
	element = ELEMENT_STRING_TO_INT.get(s, 0) as WuXing.Element

func set_kind_from_string(s: String) -> void:
	card_kind = KIND_STRING_TO_INT.get(s, 0)

func set_rarity_from_string(s: String) -> void:
	rarity = RARITY_STRING_TO_INT.get(s, 0)

## 元素名（中文）
func get_element_name() -> String:
	match element:
		0: return "金"
		1: return "木"
		2: return "水"
		3: return "火"
		4: return "土"
	return "?"

## 类型名（中文）
func get_kind_name() -> String:
	match card_kind:
		0: return "攻击"
		1: return "防御"
		2: return "特殊"
		3: return "辅助"
	return "未知"

## 稀有度名（中文）
func get_rarity_name() -> String:
	match rarity:
		0: return "普通"
		1: return "稀有"
		2: return "史诗"
		3: return "传说"
	return "未知"

func is_attack() -> bool:
	return card_kind == 0

func is_defense() -> bool:
	return card_kind == 1

## 是否消耗（打出后放逐）—— 按 spec §1.5 用 tags 实现
func is_exhaust() -> bool:
	return tags.has("exhaust")

## 完整渲染名（spec §4.1 三段式）
func get_display_name() -> String:
	if name != "":
		return name
	# fallback: 从 prefix/core/suffix 拼接
	var parts: Array = []
	if name_prefix != "": parts.append(name_prefix)
	if name_core != "": parts.append(name_core)
	if name_suffix != "": parts.append(name_suffix)
	if parts.is_empty():
		return "?"
	return "".join(parts)

## 概要（用于牌组管理 UI）
func get_summary() -> String:
	return "[%s]%s (%s) 费%d 伤%d 盾%d" % [
		get_element_name(), get_display_name(), get_kind_name(), cost, damage, block
	]

## 自动按稀有度填刻印槽/侵蚀耐受（spec §1.4）
func apply_default_advanced_stats() -> void:
	if engraving_slot_count == 0:
		engraving_slot_count = ENGRAVING_SLOTS_BY_RARITY[rarity]
	if erosion_tolerance == 0:
		erosion_tolerance = EROSION_TOLERANCE_BY_RARITY[rarity]

## 序列化到 Dictionary（GameState.collection 用）
func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"description": description,
		"short_desc": short_desc,
		"cost": cost,
		"element": element,
		"card_kind": card_kind,
		"rarity": rarity,
		"art_path": art_path,
		"name_prefix": name_prefix,
		"name_core": name_core,
		"name_suffix": name_suffix,
		"damage": damage,
		"block": block,
		"heal": heal,
		"draw_cards": draw_cards,
		"upgrade_id": upgrade_id,
		"character_lock": character_lock,
		"engraving_slot_count": engraving_slot_count,
		"erosion_tolerance": erosion_tolerance,
		"tags": tags,
		"effects": effects,
	}
