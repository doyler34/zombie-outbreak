class_name BuildingPlacer
extends Node3D
## Ghost-preview building placement in the 3D world.
##
## Flow: the build menu emits EventBus.building_placement_started(def) →
## a translucent ghost model snaps to the grid with a green/red
## footprint quad for validity. Tapping moves the ghost; the HUD's
## confirm / rotate / cancel buttons drive the rest. Position first,
## commit second — no accidental purchases from a single mis-tap.

const VALID_COLOR := Color(0.35, 0.9, 0.4, 0.4)
const INVALID_COLOR := Color(0.95, 0.3, 0.25, 0.45)
const GHOST_TRANSPARENCY := 0.45

var _definition: BuildingDefinition
var _ghost_cell: Vector2i
var _ghost: Node3D
var _footprint_quad: MeshInstance3D
var _quad_material: StandardMaterial3D
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
	_ghost.rotation.y = -_rotation * PI / 2.0
	_footprint_quad.rotation.y = _ghost.rotation.y
	# Re-snap: a swapped footprint changes the center and validity.
	_move_ghost(_ghost_cell)


# ── Internal ─────────────────────────────────────────────────────────────

func _on_placement_started(def: BuildingDefinition) -> void:
	_definition = def
	_active = true
	_rotation = 0
	BuildingManager.deselect()
	ObstacleManager.deselect()

	var fp := Vector2(def.grid_size) * WorldManager.cell_size()
	_ghost = ModelFactory.building_model(def, fp)
	ModelFactory.set_transparency(_ghost, GHOST_TRANSPARENCY)
	add_child(_ghost)

	var plane := PlaneMesh.new()
	plane.size = fp * 1.02
	_footprint_quad = MeshInstance3D.new()
	_footprint_quad.mesh = plane
	_quad_material = StandardMaterial3D.new()
	_quad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_quad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_footprint_quad.material_override = _quad_material
	add_child(_footprint_quad)

	# Start centered on the current camera view.
	var camera := get_viewport().get_camera_3d()
	var start := Vector3.ZERO
	if camera != null:
		var viewport_center := get_viewport().get_visible_rect().size / 2.0
		var origin := camera.project_ray_origin(viewport_center)
		var direction := camera.project_ray_normal(viewport_center)
		if absf(direction.y) > 0.0001:
			start = origin + direction * (-origin.y / direction.y)
	_move_ghost(WorldManager.world_to_cell(start))


func _on_tapped(_screen_pos: Vector2, world_pos: Vector3) -> void:
	if not _active:
		return
	# Snap the footprint so the tapped point is its center.
	var fp := _footprint()
	var corner := world_pos - Vector3(fp.x, 0, fp.y) * WorldManager.cell_size() / 2.0 \
		+ Vector3.ONE * WorldManager.cell_size() / 2.0
	_move_ghost(WorldManager.world_to_cell(corner))


## Grid footprint with the current rotation applied.
func _footprint() -> Vector2i:
	if _rotation % 2 == 1:
		return Vector2i(_definition.grid_size.y, _definition.grid_size.x)
	return _definition.grid_size


func _move_ghost(cell: Vector2i) -> void:
	_ghost_cell = cell
	var center := WorldManager.area_center(cell, _footprint())
	_ghost.position = center
	_footprint_quad.position = center + Vector3(0, 0.06, 0)
	var valid := WorldManager.is_area_buildable(cell, _footprint())
	_quad_material.albedo_color = VALID_COLOR if valid else INVALID_COLOR


func _end(confirmed: bool) -> void:
	_active = false
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _footprint_quad:
		_footprint_quad.queue_free()
		_footprint_quad = null
	EventBus.building_placement_ended.emit(confirmed)
