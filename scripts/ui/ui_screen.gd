class_name UIScreen
extends Control
## Base class for every modal screen pushed via UIManager.push_screen().
##
## Provides: full-screen dim backdrop that closes on tap, a centered
## styled panel, and open/close fade animations. Subclasses put their
## content in `panel` (or override _build_content) and get consistent
## behaviour for free.

const ANIM_TIME := 0.15

## Set false for screens that must not be dismissed by tapping outside.
var close_on_backdrop_tap: bool = true
## Size of the centered panel; subclasses set before _ready runs
## (in _init) or leave the default.
var panel_size: Vector2 = Vector2(620, 480)

var backdrop: ColorRect
var panel: PanelContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	backdrop = ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.7)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.panel_style())
	panel.custom_minimum_size = panel_size
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	_build_content()


## Subclasses build their UI here; `panel` is ready to receive children.
func _build_content() -> void:
	pass


## Standard header row with title + close button; returns the content
## VBox below it for the subclass to fill.
func build_frame(title_text: String) -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UIStyle.BRASS_BRIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := UIStyle.make_button("✕", 16)
	close_btn.pressed.connect(func(): UIManager.pop_screen())
	header.add_child(close_btn)

	var rule := ColorRect.new()
	rule.color = UIStyle.BRASS
	rule.custom_minimum_size = Vector2(0, 2)
	root.add_child(rule)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)
	return content


# ── Lifecycle (called by UIManager) ──────────────────────────────────────

func open() -> void:
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, ANIM_TIME)


func close() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, ANIM_TIME)
	tween.tween_callback(queue_free)


func _on_backdrop_input(event: InputEvent) -> void:
	if close_on_backdrop_tap and event is InputEventMouseButton and event.pressed:
		UIManager.pop_screen()
