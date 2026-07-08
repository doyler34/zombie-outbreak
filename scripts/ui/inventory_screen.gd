class_name InventoryScreen
extends UIScreen
## The Commander's backpack — modal screen pushed via UIManager.
##
## Layout: backpack grid + hotbar row on the left, details pane on the
## right. Interaction is tap-to-select then tap-to-place (works the same
## with touch and mouse — no drag precision needed on a phone):
##   tap an item        → select it, details pane shows it
##   tap another slot   → move/merge/swap there (hotbar included)
##   tap it again       → deselect
## The details pane offers Use (usables on the hotbar), To Hotbar
## (quick-assign) and Drop. All rules live in InventoryManager — this
## screen never touches slot data directly.

const GRID_COLUMNS := 5

var _slot_buttons: Array[ItemSlotButton] = []
var _details: VBoxContainer
## Selected slot: {"area": String, "index": int}, empty when none.
var _selected: Dictionary = {}


func _init() -> void:
	panel_size = Vector2(700, 460)


func _build_content() -> void:
	var content := build_frame("🎒  INVENTORY")

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)

	# ── Left: backpack grid + hotbar row ─────────────────────────────
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)

	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	for i in InventoryManager.inventory_size():
		grid.add_child(_make_slot(InventoryManager.AREA_INVENTORY, i))

	var hotbar_title := Label.new()
	hotbar_title.text = "HOTBAR"
	hotbar_title.add_theme_font_size_override("font_size", 13)
	hotbar_title.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	left.add_child(hotbar_title)

	var hotbar_row := HBoxContainer.new()
	hotbar_row.add_theme_constant_override("separation", 6)
	left.add_child(hotbar_row)
	for i in InventoryManager.hotbar_size():
		hotbar_row.add_child(_make_slot(InventoryManager.AREA_HOTBAR, i))

	# ── Right: details pane ──────────────────────────────────────────
	var details_panel := PanelContainer.new()
	details_panel.add_theme_stylebox_override("panel", UIStyle.panel_style())
	details_panel.custom_minimum_size = Vector2(210, 0)
	columns.add_child(details_panel)

	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 8)
	details_panel.add_child(_details)

	EventBus.inventory_changed.connect(_refresh)
	EventBus.hotbar_changed.connect(_refresh)
	_refresh.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	# The same key that opened the backpack closes it again.
	if event.is_action_pressed("inventory"):
		UIManager.pop_screen()
		get_viewport().set_input_as_handled()


# ── Slots ────────────────────────────────────────────────────────────────

func _make_slot(area: String, index: int) -> ItemSlotButton:
	var btn := ItemSlotButton.new(area, index)
	btn.pressed.connect(func(): _on_slot_tapped(btn))
	_slot_buttons.append(btn)
	return btn


func _on_slot_tapped(btn: ItemSlotButton) -> void:
	var here := {"area": btn.area, "index": btn.index}
	if _selected.is_empty():
		if not InventoryManager.slot(btn.area, btn.index).is_empty():
			_selected = here
	elif _selected.area == here.area and _selected.index == here.index:
		_selected = {}
	else:
		InventoryManager.move(_selected.area, _selected.index, here.area, here.index)
		_selected = {}
	_refresh()


func _refresh() -> void:
	# Selection can point at a slot the move just emptied.
	if not _selected.is_empty() \
			and InventoryManager.slot(_selected.area, _selected.index).is_empty():
		_selected = {}
	for btn in _slot_buttons:
		btn.refresh()
		btn.set_selected(not _selected.is_empty()
			and btn.area == _selected.area and btn.index == _selected.index)
	_rebuild_details()


# ── Details pane ─────────────────────────────────────────────────────────

func _rebuild_details() -> void:
	for child in _details.get_children():
		_details.remove_child(child)
		child.queue_free()

	if _selected.is_empty():
		var hint := Label.new()
		hint.text = "Tap an item to inspect it.\n\nTap a second slot to move\nit there."
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		_details.add_child(hint)
		return

	var slot := InventoryManager.slot(_selected.area, _selected.index)
	var def := DataManager.get_item(slot.get("id", ""))
	if def == null:
		return

	var icon := Label.new()
	icon.text = def.icon
	icon.add_theme_font_size_override("font_size", 40)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details.add_child(icon)

	var title := Label.new()
	title.text = def.display_name
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", UIStyle.BRASS_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_child(title)

	var meta := Label.new()
	meta.text = "%s   ×%d" % [def.type_name(), int(slot["count"])]
	meta.add_theme_font_size_override("font_size", 13)
	meta.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details.add_child(meta)

	if def.description != "":
		var desc := Label.new()
		desc.text = def.description
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_color_override("font_color", UIStyle.TEXT_WARM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_details.add_child(desc)

	# ── Actions ──────────────────────────────────────────────────────
	if def.is_usable() and _selected.area == InventoryManager.AREA_HOTBAR:
		var use_btn := UIStyle.make_button("Use", 14)
		var idx: int = _selected.index
		use_btn.pressed.connect(func():
			InventoryManager.use_hotbar(idx)
			_refresh())
		_details.add_child(use_btn)

	if _selected.area == InventoryManager.AREA_INVENTORY and def.hotbar_allowed():
		var assign_btn := UIStyle.make_button("To Hotbar", 14)
		assign_btn.pressed.connect(_assign_to_hotbar)
		_details.add_child(assign_btn)

	var drop_btn := UIStyle.make_button("Drop", 14)
	drop_btn.add_theme_color_override("font_color", UIStyle.DANGER)
	drop_btn.pressed.connect(func():
		InventoryManager.drop(_selected.area, _selected.index)
		_selected = {}
		_refresh())
	_details.add_child(drop_btn)


## Quick-assign the selected backpack item into the first free hotbar
## slot (or merge into a matching stack — move() handles that).
func _assign_to_hotbar() -> void:
	var src_id: String = InventoryManager.slot(_selected.area, _selected.index).get("id", "")
	for i in InventoryManager.hotbar_size():
		var dst := InventoryManager.slot(InventoryManager.AREA_HOTBAR, i)
		if dst.is_empty() or dst.get("id") == src_id:
			InventoryManager.move(_selected.area, _selected.index,
				InventoryManager.AREA_HOTBAR, i)
			_selected = {}
			_refresh()
			return
	EventBus.notify("Hotbar is full.", 1)
