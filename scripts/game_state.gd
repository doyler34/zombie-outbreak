# game_state.gd - Central game state and save/load manager (Autoload)
extends Node

const SAVE_PATH := "user://save_game.json"

var current_day: int = 1
var is_night: bool = false
var day_timer: float = 0.0
const DAY_LENGTH := 120.0
const DAY_PORTION := 0.55

var base_defense: int = 0
var noise_level: float = 0.0

var survivors: Array = []
var population_cap: int = 4

var buildings: Dictionary = {}
var active_missions: Array = []

var tutorial_active: bool = true
var tutorial_step: int = 0   # 0=show building  1=repairing  2=done

func _ready() -> void:
	pass

func new_game() -> void:
	current_day = 1
	is_night = false
	day_timer = 0.0
	noise_level = 0.0
	survivors.clear()
	buildings.clear()
	active_missions.clear()
	tutorial_active = true
	tutorial_step = 0

	for res in ResourceManager.resource_order:
		var data = _load_json("res://data/survivors.json")
		if data and data.has("starting_resources"):
			ResourceManager.set_resource(res, data.starting_resources.get(res, 500))
		else:
			ResourceManager.set_resource(res, 500)

	buildings["ruined_outpost"] = 0
	_recalculate_base_stats()
	save_game()

func _recalculate_base_stats() -> void:
	var buildings_data = _load_json("res://data/buildings.json")
	if buildings_data == null:
		return
	base_defense = 0
	for bld in buildings_data.buildings:
		if buildings.has(bld.id):
			var lvl = buildings[bld.id]
			if lvl <= 0:
				continue
			for effect in bld.effects:
				var cfg = bld.effects[effect]
				var val = cfg.base + (lvl - 1) * cfg.per_level
				match effect:
					"defense":
						base_defense += val

func process_daily_production() -> void:
	var buildings_data = _load_json("res://data/buildings.json")
	if buildings_data == null:
		return
	for bld in buildings_data.buildings:
		if not buildings.has(bld.id):
			continue
		var lvl = buildings[bld.id]
		for effect in bld.effects:
			match effect:
				"metal_per_day":
					var amount = bld.effects[effect].base + (lvl - 1) * bld.effects[effect].per_level
					ResourceManager.modify("metal", amount)
				"gold_per_day":
					var amount = bld.effects[effect].base + (lvl - 1) * bld.effects[effect].per_level
					ResourceManager.modify("gold", amount)

func _check_zombie_attack_survivors() -> void:
	if GameState.alive_count() <= 0:
		EventBus.game_over.emit("All survivors lost.")

func save_game() -> void:
	var save_data = {
		"version": "0.2.0",
		"current_day": current_day,
		"is_night": is_night,
		"day_timer": day_timer,
		"noise_level": noise_level,
		"resources": ResourceManager.to_dict(),
		"survivors": survivors,
		"buildings": buildings,
		"tutorial_active": tutorial_active,
		"tutorial_step": tutorial_step
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	EventBus.game_saved.emit()

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK:
		return false
	var data = json.get_data()
	current_day = data.get("current_day", 1)
	is_night = data.get("is_night", false)
	day_timer = data.get("day_timer", 0.0)
	noise_level = data.get("noise_level", 0.0)
	ResourceManager.from_dict(data.get("resources", {}))
	survivors = data.get("survivors", [])
	buildings = data.get("buildings", {})
	tutorial_active = data.get("tutorial_active", false)
	tutorial_step = data.get("tutorial_step", 2)
	_recalculate_base_stats()
	EventBus.game_loaded.emit()
	return true

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func alive_count() -> int:
	var count = 0
	for s in survivors:
		if s.alive:
			count += 1
	return count

func available_survivors() -> Array:
	var avail = []
	for s in survivors:
		if s.alive:
			avail.append(s)
	return avail

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
