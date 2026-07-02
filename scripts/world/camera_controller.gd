class_name CameraController
extends Camera2D
## RTS-style camera: one-finger / mouse drag to pan, pinch or wheel to
## zoom toward the gesture point, clamped to the world bounds.
##
## All gestures arrive pre-digested from InputManager, so this script
## contains zero platform-specific input code. Tuning lives in
## GameSettings (zoom range, smoothing, wheel step).

var _target_position: Vector2
var _target_zoom: float = 1.0


func _ready() -> void:
	_target_position = position
	_target_zoom = zoom.x
	InputManager.drag_updated.connect(_on_drag)
	InputManager.zoom_requested.connect(_on_zoom)


func _process(delta: float) -> void:
	var weight := clampf(DataManager.settings.camera_smoothing * delta, 0.0, 1.0)
	position = position.lerp(_target_position, weight)
	var z := lerpf(zoom.x, _target_zoom, weight)
	zoom = Vector2(z, z)


## Snap instantly (e.g. when the world loads centered on the base).
func jump_to(world_pos: Vector2) -> void:
	_target_position = _clamped(world_pos)
	position = _target_position


# ── Gestures ─────────────────────────────────────────────────────────────

func _on_drag(delta_screen: Vector2) -> void:
	# Screen-space drag → world-space pan (inverted; scaled by zoom).
	_target_position = _clamped(_target_position - delta_screen / zoom.x)


func _on_zoom(factor: float, screen_pos: Vector2) -> void:
	var settings := DataManager.settings
	var old_zoom := _target_zoom
	_target_zoom = clampf(_target_zoom * factor, settings.camera_min_zoom, settings.camera_max_zoom)
	if is_equal_approx(old_zoom, _target_zoom):
		return
	# Keep the point under the finger/cursor stationary while zooming.
	var viewport_center := get_viewport_rect().size / 2.0
	var offset_from_center := (screen_pos - viewport_center) / old_zoom
	var world_focus := _target_position + offset_from_center
	_target_position = _clamped(world_focus - offset_from_center * old_zoom / _target_zoom)


# ── Internal ─────────────────────────────────────────────────────────────

## Keep the camera center inside the world rect (with a half-view margin
## so the view never shows past the edge more than necessary).
func _clamped(pos: Vector2) -> Vector2:
	var world := WorldManager.world_rect()
	var half_view := get_viewport_rect().size / (2.0 * _target_zoom)
	var min_pos := world.position + half_view
	var max_pos := world.end - half_view
	# If the world is smaller than the view on an axis, just center it.
	if min_pos.x > max_pos.x:
		pos.x = world.get_center().x
	else:
		pos.x = clampf(pos.x, min_pos.x, max_pos.x)
	if min_pos.y > max_pos.y:
		pos.y = world.get_center().y
	else:
		pos.y = clampf(pos.y, min_pos.y, max_pos.y)
	return pos
