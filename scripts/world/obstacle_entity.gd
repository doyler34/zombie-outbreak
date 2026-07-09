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

## Generic action clips a gather falls back to when the node's own
## gather_anim isn't on the actor's rig.
const GATHER_ANIM_FALLBACKS: Array[String] = ["Interact", "PickUp_Table", "Fixing_Kneeling", "pick-up"]
## Speed bonus for using the node's ideal tool (multiplies gather_time).
const IDEAL_TOOL_TIME := 0.7
## All gatherable nodes join this group so starting work at one node
## stops any gather already running elsewhere (one Commander, one job).
const GATHER_GROUP := "gather_nodes"

var definition: ObstacleDefinition
var cell: Vector2i
var state: ObstacleState = ObstacleState.INTACT
## Current durability (future combat/tooling hook).
var health: int = 100
var assigned_workers: int = 0
var remaining_time: float = 0.0
## Units of gather_item still in the node (gatherable nodes only).
var stock: int = 0

var _model_root: Node3D
var _select_ring: MeshInstance3D
var _interactable: Interactable
var _gather_actor: Node3D
var _gather_left: float = 0.0

@onready var _timer_label: Label3D = $TimerLabel


func _ready() -> void:
	EventBus.game_tick.connect(_on_game_tick)


## Called by ObstacleManager right after instancing.
func setup(def: ObstacleDefinition, grid_cell: Vector2i) -> void:
	definition = def
	cell = grid_cell
	health = def.health
	stock = def.gather_stock
	position = WorldManager.area_center(cell, def.grid_size)

	var fp := Vector2(def.grid_size) * WorldManager.cell_size()
	_model_root = ModelFactory.obstacle_model(def, fp)
	add_child(_model_root)

	_select_ring = _make_ring(fp, Color(0.55, 0.85, 0.45, 0.4))
	add_child(_select_ring)

	_timer_label.position.y = WorldManager.cell_size() * 1.3

	_interactable = Interactable.attach(self, "Examine",
		fp.length() / 2.0 + DataManager.settings.interaction_reach, _on_interacted)
	if def.is_gatherable():
		add_to_group(GATHER_GROUP)
	_refresh_prompt()


# ── Occupancy contract (duck-typed by WorldManager) ──────────────────────

func blocks_building() -> bool:
	return definition.blocks_building


func blocks_movement() -> bool:
	return definition.blocks_movement


# ── Interaction ──────────────────────────────────────────────────────────

func _on_interacted(actor: Node3D) -> void:
	if definition.has_tag("infested"):
		EventBus.notify("Best not to disturb the %s without a squad."
			% definition.display_name.to_lower(), 1)
		return
	if definition.is_gatherable() and not is_clearing():
		_try_start_gather(actor)
		return
	EventBus.notify("Nothing to do here yet.", 0)


func _refresh_prompt() -> void:
	if _interactable == null:
		return
	if definition.is_gatherable():
		_interactable.prompt = "%s %s (%d)" % [definition.gather_verb,
			definition.display_name, stock]
	# Non-gatherables keep the "Examine" default.


# ── Gathering ────────────────────────────────────────────────────────────

func is_gathering() -> bool:
	return _gather_actor != null


## One tap starts a gather cycle; cycles auto-repeat until the node is
## dry, the backpack is full, or the Commander walks away.
func _try_start_gather(actor: Node3D) -> void:
	if is_gathering():
		return
	# One job at a time — walking to a new node abandons the old one.
	get_tree().call_group(GATHER_GROUP, "cancel_gather")
	if definition.gather_tool != "" and InventoryManager.equipped_tool() == null:
		var ideal := DataManager.get_item(definition.gather_tool)
		EventBus.notify("Equip a tool to %s — a %s works best." % [
			definition.gather_verb.to_lower(),
			ideal.display_name if ideal != null else definition.gather_tool], 1)
		return
	if not InventoryManager.can_add(definition.gather_item, 1):
		EventBus.notify("Inventory full!", 1)
		return

	_gather_actor = actor
	_gather_left = _cycle_time()
	_timer_label.visible = true
	_update_timer_text()
	# Walking away cancels the work.
	if actor.has_signal("movement_started") \
			and not actor.movement_started.is_connected(cancel_gather):
		actor.movement_started.connect(cancel_gather)
	if actor.has_method("play_action"):
		var candidates: Array[String] = []
		if definition.gather_anim != "":
			candidates.append(definition.gather_anim)
		candidates.append_array(GATHER_ANIM_FALLBACKS)
		actor.play_action(candidates)


func _process(delta: float) -> void:
	if not is_gathering():
		return
	_gather_left -= delta
	if _gather_left <= 0.0:
		_finish_gather_cycle()
	else:
		_update_timer_text()


func _finish_gather_cycle() -> void:
	var granted: int = InventoryManager.add_item(definition.gather_item,
		mini(definition.gather_yield, stock))
	if granted <= 0:
		cancel_gather()  # backpack filled up mid-swing
		return
	stock -= granted
	var item := DataManager.get_item(definition.gather_item)
	EventBus.notify("+%d %s %s" % [granted,
		item.icon if item != null else "",
		item.display_name if item != null else definition.gather_item], 2)
	EventBus.resource_gathered.emit(self, definition.gather_item, granted)
	_refresh_prompt()

	if stock <= 0:
		cancel_gather()
		ObstacleManager.deplete(self)
		return
	if not InventoryManager.can_add(definition.gather_item, 1):
		cancel_gather()
		EventBus.notify("Inventory full!", 1)
		return
	_gather_left = _cycle_time()  # keep working


func cancel_gather() -> void:
	if _gather_actor != null:
		if _gather_actor.has_signal("movement_started") \
				and _gather_actor.movement_started.is_connected(cancel_gather):
			_gather_actor.movement_started.disconnect(cancel_gather)
		if _gather_actor.has_method("stop_action"):
			_gather_actor.stop_action()
	_gather_actor = null
	_timer_label.visible = false


func _cycle_time() -> float:
	var ideal := definition.gather_tool != "" \
		and InventoryManager.equipped_tool() != null \
		and InventoryManager.equipped_tool().id == definition.gather_tool
	return definition.gather_time * (IDEAL_TOOL_TIME if ideal else 1.0)


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
	if is_gathering():
		_timer_label.text = "⛏ %ds" % ceili(_gather_left)
	else:
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
		"stock": stock,
	}


func apply_save_data(data: Dictionary) -> void:
	health = int(data.get("health", definition.health))
	stock = int(data.get("stock", definition.gather_stock))
	_refresh_prompt()
	if int(data.get("state", ObstacleState.INTACT)) == ObstacleState.CLEARING:
		state = ObstacleState.CLEARING
		assigned_workers = int(data.get("workers", 0))
		remaining_time = float(data.get("remaining", 1.0))
		_timer_label.visible = true
		_update_timer_text()
