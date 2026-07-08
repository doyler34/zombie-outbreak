class_name ObstacleEntity
extends Node3D
## One natural obstacle on the 3D map (tree, rock, debris, ...).
##
## Presentation + per-instance task state, same philosophy as
## BuildingEntity: all rules (cost, workers, rewards, tech gates) live in
## ObstacleManager and the ObstacleDefinition. Visuals come from
## ModelFactory (stylized primitives keyed by model_kind, or a real .glb
## when the definition provides one).

enum ObstacleState { INTACT, CLEARING }

var definition: ObstacleDefinition
var cell: Vector2i
var state: ObstacleState = ObstacleState.INTACT
## Current durability (future combat/tooling hook).
var health: int = 100
var assigned_workers: int = 0
var remaining_time: float = 0.0

var _model_root: Node3D
var _select_ring: MeshInstance3D

@onready var _timer_label: Label3D = $TimerLabel


func _ready() -> void:
	EventBus.game_tick.connect(_on_game_tick)


## Called by ObstacleManager right after instancing.
func setup(def: ObstacleDefinition, grid_cell: Vector2i) -> void:
	definition = def
	cell = grid_cell
	health = def.health
	position = WorldManager.area_center(cell, def.grid_size)

	var fp := Vector2(def.grid_size) * WorldManager.cell_size()
	_model_root = ModelFactory.obstacle_model(def, fp)
	add_child(_model_root)

	_select_ring = _make_ring(fp, Color(0.55, 0.85, 0.45, 0.4))
	add_child(_select_ring)

	_timer_label.position.y = WorldManager.cell_size() * 1.3

	Interactable.attach(self, "Examine",
		fp.length() / 2.0 + DataManager.settings.interaction_reach, _on_interacted)


# ── Occupancy contract (duck-typed by WorldManager) ──────────────────────

func blocks_building() -> bool:
	return definition.blocks_building


func blocks_movement() -> bool:
	return definition.blocks_movement


# ── Interaction ──────────────────────────────────────────────────────────

## Placeholder interactions until gathering/combat land — each kind of
## obstacle acknowledges the Commander with what it will become.
func _on_interacted(_actor: Node3D) -> void:
	EventBus.notify(_placeholder_message(), 0)


func _placeholder_message() -> String:
	if definition.has_tag("infested"):
		return "Best not to disturb the %s without a squad." % definition.display_name.to_lower()
	match definition.id:
		"tree", "bush":
			return "Tree interaction coming soon."
		"rock", "boulder":
			return "Rock interaction coming soon."
	if not definition.clear_rewards.is_empty():
		return "Resource gathering coming soon."
	return "Nothing to do here yet."


# ── Clearing task ────────────────────────────────────────────────────────

func is_clearing() -> bool:
	return state == ObstacleState.CLEARING


## Validation and payment already done by ObstacleManager.
func start_clearing(workers: int) -> void:
	state = ObstacleState.CLEARING
	assigned_workers = workers
	remaining_time = definition.effective_clear_time(workers)
	_timer_label.visible = true
	_update_timer_text()


func _on_game_tick() -> void:
	if state != ObstacleState.CLEARING:
		return
	remaining_time -= TimeManager.TICK_INTERVAL
	# Shrink as the work progresses — cheap, readable feedback.
	var total := definition.effective_clear_time(assigned_workers)
	_model_root.scale = Vector3.ONE * clampf(remaining_time / maxf(total, 0.1), 0.35, 1.0)
	if remaining_time <= 0.0:
		ObstacleManager.finish_clearing(self)
	else:
		_update_timer_text()


func _update_timer_text() -> void:
	_timer_label.text = "⛏ %ds" % ceili(remaining_time)


# ── Selection ────────────────────────────────────────────────────────────

func set_selected(selected: bool) -> void:
	_select_ring.visible = selected


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
		_timer_label.visible = true
		_update_timer_text()
