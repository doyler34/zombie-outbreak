class_name CraftingScreen
extends UIScreen
## The Commander's crafting menu — modal screen pushed via UIManager.
##
## Recipe list on the left, details on the right: result item, an
## ingredient checklist colored by what the inventory actually holds,
## and a CRAFT button that is disabled (with the shortfall spelled out)
## until everything is in the bag. All rules live in CraftingManager —
## this screen only draws state and forwards taps, and redraws itself
## on EventBus.inventory_changed so counts stay live while crafting.

var _recipes: Array[RecipeDefinition] = []
var _selected: RecipeDefinition = null
var _list: VBoxContainer
var _details: VBoxContainer
var _recipe_buttons: Dictionary = {}  # recipe id -> Button


func _init() -> void:
	panel_size = Vector2(700, 460)


func _build_content() -> void:
	var content := build_frame("🔨  CRAFTING")

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)

	# ── Left: recipe list ────────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(250, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	# ── Right: details pane ──────────────────────────────────────────
	var details_panel := PanelContainer.new()
	details_panel.add_theme_stylebox_override("panel", UIStyle.panel_style())
	details_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(details_panel)

	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 8)
	details_panel.add_child(_details)

	_recipes = DataManager.all_recipes()
	_build_recipe_list()
	if not _recipes.is_empty():
		_selected = _recipes[0]
	_refresh()

	EventBus.inventory_changed.connect(_refresh)
	EventBus.hotbar_changed.connect(_refresh)


func _unhandled_input(event: InputEvent) -> void:
	# The same key that opened the menu closes it again.
	if event.is_action_pressed("crafting"):
		UIManager.pop_screen()
		get_viewport().set_input_as_handled()


# ── Recipe list ──────────────────────────────────────────────────────────

func _build_recipe_list() -> void:
	for recipe in _recipes:
		var item := recipe.result_definition()
		var label := "%s  %s" % [item.icon, item.display_name] if item != null else recipe.id
		var btn := UIStyle.make_button(label, 15)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func():
			_selected = recipe
			_refresh())
		_list.add_child(btn)
		_recipe_buttons[recipe.id] = btn


func _refresh() -> void:
	for recipe in _recipes:
		var btn: Button = _recipe_buttons.get(recipe.id)
		if btn == null:
			continue
		var craftable := CraftingManager.can_craft(recipe)
		btn.add_theme_color_override("font_color",
			UIStyle.TEXT_WARM if craftable else UIStyle.TEXT_DIM)
		# The selected row gets the bright brass ring.
		btn.add_theme_stylebox_override("normal", UIStyle.button_style(
			UIStyle.BUTTON_BG.lightened(0.10) if recipe == _selected else UIStyle.BUTTON_BG,
			UIStyle.BRASS_BRIGHT if recipe == _selected else UIStyle.BRASS))
	_rebuild_details()


# ── Details pane ─────────────────────────────────────────────────────────

func _rebuild_details() -> void:
	for child in _details.get_children():
		_details.remove_child(child)
		child.queue_free()
	if _selected == null:
		return
	var item := _selected.result_definition()
	if item == null:
		return

	var icon := Label.new()
	icon.text = item.icon
	icon.add_theme_font_size_override("font_size", 40)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details.add_child(icon)

	var title := Label.new()
	title.text = item.display_name \
		+ ("  ×%d" % _selected.result_count if _selected.result_count > 1 else "")
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", UIStyle.BRASS_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details.add_child(title)

	var meta := Label.new()
	meta.text = item.type_name()
	meta.add_theme_font_size_override("font_size", 13)
	meta.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details.add_child(meta)

	if item.description != "":
		var desc := Label.new()
		desc.text = item.description
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_color_override("font_color", UIStyle.TEXT_WARM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_details.add_child(desc)

	var need_title := Label.new()
	need_title.text = "REQUIRES"
	need_title.add_theme_font_size_override("font_size", 12)
	need_title.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_details.add_child(need_title)

	# Ingredient checklist: green when covered, red with the shortfall.
	for ingredient_id in _selected.ingredients:
		var need := int(_selected.ingredients[ingredient_id])
		var have := InventoryManager.total_count(ingredient_id)
		var def := DataManager.get_item(ingredient_id)
		var row := Label.new()
		var display := def.display_name if def != null else String(ingredient_id)
		var icon_text: String = def.icon if def != null else ""
		if have >= need:
			row.text = "✔ %s %s   %d / %d" % [icon_text, display, have, need]
			row.add_theme_color_override("font_color", Color(0.55, 0.85, 0.45))
		else:
			row.text = "✘ %s %s   %d / %d  (need %d more)" % [
				icon_text, display, have, need, need - have]
			row.add_theme_color_override("font_color", Color(0.9, 0.45, 0.35))
		row.add_theme_font_size_override("font_size", 14)
		_details.add_child(row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.add_child(spacer)

	var craft_btn := UIStyle.make_button("🔨  CRAFT", 17)
	craft_btn.disabled = not CraftingManager.can_craft(_selected)
	craft_btn.pressed.connect(func(): CraftingManager.craft(_selected))
	_details.add_child(craft_btn)
