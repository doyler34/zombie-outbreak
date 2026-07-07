class_name VirtualJoystick
extends Control
## Fixed on-screen movement joystick (bottom-left thumb zone).
##
## Drawn with _draw (no textures, same as the rest of the UI) and sized
## from GameSettings. Because it's a Control that accepts its events,
## touches on it never reach InputManager — the camera won't pan while
## the player is steering. Consumers poll [member direction]; the
## Commander does so every physics frame.
##
## Works for both real touches (Android) and the mouse (desktop, via the
## project's emulate_touch_from_mouse) by handling the touch events and
## tracking which finger owns the knob.

const MARGIN := 24.0
## Control extent relative to the base radius — padding so the knob
## never draws outside the control's rect.
const EXTENT_FACTOR := 2.8

## Normalized screen-space movement vector (x right, y down), length
## 0..1. Vector2.ZERO while idle or inside the dead zone.
var direction := Vector2.ZERO

var _radius: float
var _dead_zone: float
var _touch_index := -1
var _knob_offset := Vector2.ZERO


func _ready() -> void:
	_radius = DataManager.settings.joystick_radius
	_dead_zone = DataManager.settings.joystick_dead_zone
	mouse_filter = Control.MOUSE_FILTER_STOP

	var extent := _radius * EXTENT_FACTOR
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = MARGIN
	offset_right = MARGIN + extent
	offset_top = -(MARGIN + extent)
	offset_bottom = -MARGIN


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_update_knob(event.position)
		elif not event.pressed and event.index == _touch_index:
			_reset()
		accept_event()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_knob(event.position)
		accept_event()


## Losing visibility (scene change, modal covering the HUD) must not
## leave a phantom deflection driving the Commander.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_reset()


# ── Internal ─────────────────────────────────────────────────────────────

func _update_knob(local_pos: Vector2) -> void:
	var offset := local_pos - size / 2.0
	_knob_offset = offset.limit_length(_radius)
	var deflection := _knob_offset / _radius
	direction = Vector2.ZERO if deflection.length() < _dead_zone else deflection
	queue_redraw()


func _reset() -> void:
	_touch_index = -1
	_knob_offset = Vector2.ZERO
	direction = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var active := _touch_index != -1
	# Base ring.
	draw_circle(center, _radius, Color(0.05, 0.05, 0.1, 0.45 if active else 0.3))
	draw_arc(center, _radius, 0, TAU, 48,
		UIStyle.BRASS if active else Color(UIStyle.BRASS, 0.5), 2.0, true)
	# Knob.
	draw_circle(center + _knob_offset, _radius * 0.42,
		Color(UIStyle.BRASS_BRIGHT, 0.85 if active else 0.55))
