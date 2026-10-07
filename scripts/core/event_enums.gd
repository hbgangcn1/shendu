## 事件系统枚举和常量

# implements: design/00-MASTER.md
# implements_philosophy: rule_3_three_layer_loops, rule_8_cosmetics_over_p2w
# avoids_red_line: red_10_three_layer_break

enum EventCategory { NARRATIVE, RESOURCE, RISK }

const CATEGORY_NAMES := {
	EventCategory.NARRATIVE: "叙事型",
	EventCategory.RESOURCE: "资源型",
	EventCategory.RISK: "风险型",
}

enum ResourceType { HP, MANA, SPIRIT_STONES, MO_NIAN, DAO_XING, CARD, RANDOM_CARD, STATUS_EFFECT, BLESSING }

enum OutcomeDirection { GAIN, LOSE, SET }

enum PreconditionType {
	HP_ABOVE, HP_BELOW, SPIRIT_STONES, MO_NIAN, DAO_XING,
	HAS_CARD, HAS_ELEMENT, REALM_INDEX, CARD_COUNT,
}

enum TriggerType {
	REALM, NODE_COLUMN, HP_RANGE, MO_NIAN_MIN, MO_NIAN_MAX,
	SPIRIT_STONES_MIN, CARD_COUNT_MIN, HAS_ELEMENT,
	COMBAT_STREAK, EVENT_CHAIN, FIRST_TIME,
	REALM_INDEX_MIN, REALM_INDEX_MAX,
}
