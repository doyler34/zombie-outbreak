class_name InteractButton
extends Button
## Mobile interact button + prompt display (bottom-right thumb zone).
##
## Hidden until the InteractionController reports a target in range,
## then shows the target's prompt ("✋ Open Gate"). Desktop players see
## an extra [E] hint since the interact key triggers the same action.
## Sits above the selection info panel's corner spot so both can show
## at once.

## Lift above the bottom-right selection info panel.
const LIFT := 170.0
const MARGIN := 18.0

var _keyboard_hint: bool = false


func _ready() -> void:
	UIStyle.style_button(self, 19)
	custom_minimum_size = Vector2(190, 62)
	visible = false
	_keyboard_hint = not DisplayServer.is_touchscreen_available()
	set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	offset_top -= LIFT
	offset_bottom -= LIFT


## Wire to the world's InteractionController (called by GameWorld).
func bind(controller: InteractionController) -> void:
	controller.target_changed.connect(_on_target_changed)
	pressed.connect(func(): controller.interact())


func _on_target_changed(target: Interactable) -> void:
	visible = target != null
	if target != null:
		text = "✋  %s%s" % [target.prompt, "   [E]" if _keyboard_hint else ""]
