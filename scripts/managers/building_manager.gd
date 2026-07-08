extends Node
## BuildingManager — owns every placed building (autoload).
##
## Responsibilities:
##  - validate + execute placement (cost, occupancy) and removal
##  - track the selected building
##  - drive daily production and passive effect totals
##  - serialize placed buildings for SaveManager
##
## Building visuals/behaviour live in BuildingEntity (scenes/buildings/);
## this manager only orchestrates. The world scene registers its container
## node on load so entities end up inside the world tree.

const BUILDING_ENTITY_SCENE := preload("res://scenes/buildings/building_entity.tscn")

var selected: BuildingEntity = null

var _entities: Array[BuildingEntity] = []
## Set by the active GameWorld; parent for spawned building nodes.
var _container: Node = null


func _ready() -> void:
	SaveManager.register_section("buildings", self)
	EventBus.day_passed.connect(_on_day_passed)


## Called by GameWorld when it enters the tree.
func register_container(container: Node) -> void:
	_container = container


func reset() -> void:
	for entity in _entities:
		entity.queue_free()
	_entities.clear()
	selected = null
	_container = null


# ── Placement / removal ──────────────────────────────────────────────────

func can_place(def: BuildingDefinition, cell: Vector2i, rotation: int = 0) -> bool:
	return WorldManager.is_area_buildable(cell, _rotated_footprint(def, rotation)) \
		and ResourceManager.can_afford(def.cost_for_level(1))


## Validates, pays, spawns and registers a building.
## [param rotation] is in 90° steps (0-3); odd steps swap the footprint.
## Returns the new entity, or null if placement failed.
func place(def: BuildingDefinition, cell: Vector2i, rotation: int = 0, instant: bool = false) -> BuildingEntity:
	if not WorldManager.is_area_buildable(cell, _rotated_footprint(def, rotation)):
		EventBus.notify("Blocked — clear the area first.", 1)
		return null
	if not ResourceManager.spend(def.cost_for_level(1)):
		EventBus.notify("Not enough materials!", 1)
		return null
	var entity := _spawn(def, cell, rotation)
	if instant:
		entity.finish_construction()
	EventBus.building_placed.emit(entity)
	return entity


static func _rotated_footprint(def: BuildingDefinition, rotation: int) -> Vector2i:
	if posmod(rotation, 2) == 1:
		return Vector2i(def.grid_size.y, def.grid_size.x)
	return def.grid_size


## Pay for and start an upgrade on an operational building.
func upgrade(entity: BuildingEntity) -> bool:
	if not entity.is_operational():
		return false
	if entity.level >= entity.definition.max_level:
		EventBus.notify("%s is already max level." % entity.definition.display_name, 1)
		return false
	if not ResourceManager.spend(entity.definition.cost_for_level(entity.level + 1)):
		EventBus.notify("Not enough materials!", 1)
		return false
	entity.begin_upgrade()
	return true


func remove(entity: BuildingEntity) -> void:
	if selected == entity:
		deselect()
	WorldManager.vacate_area(entity.cell, entity.footprint())
	_entities.erase(entity)
	EventBus.building_removed.emit(entity)
	entity.queue_free()


# ── Selection ────────────────────────────────────────────────────────────

func select_at(cell: Vector2i) -> void:
	var occupant := WorldManager.occupant_at(cell)
	if occupant is BuildingEntity and _entities.has(occupant):
		if selected != occupant:
			deselect()
			selected = occupant
			selected.set_selected(true)
			EventBus.building_selected.emit(selected)
	else:
		deselect()


func deselect() -> void:
	if selected == null:
		return
	if is_instance_valid(selected):
		selected.set_selected(false)
	selected = null
	EventBus.building_deselected.emit()


# ── Queries ──────────────────────────────────────────────────────────────

## First placed building with this id, or null — e.g. the Capital as
## the anchor point for survivor NPCs.
func first_of(building_id: String) -> BuildingEntity:
	for entity in _entities:
		if entity.definition.id == building_id:
			return entity
	return null


func count_of(building_id: String) -> int:
	var n := 0
	for entity in _entities:
		if entity.definition.id == building_id:
			n += 1
	return n


## Sum of one passive effect across all operational buildings,
## e.g. total_effect("population_cap") or total_effect("defense").
func total_effect(effect_id: String) -> int:
	var total := 0
	for entity in _entities:
		if entity.is_operational():
			total += int(entity.definition.effects_at_level(entity.level).get(effect_id, 0))
	return total


# ── Internal ─────────────────────────────────────────────────────────────

func _spawn(def: BuildingDefinition, cell: Vector2i, rotation: int = 0) -> BuildingEntity:
	assert(_container != null, "No world registered — call register_container() first")
	var entity: BuildingEntity = BUILDING_ENTITY_SCENE.instantiate()
	_container.add_child(entity)
	entity.setup(def, cell, rotation)
	WorldManager.occupy_area(cell, entity.footprint(), entity)
	_entities.append(entity)
	return entity


func _on_day_passed(_day: int) -> void:
	# Daily production from every operational building.
	for entity in _entities:
		if entity.is_operational():
			ResourceManager.grant(entity.definition.production_at_level(entity.level))


# ── Save contract ────────────────────────────────────────────────────────

func get_save_data() -> Array:
	var out := []
	for entity in _entities:
		out.append(entity.get_save_data())
	return out


func apply_save_data(data: Array) -> void:
	for entry: Dictionary in data:
		var def := DataManager.get_building(str(entry.get("id", "")))
		if def == null:
			push_warning("[BuildingManager] Save references unknown building: %s" % entry)
			continue
		var cell := Vector2i(int(entry.get("cx", 0)), int(entry.get("cy", 0)))
		var entity := _spawn(def, cell, int(entry.get("rot", 0)))
		entity.apply_save_data(entry)
