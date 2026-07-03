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
const TABLES_DIR := "res://data/tables"

var settings: GameSettings

var _buildings: Dictionary = {}  # id -> BuildingDefinition
var _resources: Dictionary = {}  # id -> ResourceDefinition
var _obstacles: Dictionary = {}  # id -> ObstacleDefinition
var _tables: Dictionary = {}     # name -> Dictionary/Array


func _ready() -> void:
	settings = load(SETTINGS_PATH)
	assert(settings != null, "Missing game settings at %s" % SETTINGS_PATH)
	_load_definitions(BUILDINGS_DIR, _buildings)
	_load_definitions(RESOURCES_DIR, _resources)
	_load_definitions(OBSTACLES_DIR, _obstacles)
	_load_tables()
	print("[DataManager] %d buildings, %d resources, %d obstacles, %d tables" % [
		_buildings.size(), _resources.size(), _obstacles.size(), _tables.size()])


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
