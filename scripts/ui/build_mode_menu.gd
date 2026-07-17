class_name BuildModeMenu
extends Control
## Build-mode bottom bar: category tabs + every BuildingPiece as a
## button, discovered from DataManager — dropping a new piece .tres in
## data/building_pieces/ adds it here with zero code.
##
## Lives in the HUD layer, hidden until EventBus.build_mode_changed.
## Selecting a piece arms the BuildModeController's ghost; the ✓ ⟳ ✕
## controls drive it (they mirror the desktop R/Enter/Esc keys).

var _tab_bar: HBoxContainer
var _piece_row: HBoxContainer
var _action_row: HBoxContainer
var _active_category := ""
var _piece_buttons: Dictionary = {}  # piece id -> Button
var _selected: BuildingPiece


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", UIStyle.panel_style())
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	_build_top_row(column)
	_build_piece_row(column)

	EventBus.build_mode_changed.connect(_on_build_mode_changed)
	EventBus.piece_selected.connect(_on_piece_selected)
	EventBus.resource_changed.connect(func(_i, _a, _c): _refresh_affordability())
	EventBus.piece_placed.connect(func(_e): _refresh_affordability())

	var categories := _categories()
	if not categories.is_empty():
		_show_category(categories[0])


func _build_top_row(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)

	var exit_btn := UIStyle.make_button("✕  EXIT BUILD", 15)
	exit_btn.pressed.connect(func(): BaseManager.exit_build_mode())
	row.add_child(exit_btn)

	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 6)
	row.add_child(_tab_bar)
	for category in _categories():
		var tab := UIStyle.make_button(category.capitalize(), 14)
		tab.pressed.connect(_show_category.bind(category))
		_tab_bar.add_child(tab)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# Ghost controls — visible only while a piece preview is armed.
	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 8)
	_action_row.visible = false
	row.add_child(_action_row)

	var place_btn := UIStyle.make_button("✓  PLACE", 15)
	place_btn.pressed.connect(func(): _controller().confirm())
	_action_row.add_child(place_btn)

	var rotate_btn := UIStyle.make_button("⟳", 15)
	rotate_btn.pressed.connect(func(): _controller().rotate_preview())
	_action_row.add_child(rotate_btn)

	var cancel_btn := UIStyle.make_button("✕", 15)
	cancel_btn.pressed.connect(func(): _controller().cancel())
	_action_row.add_child(cancel_btn)


func _build_piece_row(column: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 78)
	column.add_child(scroll)

	_piece_row = HBoxContainer.new()
	_piece_row.add_theme_constant_override("separation", 8)
	scroll.add_child(_piece_row)


func _show_category(category: String) -> void:
	_active_category = category
	_piece_buttons.clear()
	for child in _piece_row.get_children():
		_piece_row.remove_child(child)
		child.queue_free()
	for piece in DataManager.all_pieces():
		if piece.category != category:
			continue
		var button := UIStyle.make_button(
			"%s\n%s" % [piece.display_name, _cost_text(piece.cost)], 13)
		button.custom_minimum_size = Vector2(112, 64)
		button.pressed.connect(func(): EventBus.piece_selected.emit(piece))
		_piece_row.add_child(button)
		_piece_buttons[piece.id] = button
	_refresh_affordability()


func _refresh_affordability() -> void:
	for id in _piece_buttons:
		var piece := DataManager.get_piece(id)
		(_piece_buttons[id] as Button).disabled = \
			not ResourceManager.can_afford(piece.cost)


func _on_build_mode_changed(active: bool) -> void:
	visible = active


func _on_piece_selected(piece: BuildingPiece) -> void:
	_selected = piece
	_action_row.visible = piece != null


## Every category present in the data, in all_pieces() order.
func _categories() -> Array:
	var seen := []
	for piece in DataManager.all_pieces():
		if not seen.has(piece.category):
			seen.append(piece.category)
	return seen


func _cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"
	var parts: Array[String] = []
	for id in cost:
		var def := DataManager.get_resource_def(id)
		parts.append("%s%d" % [def.icon if def else id + ":", cost[id]])
	return " ".join(parts)


func _controller() -> BuildModeController:
	return get_tree().get_first_node_in_group("build_mode_controller")
