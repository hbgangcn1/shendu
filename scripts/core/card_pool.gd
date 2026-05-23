## 卡池加载器 — 管理所有卡牌数据
## 作为 Autoload 单例使用

extends Node

# 加载后的卡牌数据字典 {id: card_data_resource}
var _cards: Dictionary = {}

# MVP 卡池 ID 列表
var _mvp_pool: Array[String] = []

func _ready() -> void:
	_load_cards("res://data/cards/mvp_cards.json")

## 从 JSON 文件加载卡牌数据
func _load_cards(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法加载卡牌数据文件: " + path)
		return

	var json_text := file.get_as_text()
	var json := JSON.new()
	var error := json.parse(json_text)

	if error != OK:
		push_error("JSON 解析失败: " + json.get_error_message())
		return

	var data: Array = json.data
	for card_dict in data:
		var dict := card_dict as Dictionary
		var card = load("res://scripts/core/card_data.gd").new()
		card.id = dict.get("id", "")
		card.card_name = dict.get("card_name", "")
		card.description = dict.get("description", "")
		card.cost = dict.get("cost", 0)
		card.element = dict.get("element", 0)
		card.card_type = dict.get("card_type", 0)
		card.rarity = dict.get("rarity", 0)
		card.damage = dict.get("damage", 0)
		card.block = dict.get("block", 0)
		card.draw_cards = dict.get("draw_cards", 0)
		card.heal = dict.get("heal", 0)
		_cards[card.id] = card
		_mvp_pool.append(card.id)

	print("CardPool: 加载了 %d 张卡牌" % _cards.size())

## 根据 ID 获取卡牌
func get_card(id: String):
	return _cards.get(id, null)

## 获取 MVP 卡池中所有卡牌
func get_mvp_pool() -> Array:
	var result: Array = []
	for id in _mvp_pool:
		result.append(_cards[id])
	return result

## 获取卡池大小
func get_pool_size() -> int:
	return _cards.size()
