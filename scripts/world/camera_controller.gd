class_name CameraController
extends Node3D
## LDoE-style perspective camera rig.
##
## This node is the look-at target on the ground plane; the child
## Camera3D is pitched down and pulled back along its view axis with a
## real PERSPECTIVE projection — near things are bigger, far things
## shrink, object sides are visible, so the world reads unmistakably 3D
## (an orthographic camera flattens exactly this away). Drag pans the
## rig across the XZ plane in camera-relative directions; pinch/wheel
## flies the camera closer/further. All tuning lives in GameSettings —
## camera_*_size values are the approximate visible ground height (m),
## converted to a camera distance for the chosen field of view.
##
## When a follow target is set (the Commander), the rig tracks it every
## frame through the same smoothing. A manual drag pauses following so
## the player can look around; it resumes as soon as the target moves
## again (GameWorld wires Commander.movement_started to resume_follow).

## Vertical field of view (degrees). Modest, so the top-down framing
## keeps gentle perspective instead of fisheye distortion.
const FOV_DEGREES := 50.0

var _target_position: Vector3
## Camera boom length (m), smoothed toward _target_distance.
var _distance: float
var _target_distance: float
var _follow_target: Node3D
var _follow_paused: bool = false

@onready var camera: Camera3D = $Camera


func _ready() -> void:
	var settings := DataManager.settings
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = FOV_DEGREES
	camera.rotation_degrees = Vector3(settings.camera_pitch_degrees, settings.camera_yaw_degrees, 0)
	camera.near = 0.5
	camera.far = 400.0

	_distance = _distance_for_view_height(settings.camera_default_size)
	_target_distance = _distance
	camera.position = camera.transform.basis.z * _distance

	_target_position = position
	InputManager.drag_updated.connect(_on_drag)
	InputManager.zoom_requested.connect(_on_zoom)


func _process(delta: float) -> void:
	if is_instance_valid(_follow_target) and not _follow_paused:
		_target_position = _clamped(_follow_target.global_position)
	var weight := clampf(DataManager.settings.camera_smoothing * delta, 0.0, 1.0)
	position = position.lerp(_target_position, weight)
	_distance = lerpf(_distance, _target_distance, weight)
	camera.position = camera.transform.basis.z * _distance


## Boom length that shows roughly [param height] meters of ground
## vertically at the focus point.
func _distance_for_view_height(height: float) -> float:
	return height / (2.0 * tan(deg_to_rad(FOV_DEGREES) * 0.5))


## Snap instantly (e.g. when the world loads centered on the base).
func jump_to(world_pos: Vector3) -> void:
	_target_position = _clamped(world_pos)
	position = _target_position


## Track [param target] every frame (pass null to stop following).
func follow(target: Node3D) -> void:
	_follow_target = target
	_follow_paused = false


## Re-engage a follow that a manual pan paused.
func resume_follow() -> void:
	_follow_paused = false


# ── Gestures ─────────────────────────────────────────────────────────────

func _on_drag(delta_screen: Vector2) -> void:
	# A manual pan takes over from following until the target moves again.
	_follow_paused = true
	# World units per screen pixel: how much ground height the current
	# boom length shows, divided by the viewport height.
	var view_height := _distance * 2.0 * tan(deg_to_rad(FOV_DEGREES) * 0.5)
	var units_per_px := view_height / get_viewport().get_visible_rect().size.y
	# Camera-relative axes flattened onto the ground plane.
	var basis := camera.global_transform.basis
	var right := Vector3(basis.x.x, 0, basis.x.z).normalized()
	var forward := Vector3(-basis.z.x, 0, -basis.z.z).normalized()
	var motion := (-right * delta_screen.x + forward * delta_screen.y) * units_per_px
	_target_position = _clamped(_target_position + motion)


func _on_zoom(factor: float, _screen_pos: Vector2) -> void:
	var settings := DataManager.settings
	_target_distance = clampf(_target_distance / factor,
		_distance_for_view_height(settings.camera_min_size),
		_distance_for_view_height(settings.camera_max_size))
	# Zooming changes how much world fits on screen — re-clamp the pan.
	_target_position = _clamped(_target_position)


# ── Internal ─────────────────────────────────────────────────────────────

## Keep the focus point inside the world rect, resting on the terrain
## so hills don't drift the subject off-frame.
func _clamped(pos: Vector3) -> Vector3:
	var world := WorldManager.world_rect()
	pos.x = clampf(pos.x, world.position.x, world.end.x)
	pos.z = clampf(pos.z, world.position.y, world.end.y)
	pos.y = WorldManager.ground_height(pos)
	return pos
