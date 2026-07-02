class_name BuildingEntity
extends Node2D
## One placed building in the world.
##
## Pure presentation + per-instance state (level, construction progress).
## Rules about placement, cost and production live in BuildingManager;
## shared stats live in the BuildingDefinition. This node never mutates
## global state directly.

enum BuildingState { CONSTRUCTING, OPERATIONAL, UPGRADING }

var definition: BuildingDefinition
var cell: Vector2i
var level: int = 1
var state: BuildingState = BuildingState.CONSTRUCTING

var _remaining_build_time: float = 0.0
var _selected: bool = false

@onready var _sprite: Sprite2D = $Sprite
@onready var _timer_label: Label = $TimerLabel


func _ready() -> void:
	EventBus.game_tick.connect(_on_game_tick)


## Called by BuildingManager right after instancing.
func setup(def: BuildingDefinition, grid_cell: Vector2i) -> void:
	definition = def
	cell = grid_cell
	position = WorldManager.area_center(cell, def.grid_size)

	_sprite.texture = def.texture
	if def.texture:
		# Scale the art to the grid footprint, whatever its native size.
		var footprint := Vector2(def.grid_size * WorldManager.cell_size())
		var tex_size := def.texture.get_size()
		var s := minf(footprint.x / tex_size.x, footprint.y / tex_size.y)
		_sprite.scale = Vector2(s, s)

	_begin_construction(def.build_time)


func is_operational() -> bool:
	return state == BuildingState.OPERATIONAL


func finish_construction(silent: bool = false) -> void:
	var was_upgrading := state == BuildingState.UPGRADING
	state = BuildingState.OPERATIONAL
	_remaining_build_time = 0.0
	_timer_label.visible = false
	_sprite.modulate = Color.WHITE
	if silent:
		return
	if was_upgrading:
		level += 1
		EventBus.building_upgraded.emit(self, level)
		EventBus.notify("%s upgraded to Lv%d!" % [definition.display_name, level], 2)
	else:
		EventBus.building_construction_finished.emit(self)
		EventBus.notify("%s built!" % definition.display_name, 2)


## Start an upgrade (validation + payment already done by the caller).
func begin_upgrade() -> void:
	state = BuildingState.UPGRADING
	_begin_construction(definition.build_time)


func set_selected(selected: bool) -> void:
	_selected = selected
	queue_redraw()


func _draw() -> void:
	if not _selected:
		return
	# Brass selection frame around the footprint.
	var footprint := Vector2(definition.grid_size * WorldManager.cell_size())
	draw_rect(Rect2(-footprint / 2.0, footprint), Color(0.9, 0.7, 0.25, 0.9), false, 3.0)


# ── Construction ticking ─────────────────────────────────────────────────

func _begin_construction(duration: float) -> void:
	if state == BuildingState.OPERATIONAL:
		state = BuildingState.CONSTRUCTING
	_remaining_build_time = duration
	_sprite.modulate = Color(1, 1, 1, 0.55)
	_timer_label.visible = true
	_update_timer_text()


func _on_game_tick() -> void:
	if state == BuildingState.OPERATIONAL:
		return
	_remaining_build_time -= TimeManager.TICK_INTERVAL
	if _remaining_build_time <= 0.0:
		finish_construction()
	else:
		_update_timer_text()


func _update_timer_text() -> void:
	_timer_label.text = "⚙ %ds" % ceili(_remaining_build_time)


# ── Save contract (via BuildingManager) ──────────────────────────────────

func get_save_data() -> Dictionary:
	return {
		"id": definition.id,
		"cx": cell.x,
		"cy": cell.y,
		"level": level,
		"state": state,
		"remaining": _remaining_build_time,
	}


func apply_save_data(data: Dictionary) -> void:
	level = int(data.get("level", 1))
	state = int(data.get("state", BuildingState.CONSTRUCTING)) as BuildingState
	_remaining_build_time = float(data.get("remaining", 0.0))
	if state == BuildingState.OPERATIONAL:
		finish_construction(true)
	else:
		_update_timer_text()
