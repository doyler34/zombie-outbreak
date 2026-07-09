extends Node
## ObstacleManager — natural obstacles and clearing operations (autoload).
##
## Owns every ObstacleEntity on the map: procedural scatter on new games
## (data/tables/world_generation.json), the timed clearing flow (pay →
## optionally assign workers → wait → rewards + freed build space), and
## persistence including regrowth queues.
##
## Future hooks already wired:
##  - required_tech gates clearing until a research system answers
##    is_tech_unlocked()
##  - the "infested" tag emits obstacle_infestation_triggered for a
##    future combat system to intercept
##  - finish_clearing_now() is the entry point for premium speed-ups
##  - regrow_days respawns vegetation via the day_passed signal

const OBSTACLE_ENTITY_SCENE := preload("res://scenes/world/obstacle_entity.tscn")

var selected: ObstacleEntity = null

var _entities: Array[ObstacleEntity] = []
var _container: Node = null
## Cleared obstacles waiting to regrow: {"id": ..., "cx": ..., "cy": ..., "days": ...}
var _regrow_queue: Array = []


func _ready() -> void:
	SaveManager.register_section("obstacles", self)
	EventBus.day_passed.connect(_on_day_passed)


## Called by GameWorld when it enters the tree.
func register_container(container: Node) -> void:
	_container = container


func reset() -> void:
	for entity in _entities:
		entity.queue_free()
	_entities.clear()
	_regrow_queue.clear()
	selected = null
	_container = null


# ── World generation ─────────────────────────────────────────────────────

## Scatter obstacles for a NEW game, from data/tables/world_generation.json.
## Never called when loading — saved obstacles are restored instead.
func generate_initial_obstacles() -> void:
	var table: Dictionary = DataManager.get_table("world_generation")
	if table == null:
		push_warning("[ObstacleManager] No world_generation table; map will be empty.")
		return
	var clear_radius := int(table.get("spawn_clear_radius_cells", 5))
	var half := DataManager.settings.world_size / 2
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for entry: Dictionary in table.get("obstacles", []):
		var def := DataManager.get_obstacle(str(entry.get("id", "")))
		if def == null:
			push_warning("[ObstacleManager] world_generation references unknown obstacle: %s" % entry)
			continue
		var placed := 0
		var attempts := 0
		var target := int(entry.get("count", 0))
		# Cap attempts so a crowded map can't hang generation.
		while placed < target and attempts < target * 20:
			attempts += 1
			var cell := Vector2i(
				rng.randi_range(-half.x, half.x - def.grid_size.x),
				rng.randi_range(-half.y, half.y - def.grid_size.y))
			# Keep the starting area buildable.
			if Vector2(cell + def.grid_size / 2).length() < clear_radius:
				continue
			if not WorldManager.is_area_free(cell, def.grid_size):
				continue
			_spawn(def, cell)
			placed += 1


# ── Clearing flow ────────────────────────────────────────────────────────

## Start a timed clearing task. Validates tech, workers and cost;
## reserves workers until the task completes. Returns true on success.
func start_clearing(entity: ObstacleEntity, workers: int = 0) -> bool:
	var def := entity.definition
	if not def.clearable:
		EventBus.notify("That can't be removed.", 1)
		return false
	if entity.is_clearing():
		return false
	if def.has_tag("infested"):
		# Zombies inside — this goes through CombatManager, not workers.
		EventBus.notify("It's crawling with zombies. Send a squad!", 1)
		return false
	if not is_tech_unlocked(def.required_tech):
		EventBus.notify("Requires research: %s" % def.required_tech.capitalize(), 1)
		return false
	workers = clampi(workers, def.min_workers, def.max_workers)
	if workers < def.min_workers:
		EventBus.notify("Needs at least %d workers." % def.min_workers, 1)
		return false
	if workers > SurvivorManager.available_workers():
		EventBus.notify("Not enough free survivors!", 1)
		return false
	if not ResourceManager.spend(def.clear_cost):
		EventBus.notify("Not enough materials!", 1)
		return false

	SurvivorManager.reserve_workers(workers)
	# Future combat system intercepts this before the timer matters.
	if def.has_tag("infested"):
		EventBus.obstacle_infestation_triggered.emit(entity)
	entity.start_clearing(workers)
	EventBus.obstacle_clear_started.emit(entity, workers)
	return true


## Completes a running task: releases workers, grants rewards, frees the
## build space permanently, queues regrowth if the data asks for it.
## Called by the entity's timer — or directly by speed-up mechanics.
func finish_clearing(entity: ObstacleEntity) -> void:
	if not entity.is_clearing():
		return
	SurvivorManager.release_workers(entity.assigned_workers)
	var rewards := entity.definition.clear_rewards
	ResourceManager.grant(rewards)

	if entity.definition.regrow_days > 0:
		_regrow_queue.append({
			"id": entity.definition.id,
			"cx": entity.cell.x, "cy": entity.cell.y,
			"days": entity.definition.regrow_days,
		})

	EventBus.obstacle_cleared.emit(entity, rewards)
	EventBus.notify("%s cleared!  %s" % [entity.definition.display_name, _rewards_text(rewards)], 2)
	_remove(entity)


## Premium speed-up entry point (gems/ads/boosts later): completes the
## task immediately. The monetization layer only needs to decide WHETHER
## to call this — the game logic is already here.
func finish_clearing_now(entity: ObstacleEntity) -> void:
	finish_clearing(entity)


## Remove a zone that was cleansed by combat (CombatManager pays no
## clearing cost and grants mission rewards instead of clear_rewards).
func clear_zone(entity: ObstacleEntity) -> void:
	EventBus.obstacle_cleared.emit(entity, {})
	_remove(entity)


## A gatherable node ran dry: free its spot. Vegetation with
## regrow_days re-enters the same regrowth queue clearing uses.
func deplete(entity: ObstacleEntity) -> void:
	if entity.definition.regrow_days > 0:
		_regrow_queue.append({
			"id": entity.definition.id,
			"cx": entity.cell.x, "cy": entity.cell.y,
			"days": entity.definition.regrow_days,
		})
	EventBus.notify("%s depleted." % entity.definition.display_name, 0)
	EventBus.obstacle_cleared.emit(entity, {})
	_remove(entity)


## Research gate. Returns true until a research/tech system exists —
## replace the body with a ResearchManager lookup when it lands.
func is_tech_unlocked(tech_id: String) -> bool:
	return tech_id == ""


# ── Selection ────────────────────────────────────────────────────────────

func select(entity: ObstacleEntity) -> void:
	if selected == entity:
		return
	deselect()
	selected = entity
	selected.set_selected(true)
	EventBus.obstacle_selected.emit(entity)


func deselect() -> void:
	if selected == null:
		return
	if is_instance_valid(selected):
		selected.set_selected(false)
	selected = null
	EventBus.obstacle_deselected.emit()


# ── Internal ─────────────────────────────────────────────────────────────

func _spawn(def: ObstacleDefinition, cell: Vector2i) -> ObstacleEntity:
	assert(_container != null, "No world registered — call register_container() first")
	var entity: ObstacleEntity = OBSTACLE_ENTITY_SCENE.instantiate()
	_container.add_child(entity)
	entity.setup(def, cell)
	# Purely decorative objects don't reserve grid space.
	if def.blocks_building or def.blocks_movement:
		WorldManager.occupy_area(cell, def.grid_size, entity)
	_entities.append(entity)
	return entity


func _remove(entity: ObstacleEntity) -> void:
	if selected == entity:
		deselect()
	var def := entity.definition
	if def.blocks_building or def.blocks_movement:
		WorldManager.vacate_area(entity.cell, def.grid_size)
	_entities.erase(entity)
	entity.queue_free()


func _on_day_passed(_day: int) -> void:
	# Regrowth: count down, respawn when the spot is still free.
	for i in range(_regrow_queue.size() - 1, -1, -1):
		var entry: Dictionary = _regrow_queue[i]
		entry.days = int(entry.days) - 1
		if entry.days > 0:
			continue
		var def := DataManager.get_obstacle(str(entry.id))
		var cell := Vector2i(int(entry.cx), int(entry.cy))
		if def != null and WorldManager.is_area_free(cell, def.grid_size):
			_spawn(def, cell)
			_regrow_queue.remove_at(i)
		# Spot occupied: leave the entry with days == 0 and retry tomorrow.


func _rewards_text(rewards: Dictionary) -> String:
	var parts: Array[String] = []
	for id in rewards:
		var def := DataManager.get_resource_def(id)
		parts.append("+%d %s" % [rewards[id], def.icon if def else id])
	return "  ".join(parts)


# ── Save contract ────────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	var entities := []
	for entity in _entities:
		entities.append(entity.get_save_data())
	return {"entities": entities, "regrow": _regrow_queue}


func apply_save_data(data: Dictionary) -> void:
	_regrow_queue = data.get("regrow", [])
	for entry: Dictionary in data.get("entities", []):
		var def := DataManager.get_obstacle(str(entry.get("id", "")))
		if def == null:
			push_warning("[ObstacleManager] Save references unknown obstacle: %s" % entry)
			continue
		var cell := Vector2i(int(entry.get("cx", 0)), int(entry.get("cy", 0)))
		var entity := _spawn(def, cell)
		entity.apply_save_data(entry)
		# Tasks in flight keep their crews (survivors section loads first).
		if entity.is_clearing():
			SurvivorManager.reserve_workers(entity.assigned_workers)
