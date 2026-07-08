class_name Hotbar
extends HBoxContainer
## Quick-use bar above the HUD's action buttons (bottom-center).
##
## A row of ItemSlotButtons over InventoryManager's hotbar area. Tap a
## slot (or press 1–5 on desktop) to select it: weapons/tools equip,
## usables arm on the first press and consume one on the second — all of
## that logic lives in InventoryManager.select_hotbar(); this Control
## only draws state and forwards input.

## Clearance above the BUILD/BAG/MAP/MENU action bar.
const LIFT := 68.0
## hotbar_1..hotbar_5 are the only bound keys; extra slots stay tap-only.
const MAX_KEY_SLOTS := 5

var _buttons: Array[ItemSlotButton] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -LIFT
	add_theme_constant_override("separation", 6)

	for i in InventoryManager.hotbar_size():
		var btn := ItemSlotButton.new(InventoryManager.AREA_HOTBAR, i)
		btn.pressed.connect(func(): InventoryManager.select_hotbar(btn.index))
		add_child(btn)
		_buttons.append(btn)

	EventBus.hotbar_changed.connect(_refresh)
	EventBus.hotbar_selection_changed.connect(func(_i, _item): _refresh())
	EventBus.load_completed.connect(func(_slot): _refresh())
	_refresh.call_deferred()  # buttons build their labels in their own _ready


func _unhandled_input(event: InputEvent) -> void:
	if UIManager.has_open_screen():
		return
	for i in mini(_buttons.size(), MAX_KEY_SLOTS):
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			InventoryManager.select_hotbar(i)
			get_viewport().set_input_as_handled()
			return


func _refresh() -> void:
	var active := InventoryManager.active_hotbar_index()
	for btn in _buttons:
		btn.refresh()
		btn.set_selected(btn.index == active)
