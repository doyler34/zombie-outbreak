# game_state.gd - Central game state and save/load manager (Autoload)
extends Node

const SAVE_PATH := "user://save_game.json"

# Day/night
var current_day: int = 1
var is_night: bool = false
var day_timer: float = 0.0
const DAY_LENGTH := 120.0  # seconds per full day cycle
const DAY_PORTION := 0.55   # 55% day, 45% night

# Base stats
var base_defense: int = 0
var base_happiness: int = 50
var noise_level: float = 0.0

# Survivors
var survivors: Array = []
var population_cap: int = 4

# Buildings dictionary: {building_id: level}
var buildings: Dictionary = {}

# Missions in progress
var active_missions: Array = []

func _ready() -> void:
	pass

## Start a new game with defaults
func new_game() -> void:
	current_day = 1
	is_night = false
	day_timer = 0.0
	noise_level = 0.0
	survivors.clear()
	buildings.clear()
	active_missions.clear()

	# Reset resources
	for res in ResourceManager.resource_order:
		ResourceManager.set_resource(res, ResourceManager.resources.get(res, 0))

	# Generate starting survivors
	_spawn_starting_survivors(3)

	# Build initial barracks at level 1
	buildings["barracks"] = 1
	# Ruined outpost starts broken (level 0), needs repair
	buildings["ruined_outpost"] = 0
	_recalculate_base_stats()

	EventBus.notification.emit("Day %d begins. A ruined outpost nearby needs repair!" % current_day, "#FFAA00")
	save_game()

func _spawn_starting_survivors(count: int) -> void:
	var names_data = _load_json("res://data/survivors.json")
	if names_data == null:
		return
	for i in range(count):
		var survivor = _generate_survivor(names_data)
		survivors.append(survivor)
		EventBus.survivor_added.emit(survivor)

func _generate_survivor(data: Dictionary) -> Dictionary:
	var first = data.first_names[randi() % data.first_names.size()]
	var last = data.last_names[randi() % data.last_names.size()]
	var skill_pool = data.skills.duplicate()
	skill_pool.shuffle()
	# Assign 2 random skills at levels 1-3
	var assigned_skills = {}
	assigned_skills[skill_pool[0].id] = randi_range(2, 4)
	assigned_skills[skill_pool[1].id] = randi_range(1, 3)

	var base = data.survivor_base_stats
	return {
		"id": str(Time.get_unix_time_from_system()) + str(randi()),
		"name": "%s %s" % [first, last],
		"health": base.max_health,
		"hunger": randi_range(40, 80),
		"mood": "Content",
		"skills": assigned_skills,
		"assigned_building": "",
		"alive": true
	}

func _recalculate_base_stats() -> void:
	var buildings_data = _load_json("res://data/buildings.json")
	if buildings_data == null:
		return

	base_defense = 0
	base_happiness = 50
	population_cap = 4  # Base without barracks

	for bld in buildings_data.buildings:
		if buildings.has(bld.id):
			var lvl = buildings[bld.id]
			if lvl <= 0:
				continue  # Skip broken/ruined buildings
			for effect in bld.effects:
				var cfg = bld.effects[effect]
				# Use base + (level-1) * per_level
				var val = cfg.base + (lvl - 1) * cfg.per_level
				match effect:
					"population_cap":
						population_cap += val
					"defense":
						base_defense += val
					"happiness":
						base_happiness += val

## Daily resource production from buildings
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
				"food_per_day":
					var amount = bld.effects[effect].base + (lvl - 1) * bld.effects[effect].per_level
					ResourceManager.modify("food", amount)
				"metal_per_day":
					var amount = bld.effects[effect].base + (lvl - 1) * bld.effects[effect].per_level
					ResourceManager.modify("metal", amount)
				"ammo_per_day":
					var amount = bld.effects[effect].base + (lvl - 1) * bld.effects[effect].per_level
					ResourceManager.modify("ammo", amount)

func process_survivor_needs() -> void:
	var starved = []
	for survivor in survivors:
		if not survivor.alive:
			continue
		# Hunger
		survivor.hunger = max(0, survivor.hunger - 8)
		if survivor.hunger <= 0:
			survivor.health -= 15
			starved.append(survivor.name)
		elif survivor.hunger < 30 and ResourceManager.has("food", 1):
			ResourceManager.modify("food", -1)
			survivor.hunger = min(100, survivor.hunger + 25)
			EventBus.survivor_healed.emit(survivor)

		# Check death
		if survivor.health <= 0:
			survivor.alive = false
			EventBus.survivor_died.emit(survivor.name)
			EventBus.notification.emit("%s has died." % survivor.name, "#FF4444")

	# Heal survivors if medical bay exists and has supplies
	if buildings.has("medical_bay") and ResourceManager.has("medicine", 1):
		for survivor in survivors:
			if survivor.alive and survivor.health < 80:
				ResourceManager.modify("medicine", -1)
				survivor.health = min(100, survivor.health + 20)
				break

## Save game to JSON
func save_game() -> void:
	var save_data = {
		"version": "0.1.0",
		"current_day": current_day,
		"is_night": is_night,
		"day_timer": day_timer,
		"noise_level": noise_level,
		"resources": ResourceManager.to_dict(),
		"survivors": survivors,
		"buildings": buildings,
		"population_cap": population_cap
	}

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("GameState: Cannot write save file.")
		return
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	EventBus.game_saved.emit()

## Load game from JSON
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		EventBus.notification.emit("No save file found.", "#FFAA00")
		return false

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false

	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		push_error("GameState: Save file corrupt.")
		return false

	var data = json.get_data()
	current_day = data.get("current_day", 1)
	is_night = data.get("is_night", false)
	day_timer = data.get("day_timer", 0.0)
	noise_level = data.get("noise_level", 0.0)
	ResourceManager.from_dict(data.get("resources", {}))
	survivors = data.get("survivors", [])
	buildings = data.get("buildings", {})
	population_cap = data.get("population_cap", 4)

	_recalculate_base_stats()
	EventBus.game_loaded.emit()
	EventBus.notification.emit("Game loaded — Day %d." % current_day, "#00FF00")
	return true

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

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

## Returns count of alive survivors
func alive_count() -> int:
	var count = 0
	for s in survivors:
		if s.alive:
			count += 1
	return count

## Get survivors available for missions (not on mission, alive)
func available_survivors() -> Array:
	var avail = []
	for s in survivors:
		if s.alive:
			avail.append(s)
	return avail
