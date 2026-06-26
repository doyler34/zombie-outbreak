# resource_manager.gd - Central resource tracking (Autoload)
extends Node

# Resource dictionary: {name: amount}
var resources: Dictionary = {}
var resource_order: Array[String] = ["food", "water", "wood", "metal", "medicine", "ammo"]

func _ready() -> void:
	# Load starting resources from data file
	var data = _load_json("res://data/survivors.json")
	if data and data.has("starting_resources"):
		for key in data.starting_resources:
			resources[key] = data.starting_resources[key]
	else:
		# Fallback defaults
		resources = {"food": 30, "water": 40, "wood": 50, "metal": 20, "medicine": 10, "ammo": 15}

func _load_json(path: String) -> Variant:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ResourceManager: Cannot open %s" % path)
		return null
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		push_error("ResourceManager: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return null
	return json.get_data()

## Add resources (positive) or remove (negative). Returns false if insufficient.
func modify(resource_name: String, amount: int) -> bool:
	if not resources.has(resource_name):
		push_error("ResourceManager: Unknown resource '%s'" % resource_name)
		return false

	if resources[resource_name] + amount < 0:
		return false  # Not enough resources

	resources[resource_name] += amount
	EventBus.resource_changed.emit(resource_name, amount, resources[resource_name])

	# Check low resource threshold
	if resources[resource_name] <= 3:
		EventBus.resource_low.emit(resource_name)

	return true

## Check if we have enough of a resource
func has(resource_name: String, amount: int) -> bool:
	return resources.get(resource_name, 0) >= amount

## Check if we can afford a cost dictionary like {"wood": 10, "metal": 5}
func can_afford(costs: Dictionary) -> bool:
	for key in costs:
		if not has(key, costs[key]):
			return false
	return true

## Pay a cost dictionary. Returns false if can't afford.
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

## Serialize for save/load
func to_dict() -> Dictionary:
	return resources.duplicate()

func from_dict(data: Dictionary) -> void:
	resources = data.duplicate()
	for key in resource_order:
		if not resources.has(key):
			resources[key] = 0
