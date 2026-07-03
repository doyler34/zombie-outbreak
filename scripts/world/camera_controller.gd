class_name CameraController
extends Node3D
## Clash-style orthographic camera rig.
##
## This node is the look-at target on the ground plane; the child
## Camera3D is pitched down and yawed 45° for the diagonal isometric
## look, pulled back along its view axis. Drag pans the rig across the
## XZ plane in camera-relative directions; pinch/wheel changes the
## orthographic size (chunky zoom). All tuning lives in GameSettings.

## Distance the camera sits back along its view direction. With an
## orthographic projection this only needs to clear the tallest object.
const CAMERA_DISTANCE := 90.0

var _target_position: Vector3
var _target_size: float

@onready var camera: Camera3D = $Camera


func _ready() -> void:
	var settings := DataManager.settings
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation_degrees = Vector3(settings.camera_pitch_degrees, settings.camera_yaw_degrees, 0)
	camera.size = settings.camera_default_size
	camera.near = 1.0
	camera.far = 400.0
	# Pull back along the view direction so the rig origin is the focus.
	camera.position = camera.transform.basis.z * CAMERA_DISTANCE

	_target_position = position
	_target_size = camera.size
	InputManager.drag_updated.connect(_on_drag)
	InputManager.zoom_requested.connect(_on_zoom)


func _process(delta: float) -> void:
	var weight := clampf(DataManager.settings.camera_smoothing * delta, 0.0, 1.0)
	position = position.lerp(_target_position, weight)
	camera.size = lerpf(camera.size, _target_size, weight)


## Snap instantly (e.g. when the world loads centered on the base).
func jump_to(world_pos: Vector3) -> void:
	_target_position = _clamped(world_pos)
	position = _target_position


# ── Gestures ─────────────────────────────────────────────────────────────

func _on_drag(delta_screen: Vector2) -> void:
	# World units per screen pixel at the current zoom (ortho size is
	# the vertical extent of the view).
	var units_per_px := camera.size / get_viewport().get_visible_rect().size.y
	# Camera-relative axes flattened onto the ground plane.
	var basis := camera.global_transform.basis
	var right := Vector3(basis.x.x, 0, basis.x.z).normalized()
	var forward := Vector3(-basis.z.x, 0, -basis.z.z).normalized()
	var motion := (-right * delta_screen.x + forward * delta_screen.y) * units_per_px
	_target_position = _clamped(_target_position + motion)


func _on_zoom(factor: float, _screen_pos: Vector2) -> void:
	var settings := DataManager.settings
	_target_size = clampf(_target_size / factor, settings.camera_min_size, settings.camera_max_size)
	# Zooming changes how much world fits on screen — re-clamp the pan.
	_target_position = _clamped(_target_position)


# ── Internal ─────────────────────────────────────────────────────────────

## Keep the focus point inside the world rect (XZ plane).
func _clamped(pos: Vector3) -> Vector3:
	var world := WorldManager.world_rect()
	pos.x = clampf(pos.x, world.position.x, world.end.x)
	pos.z = clampf(pos.z, world.position.y, world.end.y)
	pos.y = 0.0
	return pos
