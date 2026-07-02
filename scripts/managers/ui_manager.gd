extends Node
## UIManager — screens, notifications and transitions (autoload).
##
## Owns a persistent CanvasLayer stack that survives scene changes:
##   layer 90  — screen stack (modal panels pushed with push_screen)
##   layer 95  — toast notifications
##   layer 100 — fade-to-black transition overlay
##
## Screens are PackedScenes whose root extends UIScreen; the stack gives
## every panel consistent open/close behaviour and back-navigation for
## free. The in-world HUD lives inside the game scene, not here.

enum NoteType { INFO, WARNING, SUCCESS }

const NOTE_COLORS := {
	NoteType.INFO: Color(0.85, 0.85, 0.85),
	NoteType.WARNING: Color(1.0, 0.42, 0.32),
	NoteType.SUCCESS: Color(0.78, 0.66, 0.29),
}
const NOTE_LIFETIME := 3.0
const MAX_NOTES := 4

var _screen_layer: CanvasLayer
var _note_layer: CanvasLayer
var _fade_layer: CanvasLayer
var _note_box: VBoxContainer
var _fade_rect: ColorRect
var _stack: Array[Control] = []


func _ready() -> void:
	_screen_layer = _make_layer(90)
	_note_layer = _make_layer(95)
	_fade_layer = _make_layer(100)

	_note_box = VBoxContainer.new()
	_note_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_note_box.offset_top = 70
	_note_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_note_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_note_box.add_theme_constant_override("separation", 6)
	_note_layer.add_child(_note_box)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade_rect)

	EventBus.notification_requested.connect(_on_notification)


# ── Screen stack ─────────────────────────────────────────────────────────

## Instance a UIScreen scene and show it on top of the stack.
func push_screen(scene: PackedScene) -> Control:
	var screen: Control = scene.instantiate()
	_screen_layer.add_child(screen)
	_stack.append(screen)
	if screen.has_method("open"):
		screen.open()
	return screen


## Close the topmost screen.
func pop_screen() -> void:
	if _stack.is_empty():
		return
	var screen: Control = _stack.pop_back()
	if is_instance_valid(screen):
		if screen.has_method("close"):
			screen.close()  # UIScreen frees itself after its close animation
		else:
			screen.queue_free()


func close_all_screens() -> void:
	while not _stack.is_empty():
		pop_screen()


func has_open_screen() -> bool:
	return not _stack.is_empty()


# ── Transitions ──────────────────────────────────────────────────────────

## Fade to black; await this before changing scenes.
func fade_out(duration: float = 0.35) -> void:
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP  # block input mid-transition
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 1.0, duration)
	await tween.finished


func fade_in(duration: float = 0.35) -> void:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 0.0, duration)
	await tween.finished
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


# ── Notifications ────────────────────────────────────────────────────────

func _on_notification(text: String, type: int) -> void:
	while _note_box.get_child_count() >= MAX_NOTES:
		_note_box.get_child(0).free()

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", NOTE_COLORS.get(type, Color.WHITE))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	_note_box.add_child(label)

	var tween := label.create_tween()
	tween.tween_interval(NOTE_LIFETIME)
	tween.tween_property(label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(label.queue_free)


# ── Internal ─────────────────────────────────────────────────────────────

func _make_layer(layer_index: int) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = layer_index
	add_child(layer)
	return layer
