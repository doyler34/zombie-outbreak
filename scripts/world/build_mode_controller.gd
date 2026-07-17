class_name BuildModeController
extends Node3D
## Drives the modular-building preview while build mode is active.
##
## The BuildModeMenu picks a BuildingPiece (EventBus.piece_selected) →
## this node shows a holographic ghost that follows the cursor (mouse
## hover on desktop, taps on touch), snaps through BaseManager's spot
## logic, turns green/red with validity, rotates in 90° steps and
## commits through BaseManager.place(). After a successful placement the
## ghost stays armed so walls chain LDoE-style, tap-tap-tap.
##
## One ghost, two shared materials, zero per-frame allocations: the spot
## is only recomputed when the cursor actually crossed into another
## cell/edge.

const VALID_COLOR := Color(0.3, 0.95, 0.45, 0.5)
const INVALID_COLOR := Color(0.95, 0.3, 0.25, 0.5)

var _piece: BuildingPiece
var _ghost: Node3D
var _spot: Dictionary = {}
var _valid := false
## 0/1 = edge axis chosen with the rotate control, -1 = nearest wins.
var _axis_lock := -1
var _last_world := Vector3.ZERO
## Hover-follow only makes sense with a real pointer; touch moves the
## ghost by tapping.
@onready var _hover_follow: bool = not DisplayServer.is_touchscreen_available()

var _valid_material := StandardMaterial3D.new()
var _invalid_material := StandardMaterial3D.new()


func _ready() -> void:
	add_to_group("build_mode_controller")
	for entry in [[_valid_material, VALID_COLOR], [_invalid_material, INVALID_COLOR]]:
		var material: StandardMaterial3D = entry[0]
		material.albedo_color = entry[1]
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = false
	EventBus.piece_selected.connect(_on_piece_selected)
	EventBus.build_mode_changed.connect(_on_build_mode_changed)
	EventBus.piece_placed.connect(func(_e): _refresh())
	InputManager.tapped.connect(_on_tapped)


func is_previewing() -> bool:
	return _ghost != null


## Rotate the preview 90°: for edge pieces that means "the other edge
## direction" — the ghost re-snaps to the nearest edge of that axis.
func rotate_preview() -> void:
	if _piece == null or not _piece.rotatable or _piece.placement != "edge":
		return
	_axis_lock = 1 - int(_spot.get("axis", 0))
	_retarget(_last_world, true)


func confirm() -> void:
	if _piece == null or _spot.is_empty():
		return
	if BaseManager.place(_piece, _spot) != null:
		# Placement changed the world — re-snap in place (stacks climb,
		# occupied edges advance a level) so chain building just works.
		_retarget(_last_world, true)
	# Invalid spot: the red ghost is the feedback. Cost failure: place()
	# already notified. Either way the ghost stays armed.


func cancel() -> void:
	EventBus.piece_selected.emit(null)


func _process(_delta: float) -> void:
	if _ghost == null or not _hover_follow:
		return
	var world := InputManager.screen_to_world(get_viewport().get_mouse_position())
	if world != Vector3.ZERO:
		_retarget(world)


func _unhandled_key_input(event: InputEvent) -> void:
	if _ghost == null or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey
	if key.keycode == KEY_R:
		rotate_preview()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_SPACE:
		confirm()
	elif key.keycode == KEY_ESCAPE:
		cancel()


# ── Internal ─────────────────────────────────────────────────────────────

func _on_build_mode_changed(active: bool) -> void:
	if not active:
		_clear_ghost()


func _on_piece_selected(piece: BuildingPiece) -> void:
	_clear_ghost()
	_piece = piece
	if piece == null:
		return
	_axis_lock = -1
	_ghost = PiecePlacement.build_visual(piece)
	add_child(_ghost)
	# Start under the middle of the screen so the ghost never pops in
	# somewhere off-camera.
	var center := InputManager.screen_to_world(
		get_viewport().get_visible_rect().size / 2.0)
	_retarget(center, true)


func _on_tapped(_screen_pos: Vector2, world_pos: Vector3) -> void:
	if _ghost != null and world_pos != Vector3.ZERO:
		_retarget(world_pos)


## Re-snap the ghost for a cursor at [param world]. Skips all work when
## the snap target didn't change (the common hover case).
func _retarget(world: Vector3, force: bool = false) -> void:
	_last_world = world
	var spot := BaseManager.best_spot_for(_piece, world, _axis_lock)
	if not force and spot == _spot:
		return
	_spot = spot
	_ghost.transform = PiecePlacement.spot_transform(_piece, spot)
	_refresh()


## Recheck validity and repaint (world changed or ghost moved).
func _refresh() -> void:
	if _ghost == null or _spot.is_empty():
		return
	_valid = BaseManager.can_place(_piece, _spot)
	_paint(_ghost, _valid_material if _valid else _invalid_material)


func _clear_ghost() -> void:
	_piece = null
	_spot = {}
	_valid = false
	_axis_lock = -1
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null


static func _paint(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_paint(child, material)
