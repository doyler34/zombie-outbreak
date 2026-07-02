class_name BuildingPlacer
extends Node2D
## Ghost-preview building placement (city-builder style).
##
## Flow: the build menu emits EventBus.building_placement_started(def) →
## this node shows a translucent ghost that snaps to the grid and tints
## green/red for validity. Tapping moves the ghost; the HUD's confirm /
## cancel buttons call confirm() / cancel().
##
## Placement is mobile-friendly: position first, commit second — no
## accidental purchases from a single mis-tap.

const VALID_TINT := Color(0.5, 1.0, 0.5, 0.6)
const INVALID_TINT := Color(1.0, 0.35, 0.35, 0.6)
const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.07)

var _definition: BuildingDefinition
var _ghost_cell: Vector2i
var _ghost_sprite: Sprite2D
var _active: bool = false
## Ghost orientation in 90° steps (0-3).
var _rotation: int = 0


func _ready() -> void:
	EventBus.building_placement_started.connect(_on_placement_started)
	InputManager.tapped.connect(_on_tapped)


func is_active() -> bool:
	return _active


func confirm() -> void:
	if not _active:
		return
	var entity := BuildingManager.place(_definition, _ghost_cell, _rotation)
	if entity != null:
		_end(true)
	# On failure keep placement active so the player can pick another spot.


func cancel() -> void:
	if _active:
		_end(false)


## Rotate the ghost 90° clockwise (wired to the HUD's rotate button).
func rotate_ghost() -> void:
	if not _active:
		return
	_rotation = (_rotation + 1) % 4
	_ghost_sprite.rotation = _rotation * PI / 2.0
	# Re-snap: a swapped footprint changes the center and validity.
	_move_ghost(_ghost_cell)


# ── Internal ─────────────────────────────────────────────────────────────

func _on_placement_started(def: BuildingDefinition) -> void:
	_definition = def
	_active = true
	_rotation = 0
	BuildingManager.deselect()

	_ghost_sprite = Sprite2D.new()
	_ghost_sprite.texture = def.texture
	if def.texture:
		var footprint := Vector2(def.grid_size * WorldManager.cell_size())
		var tex_size := def.texture.get_size()
		var s := minf(footprint.x / tex_size.x, footprint.y / tex_size.y)
		_ghost_sprite.scale = Vector2(s, s)
	add_child(_ghost_sprite)

	# Start centered on the current camera view.
	var camera := get_viewport().get_camera_2d()
	var start := camera.position if camera else Vector2.ZERO
	_move_ghost(WorldManager.world_to_cell(start))
	queue_redraw()


func _on_tapped(_screen_pos: Vector2, world_pos: Vector2) -> void:
	if not _active:
		return
	# Snap the footprint so the tapped point is its center.
	var half := Vector2(_footprint()) * WorldManager.cell_size() / 2.0
	_move_ghost(WorldManager.world_to_cell(world_pos - half + Vector2.ONE * WorldManager.cell_size() / 2.0))


## Grid footprint with the current rotation applied.
func _footprint() -> Vector2i:
	if _rotation % 2 == 1:
		return Vector2i(_definition.grid_size.y, _definition.grid_size.x)
	return _definition.grid_size


func _move_ghost(cell: Vector2i) -> void:
	_ghost_cell = cell
	_ghost_sprite.position = WorldManager.area_center(cell, _footprint())
	var valid := WorldManager.is_area_free(cell, _footprint())
	_ghost_sprite.modulate = VALID_TINT if valid else INVALID_TINT
	queue_redraw()


func _end(confirmed: bool) -> void:
	_active = false
	if _ghost_sprite:
		_ghost_sprite.queue_free()
		_ghost_sprite = null
	queue_redraw()
	EventBus.building_placement_ended.emit(confirmed)


func _draw() -> void:
	if not _active:
		return
	# Subtle grid over the whole world while placing.
	var world := WorldManager.world_rect()
	var cs := float(WorldManager.cell_size())
	var x := world.position.x
	while x <= world.end.x:
		draw_line(Vector2(x, world.position.y), Vector2(x, world.end.y), GRID_COLOR, 1.0)
		x += cs
	var y := world.position.y
	while y <= world.end.y:
		draw_line(Vector2(world.position.x, y), Vector2(world.end.x, y), GRID_COLOR, 1.0)
		y += cs
	# Footprint outline under the ghost.
	var footprint := Rect2(WorldManager.cell_to_world(_ghost_cell),
		Vector2(_footprint()) * cs)
	var valid := WorldManager.is_area_free(_ghost_cell, _footprint())
	draw_rect(footprint, Color(0.4, 1.0, 0.4, 0.9) if valid else Color(1.0, 0.3, 0.3, 0.9), false, 2.0)
