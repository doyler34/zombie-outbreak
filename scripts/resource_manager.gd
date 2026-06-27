# resource_manager.gd - Central resource tracking (Autoload)
extends Node

var resources: Dictionary = {}
var resource_order: Array[String] = ["wood", "stone", "metal", "gold"]

func _ready() -> void:
	var data = _load_json("res://data/survivors.json")
	if data and data.has("starting_resources"):
		for key in data.starting_resources:
			resources[key] = data.starting_resources[key]
	else:
		resources = {"wood": 500, "stone": 500, "metal": 500, "gold": 500}

func _load_json(path: String) -> Variant:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK:
		return null
	return json.get_data()

func modify(resource_name: String, amount: int) -> bool:
	if not resources.has(resource_name):
		return false
	if resources[resource_name] + amount < 0:
		return false
	resources[resource_name] += amount
	EventBus.resource_changed.emit(resource_name, amount, resources[resource_name])
	if resources[resource_name] <= 10:
		EventBus.resource_low.emit(resource_name)
	return true

func has(resource_name: String, amount: int) -> bool:
	return resources.get(resource_name, 0) >= amount

func can_afford(costs: Dictionary) -> bool:
	for key in costs:
		if not has(key, costs[key]):
			return false
	return true

func pay(costs: Dictionary) -> bool:
	if not can_afford(costs):
		return false
	for key in costs:
		modify(key, -costs[key])
	return true

func get_resource(resource_name: String) -> int:
	return resources.get(resource_name, 0)

func set_resource(resource_name: String, amount: int) -> void:
	resources[resource_name] = max(0, amount)
	EventBus.resource_changed.emit(resource_name, 0, amount)

func to_dict() -> Dictionary:
	return resources.duplicate()

func from_dict(data: Dictionary) -> void:
	resources = data.duplicate()
	for key in resource_order:
		if not resources.has(key):
			resources[key] = 0
