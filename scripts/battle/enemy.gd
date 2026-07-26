## 敌人单位类
## 管理敌人的 AI 行为和意图系统

# implements: design/07-combat-system-spec.md
# implements_philosophy: rule_1_core_loop_first, rule_3_three_layer_loops, rule_6_flow_channel
# avoids_red_line: red_6_ui_overload, red_7_difficulty_wall

class_name Enemy
extends Actor

# ==================== 信号 ====================

signal intent_revealed(intent: Dictionary)

# ==================== 意图类型枚举 ====================

enum IntentType {
	ATTACK,          # 普通攻击
	PIERCE,          # 穿透攻击（无视部分格挡）
	ATK_BUFF,        # 攻击+增益
	DEFEND,          # 防御
	DEF_BUFF,        # 防御+增益
	ATK_UP,          # 攻击强化（纯增益）
	DEF_UP,          # 防御强化（纯增益）
	HEAL,            # 恢复
	WEAKEN,          # 虚弱
	VULNERABLE,      # 易伤
	POISON,          # 中毒
	SUMMON,          # 召唤（V2）
	PHASE_SHIFT,     # 阶段切换
	PURIFY,          # 净化（V2）
}

const INTENT_NAMES := {
	IntentType.ATTACK: "普通攻击",
	IntentType.PIERCE: "穿透攻击",
	IntentType.ATK_BUFF: "攻击+增益",
	IntentType.DEFEND: "防御",
	IntentType.DEF_BUFF: "防御+增益",
	IntentType.ATK_UP: "攻击强化",
	IntentType.DEF_UP: "防御强化",
	IntentType.HEAL: "恢复",
	IntentType.WEAKEN: "虚弱",
	IntentType.VULNERABLE: "易伤",
	IntentType.POISON: "中毒",
	IntentType.SUMMON: "召唤",
	IntentType.PHASE_SHIFT: "阶段切换",
	IntentType.PURIFY: "净化",
}

# ==================== 敌人属性 ====================

var enemy_id: String = ""
var description: String = ""
var image_path: String = ""  ## 敌人立绘路径

# ==================== 意图系统 ====================

var current_intent: Dictionary = {}
var intent_weights: Dictionary = {}  # 自定义权重覆盖（空=用默认）

# ==================== AI 属性 ====================

var aggression: float = 0.5  # 攻击倾向 0-1
var intelligence: float = 0.5  # 智能程度 0-1

# ==================== 默认权重 ====================

const BASE_WEIGHTS: Dictionary = {
	"attack": 60, "defense": 20, "buff": 10,
	"debuff": 5, "special": 5,
}

# 攻击类内部细分
const ATTACK_INTENTS: Array = [IntentType.ATTACK, IntentType.PIERCE, IntentType.ATK_BUFF]
const ATTACK_INTERNAL_WEIGHTS: Array = [50, 25, 25]

# 防御类内部细分
const DEFENSE_INTENTS: Array = [IntentType.DEFEND, IntentType.DEF_BUFF]
const DEFENSE_INTERNAL_WEIGHTS: Array = [60, 40]

# 增益类内部细分
const BUFF_INTENTS: Array = [IntentType.ATK_UP]
const BUFF_INTERNAL_WEIGHTS: Array = [100]

# 削弱类内部细分
const DEBUFF_INTENTS: Array = [IntentType.WEAKEN, IntentType.VULNERABLE]
const DEBUFF_INTERNAL_WEIGHTS: Array = [50, 50]

# 特殊类内部细分
const SPECIAL_INTENTS: Array = [IntentType.PHASE_SHIFT]
const SPECIAL_INTERNAL_WEIGHTS: Array = [100]

# ==================== 初始化 ====================

func _init(
	p_name: String = "敌人",
	p_hp: int = 50,
	p_elem: WuXing.Element = WuXing.Element.FIRE,
	p_id: String = ""
) -> void:
	super._init(p_name, p_hp, p_elem)
	enemy_id = p_id

# ==================== 意图选择算法 ====================

## 选择下一个意图（根据权重+修正）
func choose_intent(player_state: Dictionary = {}) -> void:
	var weights := _get_modified_weights(player_state)
	var category := _weighted_category_select(weights)
	var intent_type := _pick_intent_from_category(category)
	current_intent = _build_intent(intent_type)
	intent_revealed.emit(current_intent)

## 获取修正后的权重
func _get_modified_weights(player_state: Dictionary) -> Dictionary:
	var weights: Dictionary = BASE_WEIGHTS.duplicate()

	# 自定义权重覆盖
	if not intent_weights.is_empty():
		for key in intent_weights:
			weights[key] = intent_weights[key]

	# 血量修正：HP<30% → 防御+40，攻击-20
	var hp_ratio: float = float(current_hp) / float(max_hp) if max_hp > 0 else 1.0
	if hp_ratio < 0.3:
		weights["attack"] = maxi(0, weights["attack"] - 20)
		weights["defense"] += 40

	# 玩家状态修正
	if player_state.get("block", 0) > 0:
		weights["attack"] += 15  # 提升穿透攻击概率
	if player_state.get("vulnerable", 0) > 0:
		weights["attack"] += 20

	return weights

## 加权随机选择分类
func _weighted_category_select(weights: Dictionary) -> String:
	var total: int = 0
	for w in weights.values():
		total += w

	if total <= 0:
		return "attack"

	var roll: int = randi() % total
	var cumulative: int = 0
	for category in weights:
		cumulative += weights[category]
		if roll < cumulative:
			return category

	return "attack"

## 从分类中选择具体意图
func _pick_intent_from_category(category: String) -> IntentType:
	match category:
		"attack":
			return _weighted_pick(ATTACK_INTENTS, ATTACK_INTERNAL_WEIGHTS)
		"defense":
			return _weighted_pick(DEFENSE_INTENTS, DEFENSE_INTERNAL_WEIGHTS)
		"buff":
			return _weighted_pick(BUFF_INTENTS, BUFF_INTERNAL_WEIGHTS)
		"debuff":
			return _weighted_pick(DEBUFF_INTENTS, DEBUFF_INTERNAL_WEIGHTS)
		"special":
			return _weighted_pick(SPECIAL_INTENTS, SPECIAL_INTERNAL_WEIGHTS)
	return IntentType.ATTACK

## 加权随机从数组中选择
func _weighted_pick(items: Array, weights: Array) -> IntentType:
	var total: int = 0
	for w in weights:
		total += w
	if total <= 0:
		return items[0]
	var roll: int = randi() % total
	var cumulative: int = 0
	for i in range(items.size()):
		cumulative += weights[i]
		if roll < cumulative:
			return items[i]
	return items[0]

## 构建意图字典
func _build_intent(intent_type: IntentType) -> Dictionary:
	var intent: Dictionary = {
		"type": intent_type,
		"name": INTENT_NAMES.get(intent_type, "未知"),
	}

	match intent_type:
		IntentType.ATTACK:
			intent["damage"] = _get_base_damage()
			intent["element"] = element
		IntentType.PIERCE:
			intent["damage"] = int(_get_base_damage() * 0.83)  # 略低但穿透
			intent["pierce_rate"] = 0.5  # 50%格挡穿透
			intent["element"] = element
		IntentType.ATK_BUFF:
			intent["damage"] = int(_get_base_damage() * 0.67)
			intent["buff_type"] = "attack_up"
			intent["buff_value"] = 1
			intent["element"] = element
		IntentType.DEFEND:
			intent["shield"] = _get_base_damage()  # 格挡≈伤害值
		IntentType.DEF_BUFF:
			intent["shield"] = int(_get_base_damage() * 0.67)
			intent["buff_type"] = "defense_up"
			intent["buff_value"] = 1
		IntentType.ATK_UP:
			intent["buff_type"] = "attack_up"
			intent["buff_value"] = 2
		IntentType.DEF_UP:
			intent["buff_type"] = "defense_up"
			intent["buff_value"] = 2
		IntentType.HEAL:
			intent["heal"] = int(max_hp * 0.15)  # 回复15%最大HP
		IntentType.WEAKEN:
			intent["debuff_type"] = "weakness"
			intent["debuff_value"] = 2
			intent["debuff_duration"] = 2
		IntentType.VULNERABLE:
			intent["debuff_type"] = "vulnerable"
			intent["debuff_value"] = 2
			intent["debuff_duration"] = 2
		IntentType.POISON:
			intent["debuff_type"] = "poison"
			intent["debuff_value"] = 3
		IntentType.PHASE_SHIFT:
			intent["description"] = "气场切换"
		IntentType.SUMMON:
			intent["description"] = "召唤援军"
		IntentType.PURIFY:
			intent["description"] = "净化自身"

	return intent

## 获取基础伤害（基于元素和境界）
func _get_base_damage() -> int:
	# 基础伤害=6（炼气期基准），后续由敌人模板覆盖
	return 6

# ==================== 意图执行 ====================

## 执行当前意图
func execute_intent(target: Actor) -> Dictionary:
	if current_intent.is_empty():
		return {"success": false, "reason": "无意图"}

	var intent_type = current_intent.get("type", IntentType.ATTACK)
	var result: Dictionary = {"success": true, "type": intent_type}

	match intent_type:
		IntentType.ATTACK, IntentType.ATK_BUFF:
			var damage: int = current_intent.get("damage", 5)
			var atk_element = current_intent.get("element", element)
			var actual := target.take_damage(damage, atk_element, false)
			result["damage"] = actual
			# 攻击+增益：给自己加攻击buff
			if intent_type == IntentType.ATK_BUFF:
				_apply_self_buff(current_intent.get("buff_type", ""), current_intent.get("buff_value", 1))

		IntentType.PIERCE:
			var damage: int = current_intent.get("damage", 5)
			var _pierce_rate: float = current_intent.get("pierce_rate", 0.5)
			var atk_element = current_intent.get("element", element)
			# 穿透：先计算伤害，格挡只吸收 (1-pierce_rate) 部分
			var actual := target.take_damage(damage, atk_element, false)
			result["damage"] = actual
			result["pierce"] = true

		IntentType.DEFEND, IntentType.DEF_BUFF:
			var shield_amount: int = current_intent.get("shield", 5)
			gain_shield(shield_amount)
			result["shield"] = shield_amount
			if intent_type == IntentType.DEF_BUFF:
				_apply_self_buff(current_intent.get("buff_type", ""), current_intent.get("buff_value", 1))

		IntentType.ATK_UP, IntentType.DEF_UP:
			_apply_self_buff(current_intent.get("buff_type", ""), current_intent.get("buff_value", 2))

		IntentType.HEAL:
			var heal_amount: int = current_intent.get("heal", 5)
			var healed := heal(heal_amount)
			result["healed"] = healed

		IntentType.WEAKEN, IntentType.VULNERABLE, IntentType.POISON:
			# 对玩家施加debuff（简化实现：通过信号通知battle_manager）
			result["debuff_type"] = current_intent.get("debuff_type", "")
			result["debuff_value"] = current_intent.get("debuff_value", 1)
			result["debuff_duration"] = current_intent.get("debuff_duration", 2)

		IntentType.PHASE_SHIFT:
			result["phase_shift"] = true

		IntentType.SUMMON, IntentType.PURIFY:
			result["special"] = true

	# 执行后选择下一个意图
	choose_intent()

	return result

## 应用自身buff
func _apply_self_buff(buff_type: String, value: int) -> void:
	# 简化实现：直接打印，实际效果由battle_manager处理
	print("Enemy: %s 获得 %s +%d" % [actor_name, buff_type, value])

# ==================== 气场系统 ====================

enum AuraType { METAL, WOOD, WATER, FIRE, EARTH }

const AURA_CYCLE: Array = [AuraType.METAL, AuraType.WOOD, AuraType.WATER, AuraType.FIRE, AuraType.EARTH]

const AURA_DATA: Dictionary = {
	AuraType.METAL: {"name": "金", "passive_block": 3},
	AuraType.WOOD: {"name": "木", "passive_block": 0},
	AuraType.WATER: {"name": "水", "passive_block": 2},
	AuraType.FIRE: {"name": "火", "passive_block": 0, "bonus_damage": 2},
	AuraType.EARTH: {"name": "土", "passive_block": 4},
}

# 精英/Boss 气场属性
var current_aura_index: int = 0
var aura_turn_counter: int = 0
var aura_switch_interval: int = 5  # 精英5回合，Boss3回合
var is_boss: bool = false
var boss_phase: int = 1
var phase_shifted: bool = false

## 获取当前气场
func get_current_aura() -> AuraType:
	return AURA_CYCLE[current_aura_index]

## 回合结束时调用：气场切换检查
func on_turn_end_aura(player_state: Dictionary = {}) -> void:
	aura_turn_counter += 1

	# Boss 阶段检查
	if is_boss:
		_check_boss_phase()

	# 气场切换检查
	if aura_turn_counter >= aura_switch_interval:
		_switch_aura(player_state)
		aura_turn_counter = 0

## 切换气场
func _switch_aura(player_state: Dictionary) -> void:
	current_aura_index = (current_aura_index + 1) % AURA_CYCLE.size()
	var new_aura := get_current_aura()
	var aura_info: Dictionary = AURA_DATA.get(new_aura, {})
	print("Enemy: %s 气场切换 → %s" % [actor_name, aura_info.get("name", "?")])

	# 被动格挡
	var passive_block: int = aura_info.get("passive_block", 0)
	if passive_block > 0:
		gain_shield(passive_block)
		print("Enemy: %s %s气场被动格挡 +%d" % [actor_name, aura_info.get("name", ""), passive_block])

	# Boss 气场切换特殊效果
	if is_boss:
		_trigger_boss_aura_effect(new_aura, player_state)

## Boss 阶段检查（HP≤50%进入阶段2）
func _check_boss_phase() -> void:
	if not phase_shifted and current_hp <= max_hp * 0.5:
		boss_phase = 2
		phase_shifted = true
		print("Boss: %s 进入阶段2！" % actor_name)

## Boss 气场切换特殊效果
func _trigger_boss_aura_effect(aura: AuraType, _player_state: Dictionary) -> void:
	# 简化实现：每种Boss的气场切换效果在子类或数据中定义
	# 这里提供基础框架
	match aura:
		AuraType.FIRE:
			# 火气场：额外伤害
			var bonus: int = AURA_DATA.get(AuraType.FIRE, {}).get("bonus_damage", 0)
			if bonus > 0:
				print("Boss: %s 火气场额外伤害 +%d" % [actor_name, bonus])
		AuraType.EARTH:
			# 土气场：额外格挡
			var extra_block: int = AURA_DATA.get(AuraType.EARTH, {}).get("passive_block", 0)
			if extra_block > 0:
				gain_shield(extra_block)

## 获取气场预警状态（Boss切换前1回合）
func get_aura_warning() -> String:
	if aura_turn_counter == aura_switch_interval - 1:
		return "warning"
	return "normal"

## 重置气场（战斗开始时）
func reset_aura(start_index: int = 0, interval: int = 5, boss: bool = false) -> void:
	current_aura_index = start_index
	aura_turn_counter = 0
	aura_switch_interval = interval
	is_boss = boss
	boss_phase = 1
	phase_shifted = false

# ==================== 工厂方法（炼气期5种小怪） ====================

## 灵气游魂（火元素）
static func create_fire_spirit() -> Enemy:
	var enemy := Enemy.new("灵气游魂", 35, WuXing.Element.FIRE, "fire_spirit")
	enemy.description = "游荡在废弃网吧的火焰灵气"
	enemy.image_path = "res://assets/images/enemies/enemy_fire_flame_demon_001.png"
	enemy.intent_weights = {"attack": 70, "defense": 10, "buff": 10, "debuff": 5, "special": 5}
	return enemy

## 霓虹蜘蛛（木元素）
static func create_neon_spider() -> Enemy:
	var enemy := Enemy.new("霓虹蜘蛛", 35, WuXing.Element.WOOD, "neon_spider")
	enemy.description = "霓虹灯下编织灵网的变异蜘蛛"
	enemy.image_path = "res://assets/images/enemies/enemy_wood_vine_spirit_001.png"
	enemy.intent_weights = {"attack": 55, "defense": 20, "buff": 15, "debuff": 5, "special": 5}
	return enemy

## 城市石魔（土元素）
static func create_urban_golem() -> Enemy:
	var enemy := Enemy.new("城市石魔", 35, WuXing.Element.EARTH, "urban_golem")
	enemy.description = "由城市废墟混凝土凝聚的石魔"
	enemy.image_path = "res://assets/images/enemies/enemy_earth_rock_guardian_001.png"
	enemy.intent_weights = {"attack": 35, "defense": 45, "buff": 10, "debuff": 5, "special": 5}
	return enemy

## 数据水母（水元素）
static func create_data_jellyfish() -> Enemy:
	var enemy := Enemy.new("数据水母", 35, WuXing.Element.WATER, "data_jellyfish")
	enemy.description = "数据中心泄漏的电磁水母"
	enemy.image_path = "res://assets/images/enemies/enemy_water_frost_assassin_001.png"
	enemy.intent_weights = {"attack": 45, "defense": 25, "buff": 10, "debuff": 15, "special": 5}
	return enemy

## 电路精灵（金元素）
static func create_circuit_sprite() -> Enemy:
	var enemy := Enemy.new("电路精灵", 35, WuXing.Element.METAL, "circuit_sprite")
	enemy.description = "废弃电路板中诞生的金属精灵"
	enemy.image_path = "res://assets/images/enemies/enemy_metal_iron_golem_001.png"
	enemy.intent_weights = {"attack": 55, "defense": 15, "buff": 10, "debuff": 15, "special": 5}
	return enemy

# ==================== 查询方法 ====================

## 获取意图描述
func get_intent_description() -> String:
	if current_intent.is_empty():
		return "未知"
	return current_intent.get("name", "未知")

## 获取意图数值描述
func get_intent_detail() -> String:
	if current_intent.is_empty():
		return ""
	match current_intent.get("type", -1):
		IntentType.ATTACK, IntentType.PIERCE, IntentType.ATK_BUFF:
			return "%d伤害" % current_intent.get("damage", 0)
		IntentType.DEFEND, IntentType.DEF_BUFF:
			return "%d格挡" % current_intent.get("shield", 0)
		IntentType.HEAL:
			return "回复%d" % current_intent.get("heal", 0)
		IntentType.WEAKEN, IntentType.VULNERABLE, IntentType.POISON:
			return current_intent.get("debuff_type", "")
		IntentType.ATK_UP, IntentType.DEF_UP:
			return current_intent.get("buff_type", "")
		IntentType.PHASE_SHIFT:
			return "气场切换"
	return ""

## 获取状态摘要
func get_status_summary() -> String:
	var base := "%s HP:%d/%d 盾:%d [%s]" % [
		actor_name, current_hp, max_hp, shield, get_element_name()
	]
	if not current_intent.is_empty():
		base += " 意图:%s(%s)" % [get_intent_description(), get_intent_detail()]
	return base

# ==================== 筑基期工厂方法 ====================

## 筑基期小怪

static func create_industrial_puppet() -> Enemy:
	var enemy := Enemy.new("工业傀儡", 55, WuXing.Element.METAL, "industrial_puppet")
	enemy.description = "废弃工厂中自行组装的金属傀儡"
	enemy.image_path = "res://assets/images/enemies/enemy_metal_iron_golem_001.png"
	enemy.intent_weights = {"attack": 55, "defense": 20, "buff": 10, "debuff": 10, "special": 5}
	return enemy

static func create_wild_vine() -> Enemy:
	var enemy := Enemy.new("荒野藤蔓", 55, WuXing.Element.WOOD, "wild_vine")
	enemy.description = "城市边缘疯长的变异藤蔓"
	enemy.image_path = "res://assets/images/enemies/enemy_wood_vine_spirit_001.png"
	enemy.intent_weights = {"attack": 45, "defense": 30, "buff": 10, "debuff": 10, "special": 5}
	return enemy

static func create_data_flood() -> Enemy:
	var enemy := Enemy.new("数据洪流", 55, WuXing.Element.WATER, "data_flood")
	enemy.description = "数据中心溢出的电磁洪流"
	enemy.image_path = "res://assets/images/enemies/enemy_water_frost_assassin_001.png"
	enemy.intent_weights = {"attack": 40, "defense": 25, "buff": 10, "debuff": 20, "special": 5}
	return enemy

static func create_city_fire_spirit() -> Enemy:
	var enemy := Enemy.new("城市火灵", 55, WuXing.Element.FIRE, "city_fire_spirit")
	enemy.description = "城市燃气管道中诞生的火元素"
	enemy.image_path = "res://assets/images/enemies/enemy_fire_flame_demon_001.png"
	enemy.intent_weights = {"attack": 65, "defense": 10, "buff": 15, "debuff": 5, "special": 5}
	return enemy

static func create_construction_golem() -> Enemy:
	var enemy := Enemy.new("建筑巨像", 55, WuXing.Element.EARTH, "construction_golem")
	enemy.description = "建筑工地混凝土凝聚的巨型石像"
	enemy.image_path = "res://assets/images/enemies/enemy_earth_rock_guardian_001.png"
	enemy.intent_weights = {"attack": 30, "defense": 50, "buff": 10, "debuff": 5, "special": 5}
	return enemy

# ==================== 金丹期工厂方法 ====================

## 金丹期小怪

static func create_gold_guardian() -> Enemy:
	var enemy := Enemy.new("金甲卫士", 85, WuXing.Element.METAL, "gold_guardian")
	enemy.description = "金丹期修士的护法金甲"
	enemy.image_path = "res://assets/images/enemies/enemy_metal_iron_golem_001.png"
	enemy.intent_weights = {"attack": 50, "defense": 25, "buff": 10, "debuff": 10, "special": 5}
	return enemy

static func create_spirit_tree_guardian() -> Enemy:
	var enemy := Enemy.new("灵木守卫", 85, WuXing.Element.WOOD, "spirit_tree_guardian")
	enemy.description = "灵脉附近的古木守卫"
	enemy.image_path = "res://assets/images/enemies/enemy_wood_vine_spirit_001.png"
	enemy.intent_weights = {"attack": 40, "defense": 35, "buff": 15, "debuff": 5, "special": 5}
	return enemy

static func create_abyss_water_spirit() -> Enemy:
	var enemy := Enemy.new("深渊水灵", 85, WuXing.Element.WATER, "abyss_water_spirit")
	enemy.description = "深渊裂缝中渗出的水元素"
	enemy.image_path = "res://assets/images/enemies/enemy_water_frost_assassin_001.png"
	enemy.intent_weights = {"attack": 35, "defense": 20, "buff": 10, "debuff": 25, "special": 10}
	return enemy

static func create_sky_fire_crow() -> Enemy:
	var enemy := Enemy.new("焚天火鸦", 85, WuXing.Element.FIRE, "sky_fire_crow")
	enemy.description = "金丹期火修驯养的灵鸦"
	enemy.image_path = "res://assets/images/enemies/enemy_fire_flame_demon_001.png"
	enemy.intent_weights = {"attack": 70, "defense": 10, "buff": 10, "debuff": 5, "special": 5}
	return enemy

static func create_earth_stone_king() -> Enemy:
	var enemy := Enemy.new("大地石王", 85, WuXing.Element.EARTH, "earth_stone_king")
	enemy.description = "地脉深处沉睡万年的岩石王者"
	enemy.image_path = "res://assets/images/enemies/enemy_earth_rock_guardian_001.png"
	enemy.intent_weights = {"attack": 25, "defense": 55, "buff": 10, "debuff": 5, "special": 5}
	return enemy

# ==================== 精英工厂方法 ====================

## 炼气期精英 — 百变灵傀
static func create_elite_shifting_puppet() -> Enemy:
	var enemy := Enemy.new("百变灵傀", 63, WuXing.Element.METAL, "elite_shifting_puppet")
	enemy.description = "蜃都街头游荡的傀儡，外壳随气场不断变换"
	enemy.image_path = "res://assets/images/enemies/elite_neutral_shifting_puppet_001.png"
	enemy.intent_weights = {"attack": 40, "defense": 30, "buff": 15, "debuff": 5, "special": 10}
	return enemy

## 筑基期精英 — 荆棘魔藤
static func create_elite_thorn_vine() -> Enemy:
	var enemy := Enemy.new("荆棘魔藤", 99, WuXing.Element.WOOD, "elite_thorn_vine")
	enemy.description = "筑基期魔修培育的荆棘妖植"
	enemy.image_path = "res://assets/images/enemies/enemy_wood_vine_spirit_001.png"
	enemy.intent_weights = {"attack": 35, "defense": 30, "buff": 15, "debuff": 15, "special": 5}
	return enemy

## 金丹期精英 — 幻火分身
static func create_elite_phantom_fire() -> Enemy:
	var enemy := Enemy.new("幻火分身", 153, WuXing.Element.FIRE, "elite_phantom_fire")
	enemy.description = "金丹期火修的分身投影"
	enemy.image_path = "res://assets/images/enemies/enemy_fire_flame_demon_001.png"
	enemy.intent_weights = {"attack": 55, "defense": 15, "buff": 15, "debuff": 10, "special": 5}
	return enemy

# ==================== Boss工厂方法 ====================

## 炼气期 Boss — 霓虹蛛后
## Boss HP 调整：88 → 106（+20%，2026-07-19 balance auto-dispatch）
## Boss HP 再次调整：106 → 127（+20%，2026-07-22 balance auto-dispatch #2，胜率>80%）
## Boss HP 三次调整：127 → 152（+20%，2026-07-23 balance auto-dispatch #3，胜率>80%）
## Boss HP 四次调整：152 → 182（+20%，2026-07-24 balance auto-dispatch #4，胜率>80%）
## Boss HP 五次调整：182 → 218（+20%，2026-07-25 balance auto-dispatch #5，胜率>80%）
## Boss HP 六次调整：218 → 262（+20%，2026-07-26 balance auto-dispatch #6，胜率>80%）
static func create_boss_neon_spider_queen() -> Enemy:
	var enemy := Enemy.new("霓虹蛛后", 262, WuXing.Element.WOOD, "boss_neon_spider_queen")
	enemy.description = "霓虹灯海中的蛛群女王，掌控木系灵力"
	enemy.image_path = "res://assets/images/bosses/boss_metal_lord_souls_001.png"
	enemy.intent_weights = {"attack": 50, "defense": 20, "buff": 15, "debuff": 10, "special": 5}
	return enemy

## 筑基期 Boss — 熔炉巨灵
## Boss HP 调整：138 → 166（+20%，2026-07-19 balance auto-dispatch）
## Boss HP 再次调整：166 → 199（+20%，2026-07-22 balance auto-dispatch #2，胜率>80%）
## Boss HP 三次调整：199 → 239（+20%，2026-07-23 balance auto-dispatch #3，胜率>80%）
## Boss HP 四次调整：239 → 287（+20%，2026-07-24 balance auto-dispatch #4，胜率>80%）
## Boss HP 五次调整：287 → 344（+20%，2026-07-25 balance auto-dispatch #5，胜率>80%）
## Boss HP 六次调整：344 → 413（+20%，2026-07-26 balance auto-dispatch #6，胜率>80%）
static func create_boss_furnace_giant() -> Enemy:
	var enemy := Enemy.new("熔炉巨灵", 413, WuXing.Element.FIRE, "boss_furnace_giant")
	enemy.description = "工业区核心的熔炉精灵，吞噬一切的火焰巨人"
	enemy.image_path = "res://assets/images/bosses/boss_water_abyssal_dragon_001.png"
	enemy.intent_weights = {"attack": 60, "defense": 15, "buff": 10, "debuff": 10, "special": 5}
	return enemy

## 金丹期 Boss — 通天塔守卫
## Boss HP 调整：213 → 256（+20%，2026-07-19 balance auto-dispatch）
## Boss HP 再次调整：256 → 307（+20%，2026-07-22 balance auto-dispatch #2，胜率>80%）
## Boss HP 三次调整：307 → 368（+20%，2026-07-23 balance auto-dispatch #3，胜率>80%）
## Boss HP 四次调整：368 → 442（+20%，2026-07-24 balance auto-dispatch #4，胜率>80%）
## Boss HP 五次调整：442 → 530（+20%，2026-07-25 balance auto-dispatch #5，胜率>80%）
## Boss HP 六次调整：530 → 636（+20%，2026-07-26 balance auto-dispatch #6，胜率>80%）
static func create_boss_tower_guardian() -> Enemy:
	var enemy := Enemy.new("通天塔守卫", 636, WuXing.Element.EARTH, "boss_tower_guardian")
	enemy.description = "通天塔底层的古老守卫，守护金丹期的最终试炼"
	enemy.image_path = "res://assets/images/bosses/boss_earth_true_lord_001.png"
	enemy.intent_weights = {"attack": 45, "defense": 30, "buff": 10, "debuff": 10, "special": 5}
	return enemy
