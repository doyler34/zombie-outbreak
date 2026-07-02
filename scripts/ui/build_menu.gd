extends UIScreen
## Build menu — lists every unlocked BuildingDefinition with its cost.
##
## Fully data-driven: rows come from DataManager.all_buildings(), so new
## building .tres files appear here automatically. Choosing one starts
## ghost placement (EventBus.building_placement_started) and closes the
## menu; the HUD then shows confirm/cancel.


func _init() -> void:
	panel_size = Vector2(680, 520)


func _build_content() -> void:
	var content := build_frame("⚙  CONSTRUCTIONS")

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	for def in DataManager.all_buildings():
		if not def.unlocked_from_start:
			continue  # future research system unlocks these
		list.add_child(_make_row(def))


func _make_row(def: BuildingDefinition) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var icon := TextureRect.new()
	icon.texture = def.texture
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_box)

	var name_label := Label.new()
	name_label.text = def.display_name
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", UIStyle.TEXT_WARM)
	text_box.add_child(name_label)

	var cost_label := Label.new()
	cost_label.text = _cost_text(def.cost_for_level(1))
	cost_label.add_theme_font_size_override("font_size", 13)
	cost_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	text_box.add_child(cost_label)

	var build_btn := UIStyle.make_button("Build", 15)
	build_btn.custom_minimum_size = Vector2(120, 48)
	build_btn.disabled = not ResourceManager.can_afford(def.cost_for_level(1))
	build_btn.pressed.connect(func(): _start_placement(def))
	row.add_child(build_btn)

	return row


func _start_placement(def: BuildingDefinition) -> void:
	UIManager.pop_screen()
	EventBus.building_placement_started.emit(def)


func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for id in cost:
		var def := DataManager.get_resource_def(id)
		parts.append("%s %d" % [def.icon if def else id, cost[id]])
	return "   ".join(parts)
