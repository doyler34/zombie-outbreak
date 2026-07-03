extends Node
## DataManager — loads and indexes all game data (autoload).
##
## Two kinds of data:
##  1. Definition Resources (.tres) — buildings, resources. Discovered by
##     scanning their data/ folders, so adding content means dropping in a
##     new file; no registration code.
##  2. JSON tables — loose data like survivor name pools, loaded from
##     data/tables/ and fetched with get_table().
##
## Also owns the single GameSettings instance (DataManager.settings).

const SETTINGS_PATH := "res://data/settings/game_settings.tres"
const BUILDINGS_DIR := "res://data/buildings"
const RESOURCES_DIR := "res://data/resources"
const OBSTACLES_DIR := "res://data/obstacles"
const ROLES_DIR := "res://data/roles"
const ZOMBIES_DIR := "res://data/zombies"
const LOCATIONS_DIR := "res://data/locations"
const TABLES_DIR := "res://data/tables"

var settings: GameSettings

var _buildings: Dictionary = {}  # id -> BuildingDefinition
var _resources: Dictionary = {}  # id -> ResourceDefinition
var _obstacles: Dictionary = {}  # id -> ObstacleDefinition
var _roles: Dictionary = {}      # id -> SurvivorRoleDefinition
var _zombies: Dictionary = {}    # id -> ZombieDefinition
var _locations: Dictionary = {}  # id -> LocationDefinition
var _tables: Dictionary = {}     # name -> Dictionary/Array


func _ready() -> void:
	settings = load(SETTINGS_PATH)
	assert(settings != null, "Missing game settings at %s" % SETTINGS_PATH)
	_load_definitions(BUILDINGS_DIR, _buildings)
	_load_definitions(RESOURCES_DIR, _resources)
	_load_definitions(OBSTACLES_DIR, _obstacles)
	_load_definitions(ROLES_DIR, _roles)
	_load_definitions(ZOMBIES_DIR, _zombies)
	_load_definitions(LOCATIONS_DIR, _locations)
	_load_tables()
	print("[DataManager] %d buildings, %d resources, %d obstacles, %d roles, %d zombies, %d locations, %d tables" % [
		_buildings.size(), _resources.size(), _obstacles.size(),
		_roles.size(), _zombies.size(), _locations.size(), _tables.size()])


# ── Buildings ────────────────────────────────────────────────────────────

func get_building(id: String) -> BuildingDefinition:
	return _buildings.get(id)


## All building definitions, sorted for menu display.
func all_buildings() -> Array[BuildingDefinition]:
	var list: Array[BuildingDefinition] = []
	for def: BuildingDefinition in _buildings.values():
		list.append(def)
	list.sort_custom(func(a, b): return a.sort_order < b.sort_order)
	return list


# ── Resources ────────────────────────────────────────────────────────────

func get_resource_def(id: String) -> ResourceDefinition:
	return _resources.get(id)


func all_resource_defs() -> Array[ResourceDefinition]:
	var list: Array[ResourceDefinition] = []
	for def: ResourceDefinition in _resources.values():
		list.append(def)
	list.sort_custom(func(a, b): return a.sort_order < b.sort_order)
	return list


# ── Obstacles ────────────────────────────────────────────────────────────

func get_obstacle(id: String) -> ObstacleDefinition:
	return _obstacles.get(id)


func all_obstacles() -> Array[ObstacleDefinition]:
	var list: Array[ObstacleDefinition] = []
	for def: ObstacleDefinition in _obstacles.values():
		list.append(def)
	return list


# ── Combat: roles & zombies ──────────────────────────────────────────────

func get_role(id: String) -> SurvivorRoleDefinition:
	return _roles.get(id)


func all_roles() -> Array[SurvivorRoleDefinition]:
	var list: Array[SurvivorRoleDefinition] = []
	for def: SurvivorRoleDefinition in _roles.values():
		list.append(def)
	return list


func get_zombie(id: String) -> ZombieDefinition:
	return _zombies.get(id)


func get_location(id: String) -> LocationDefinition:
	return _locations.get(id)


func all_locations() -> Array[LocationDefinition]:
	var list: Array[LocationDefinition] = []
	for def: LocationDefinition in _locations.values():
		list.append(def)
	list.sort_custom(func(a, b): return a.difficulty < b.difficulty)
	return list


func all_zombies() -> Array[ZombieDefinition]:
	var list: Array[ZombieDefinition] = []
	for def: ZombieDefinition in _zombies.values():
		list.append(def)
	return list


# ── Tables ───────────────────────────────────────────────────────────────

func get_table(table_name: String) -> Variant:
	return _tables.get(table_name)


# ── Internal ─────────────────────────────────────────────────────────────

func _load_definitions(dir_path: String, target: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("[DataManager] Missing data directory: %s" % dir_path)
		return
	for file in dir.get_files():
		# Exported builds may list resources with a .remap suffix.
		var file_name := file.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var res: Resource = load(dir_path.path_join(file_name))
		if res == null or not ("id" in res) or res.id == "":
			push_warning("[DataManager] Skipping invalid definition: %s" % file_name)
			continue
		target[res.id] = res


func _load_tables() -> void:
	var dir := DirAccess.open(TABLES_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var f := FileAccess.open(TABLES_DIR.path_join(file), FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed == null:
			push_warning("[DataManager] Bad JSON in table: %s" % file)
			continue
		_tables[file.trim_suffix(".json")] = parsed
