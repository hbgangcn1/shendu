## 卡牌数据资源类
## 定义单张卡牌的所有属性
## 使用 Resource 而非 Node，支持 JSON 序列化

extends Resource

# ==================== 基础属性 ====================

var id: String = ""
var card_name: String = ""
var description: String = ""
var cost: int = 0
var element: int = 0            # WuXing.Element 枚举值
var card_type: int = 0          # 0=攻击 1=防御 2=特殊 3=辅助
var rarity: int = 0             # 0=普通 1=稀有 2=史诗 3=传说

# ==================== 效果数值 ====================

var damage: int = 0
var block: int = 0
var draw_cards: int = 0
var heal: int = 0

# ==================== 辅助方法 ====================

func get_type_name() -> String:
	match card_type:
		0: return "攻击"
		1: return "防御"
		2: return "特殊"
		3: return "辅助"
	return "未知"

func get_rarity_name() -> String:
	match rarity:
		0: return "普通"
		1: return "稀有"
		2: return "史诗"
		3: return "传说"
	return "未知"

func is_attack() -> bool:
	return card_type == 0

func is_defense() -> bool:
	return card_type == 1

func get_summary() -> String:
	var elem_name: String = WuXing.get_element_name(element)
	return "[%s]%s (%s) 费%d 伤%d 盾%d" % [
		elem_name, card_name, get_type_name(), cost, damage, block
	]
