extends Node
## InputManager — unified touch + mouse input (autoload).
##
## Translates raw events into high-level gestures so gameplay code never
## touches InputEvent directly (the same idea as open-rts's controller
## layer). Works identically for Android touch and desktop mouse:
##
##   tapped(screen, world)        — quick press+release (select / place)
##   long_pressed(screen, world)  — press held in place (context actions)
##   drag_updated(delta_screen)   — one finger / left-mouse drag (camera pan)
##   zoom_requested(factor, screen) — pinch or mouse wheel (camera zoom)
##
## Uses _unhandled_input, so any Control that accepts the event (buttons,
## panels) automatically blocks world input — no manual "is pointer over
## UI" checks anywhere.

signal tapped(screen_pos: Vector2, world_pos: Vector3)
signal double_tapped(screen_pos: Vector2, world_pos: Vector3)
signal long_pressed(screen_pos: Vector2, world_pos: Vector3)
signal drag_started(screen_pos: Vector2)
signal drag_updated(delta: Vector2)
signal drag_ended()
signal zoom_requested(factor: float, screen_pos: Vector2)

var _touches: Dictionary = {}  # finger index -> screen position
var _press_pos: Vector2
var _press_time: float = 0.0
var _pressing: bool = false
var _dragging: bool = false
var _long_press_fired: bool = false
var _pinch_distance: float = 0.0
var _last_tap_pos: Vector2 = Vector2.ZERO
var _last_tap_time: float = -10.0
const DOUBLE_TAP_THRESHOLD := 0.3
const DOUBLE_TAP_DISTANCE := 30.0


func _process(delta: float) -> void:
	if _pressing and not _dragging and not _long_press_fired:
		_press_time += delta
		if _press_time >= DataManager.settings.long_press_duration:
			_long_press_fired = true
			long_pressed.emit(_press_pos, _to_world(_press_pos))


func _unhandled_input(event: InputEvent) -> void:
	# Touch screens; mouse events arrive as emulated touches when
	# pointing/emulate_touch_from_mouse is enabled in project settings.
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseButton:
		_handle_wheel(event)


# ── Internal ─────────────────────────────────────────────────────────────

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_pressing = true
			_dragging = false
			_long_press_fired = false
			_press_pos = event.position
			_press_time = 0.0
		elif _touches.size() == 2:
			# Second finger down: switch from pan/tap to pinch.
			_end_single_gesture(false)
			_pinch_distance = _touch_span()
	else:
		var was_single := _touches.size() == 1
		_touches.erase(event.index)
		if was_single and _pressing:
			var is_tap := not _dragging and not _long_press_fired \
				and _press_time <= DataManager.settings.tap_max_duration \
				and event.position.distance_to(_press_pos) <= DataManager.settings.tap_max_distance
			_end_single_gesture(is_tap, event.position)


func _handle_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position
	if _touches.size() >= 2:
		var span := _touch_span()
		if _pinch_distance > 0.0 and span > 0.0:
			zoom_requested.emit(span / _pinch_distance, _touch_center())
		_pinch_distance = span
		return
	if not _pressing:
		return
	if not _dragging and event.position.distance_to(_press_pos) > DataManager.settings.tap_max_distance:
		_dragging = true
		drag_started.emit(event.position)
	if _dragging:
		drag_updated.emit(event.relative)


func _handle_wheel(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	var step := DataManager.settings.camera_zoom_step
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_requested.emit(step, event.position)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_requested.emit(1.0 / step, event.position)


func _end_single_gesture(is_tap: bool, release_pos: Vector2 = Vector2.ZERO) -> void:
	if _dragging:
		drag_ended.emit()
	if is_tap:
		var now := Time.get_ticks_msec() / 1000.0
		var time_since_last := now - _last_tap_time
		var distance_to_last := release_pos.distance_to(_last_tap_pos)
		if time_since_last < DOUBLE_TAP_THRESHOLD and distance_to_last < DOUBLE_TAP_DISTANCE:
			double_tapped.emit(release_pos, _to_world(release_pos))
			_last_tap_time = -10.0
		else:
			tapped.emit(release_pos, _to_world(release_pos))
			_last_tap_pos = release_pos
			_last_tap_time = now
	_pressing = false
	_dragging = false


func _touch_span() -> float:
	var positions := _touches.values()
	return positions[0].distance_to(positions[1]) if positions.size() >= 2 else 0.0


func _touch_center() -> Vector2:
	var positions := _touches.values()
	return (positions[0] + positions[1]) / 2.0 if positions.size() >= 2 else Vector2.ZERO


## Screen → world by casting the active 3D camera's ray onto the ground
## plane (Y = 0). Returns Vector3.ZERO when no 3D camera is active
## (menus) or the ray is parallel to the ground.
func _to_world(screen_pos: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.ZERO
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.0001:
		return Vector3.ZERO
	var t := -origin.y / direction.y
	return origin + direction * t
