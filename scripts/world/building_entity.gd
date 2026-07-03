class_name BuildingEntity
extends Node3D
## One placed building in the 3D world.
##
## Pure presentation + per-instance state (level, construction progress).
## Rules about placement, cost and production live in BuildingManager;
## shared stats live in the BuildingDefinition. The visual comes from
## ModelFactory — a real .glb when the definition has one, a chunky
## placeholder otherwise.

enum BuildingState { CONSTRUCTING, OPERATIONAL, UPGRADING }

## Construction sites show the model shrunken until work completes.
const CONSTRUCTION_SCALE := 0.55

var definition: BuildingDefinition
var cell: Vector2i
var level: int = 1
var state: BuildingState = BuildingState.CONSTRUCTING
## Orientation in 90° steps (0-3).
var rotation_index: int = 0

var _remaining_build_time: float = 0.0
var _model_root: Node3D
var _select_ring: MeshInstance3D

@onready var _timer_label: Label3D = $TimerLabel


func _ready() -> void:
	EventBus.game_tick.connect(_on_game_tick)


## Called by BuildingManager right after instancing.
func setup(def: BuildingDefinition, grid_cell: Vector2i, rot: int = 0) -> void:
	definition = def
	cell = grid_cell
	rotation_index = posmod(rot, 4)
	position = WorldManager.area_center(cell, footprint())
	rotation.y = -rotation_index * PI / 2.0

	# Footprint in meters, pre-rotation (the whole entity rotates).
	var fp := Vector2(def.grid_size) * WorldManager.cell_size()
	_model_root = ModelFactory.building_model(def, fp)
	add_child(_model_root)

	_select_ring = _make_ring(fp, Color(0.9, 0.7, 0.25, 0.45))
	add_child(_select_ring)

	_timer_label.position.y = WorldManager.cell_size() * 1.6

	_begin_construction(def.build_time)


## Grid footprint with rotation applied (90°/270° swap the axes).
func footprint() -> Vector2i:
	if rotation_index % 2 == 1:
		return Vector2i(definition.grid_size.y, definition.grid_size.x)
	return definition.grid_size


func is_operational() -> bool:
	return state == BuildingState.OPERATIONAL


func finish_construction(silent: bool = false) -> void:
	var was_upgrading := state == BuildingState.UPGRADING
	state = BuildingState.OPERATIONAL
	_remaining_build_time = 0.0
	_timer_label.visible = false
	if silent:
		_model_root.scale = Vector3.ONE
		return
	# Pop up to full size.
	var tween := create_tween()
	tween.tween_property(_model_root, "scale", Vector3.ONE * 1.08, 0.18) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(_model_root, "scale", Vector3.ONE, 0.12)
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
	_select_ring.visible = selected


# ── Construction ticking ─────────────────────────────────────────────────

func _begin_construction(duration: float) -> void:
	if state == BuildingState.OPERATIONAL:
		state = BuildingState.CONSTRUCTING
	_remaining_build_time = duration
	_model_root.scale = Vector3.ONE * CONSTRUCTION_SCALE
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


## Flat translucent quad marking the footprint (selection indicator).
func _make_ring(fp: Vector2, color: Color) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = fp * 1.04
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position.y = 0.05
	mi.visible = false
	return mi


# ── Save contract (via BuildingManager) ──────────────────────────────────

func get_save_data() -> Dictionary:
	return {
		"id": definition.id,
		"cx": cell.x,
		"cy": cell.y,
		"rot": rotation_index,
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
