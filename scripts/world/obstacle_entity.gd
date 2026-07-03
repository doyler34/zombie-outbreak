class_name ObstacleEntity
extends Node2D
## One natural obstacle on the map (tree, rock, debris, ...).
##
## Presentation + per-instance task state, same philosophy as
## BuildingEntity: all rules (cost, workers, rewards, tech gates) live in
## ObstacleManager and the ObstacleDefinition. Every obstacle type uses
## this one scene — behaviour differences come from data.

enum ObstacleState { INTACT, CLEARING }

var definition: ObstacleDefinition
var cell: Vector2i
var state: ObstacleState = ObstacleState.INTACT
## Current durability (future combat/tooling hook).
var health: int = 100
var assigned_workers: int = 0
var remaining_time: float = 0.0

var _selected: bool = false

@onready var _sprite: Sprite2D = $Sprite
@onready var _timer_label: Label = $TimerLabel


func _ready() -> void:
	EventBus.game_tick.connect(_on_game_tick)


## Called by ObstacleManager right after instancing.
func setup(def: ObstacleDefinition, grid_cell: Vector2i) -> void:
	definition = def
	cell = grid_cell
	health = def.health
	position = WorldManager.area_center(cell, def.grid_size)

	_sprite.texture = def.texture
	if def.texture:
		var fp := Vector2(def.grid_size * WorldManager.cell_size())
		var tex_size := def.texture.get_size()
		var s := minf(fp.x / tex_size.x, fp.y / tex_size.y)
		_sprite.scale = Vector2(s, s)


# ── Occupancy contract (duck-typed by WorldManager) ──────────────────────

func blocks_building() -> bool:
	return definition.blocks_building


func blocks_movement() -> bool:
	return definition.blocks_movement


# ── Clearing task ────────────────────────────────────────────────────────

func is_clearing() -> bool:
	return state == ObstacleState.CLEARING


## Validation and payment already done by ObstacleManager.
func start_clearing(workers: int) -> void:
	state = ObstacleState.CLEARING
	assigned_workers = workers
	remaining_time = definition.effective_clear_time(workers)
	_sprite.modulate = Color(1, 1, 1, 0.75)
	_timer_label.visible = true
	_update_timer_text()


func _on_game_tick() -> void:
	if state != ObstacleState.CLEARING:
		return
	remaining_time -= TimeManager.TICK_INTERVAL
	if remaining_time <= 0.0:
		ObstacleManager.finish_clearing(self)
	else:
		_update_timer_text()


func _update_timer_text() -> void:
	_timer_label.text = "⛏ %ds" % ceili(remaining_time)


# ── Selection ────────────────────────────────────────────────────────────

func set_selected(selected: bool) -> void:
	_selected = selected
	queue_redraw()


func _draw() -> void:
	if not _selected:
		return
	var fp := Vector2(definition.grid_size * WorldManager.cell_size())
	draw_rect(Rect2(-fp / 2.0, fp), Color(0.55, 0.85, 0.45, 0.9), false, 3.0)


# ── Save contract (via ObstacleManager) ──────────────────────────────────

func get_save_data() -> Dictionary:
	return {
		"id": definition.id,
		"cx": cell.x,
		"cy": cell.y,
		"state": state,
		"remaining": remaining_time,
		"workers": assigned_workers,
		"health": health,
	}


func apply_save_data(data: Dictionary) -> void:
	health = int(data.get("health", definition.health))
	if int(data.get("state", ObstacleState.INTACT)) == ObstacleState.CLEARING:
		state = ObstacleState.CLEARING
		assigned_workers = int(data.get("workers", 0))
		remaining_time = float(data.get("remaining", 1.0))
		_sprite.modulate = Color(1, 1, 1, 0.75)
		_timer_label.visible = true
		_update_timer_text()
