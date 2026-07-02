class_name HUD
extends Control
## In-game HUD: resource bar, clock, build/menu buttons, placement
## confirm/cancel, and the selected-building panel.
##
## Everything is generated from data — the resource row is built from
## whatever ResourceDefinitions exist, so adding a resource .tres file
## automatically adds its HUD counter. The HUD lives inside the world
## scene (it belongs to gameplay); modal screens go through UIManager.

const BUILD_MENU_SCENE := preload("res://scenes/ui/build_menu.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")

var _resource_labels: Dictionary = {}  # id -> Label
var _day_label: Label
var _population_label: Label
var _placement_bar: HBoxContainer
var _action_bar: HBoxContainer
var _info_panel: PanelContainer
var _info_content: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_top_bar()
	_build_action_bar()
	_build_placement_bar()
	_build_info_panel()

	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.day_passed.connect(func(_d): _refresh_clock())
	EventBus.population_changed.connect(_on_population_changed)
	EventBus.building_placement_started.connect(func(_def): _set_placement_mode(true))
	EventBus.building_placement_ended.connect(func(_ok): _set_placement_mode(false))
	EventBus.building_selected.connect(_on_building_selected)
	EventBus.building_deselected.connect(func(): _info_panel.visible = false)
	EventBus.building_upgraded.connect(_on_building_upgraded)
	# A save load happens after the HUD's first refresh — refresh again.
	EventBus.load_completed.connect(func(_slot): _refresh_all())

	_refresh_all()


# ── Construction ─────────────────────────────────────────────────────────

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.05, 0.9)
	style.border_color = UIStyle.BRASS
	style.border_width_bottom = 2
	style.set_content_margin_all(8)
	bar.add_theme_stylebox_override("panel", style)
	add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	bar.add_child(row)

	_day_label = _make_stat_label(UIStyle.BRASS_BRIGHT)
	row.add_child(_day_label)

	for def in DataManager.all_resource_defs():
		var label := _make_stat_label(def.icon_color)
		row.add_child(label)
		_resource_labels[def.id] = label

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_population_label = _make_stat_label(UIStyle.TEXT_WARM)
	row.add_child(_population_label)


func _make_stat_label(color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	return label


func _build_action_bar() -> void:
	_action_bar = HBoxContainer.new()
	_action_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_action_bar.offset_bottom = -12
	_action_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_action_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_action_bar.add_theme_constant_override("separation", 14)
	add_child(_action_bar)

	var build_btn := UIStyle.make_button("⚙  BUILD")
	build_btn.pressed.connect(func(): UIManager.push_screen(BUILD_MENU_SCENE))
	_action_bar.add_child(build_btn)

	var menu_btn := UIStyle.make_button("☰  MENU")
	menu_btn.pressed.connect(func(): UIManager.push_screen(PAUSE_MENU_SCENE))
	_action_bar.add_child(menu_btn)


func _build_placement_bar() -> void:
	_placement_bar = HBoxContainer.new()
	_placement_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_placement_bar.offset_bottom = -12
	_placement_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_placement_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_placement_bar.add_theme_constant_override("separation", 14)
	_placement_bar.visible = false
	add_child(_placement_bar)

	var confirm := UIStyle.make_button("✓  PLACE", 20)
	confirm.pressed.connect(func(): _placer().confirm())
	_placement_bar.add_child(confirm)

	var rotate := UIStyle.make_button("⟳  ROTATE", 20)
	rotate.pressed.connect(func(): _placer().rotate_ghost())
	_placement_bar.add_child(rotate)

	var cancel := UIStyle.make_button("✕  CANCEL", 20)
	cancel.pressed.connect(func(): _placer().cancel())
	_placement_bar.add_child(cancel)


func _build_info_panel() -> void:
	_info_panel = PanelContainer.new()
	_info_panel.add_theme_stylebox_override("panel", UIStyle.panel_style())
	_info_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_info_panel.offset_left = 12
	_info_panel.offset_bottom = -12
	_info_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info_panel.custom_minimum_size = Vector2(280, 0)
	_info_panel.visible = false
	add_child(_info_panel)

	_info_content = VBoxContainer.new()
	_info_content.add_theme_constant_override("separation", 6)
	_info_panel.add_child(_info_content)


# ── Refresh ──────────────────────────────────────────────────────────────

func _refresh_all() -> void:
	for id in _resource_labels:
		_update_resource_label(id, ResourceManager.get_amount(id))
	_refresh_clock()
	_on_population_changed(SurvivorManager.count(), SurvivorManager.population_cap())


func _on_resource_changed(id: String, amount: int, _change: int) -> void:
	_update_resource_label(id, amount)


func _update_resource_label(id: String, amount: int) -> void:
	var label: Label = _resource_labels.get(id)
	if label:
		label.text = "%s %d" % [DataManager.get_resource_def(id).icon, amount]


func _refresh_clock() -> void:
	var phase := "🌙" if TimeManager.is_night else "☀"
	_day_label.text = "%s Day %d" % [phase, TimeManager.current_day]


func _on_population_changed(count: int, cap: int) -> void:
	_population_label.text = "👥 %d / %d" % [count, cap]


func _set_placement_mode(placing: bool) -> void:
	_placement_bar.visible = placing
	_action_bar.visible = not placing


func _on_building_selected(entity: BuildingEntity) -> void:
	for child in _info_content.get_children():
		child.free()

	var def: BuildingDefinition = entity.definition

	var title := Label.new()
	title.text = "%s  —  Lv %d" % [def.display_name, entity.level]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UIStyle.BRASS_BRIGHT)
	_info_content.add_child(title)

	var status := Label.new()
	status.text = "Operational" if entity.is_operational() else "Under construction…"
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_info_content.add_child(status)

	if entity.is_operational() and entity.level < def.max_level:
		var cost := def.cost_for_level(entity.level + 1)
		var upgrade_btn := UIStyle.make_button(
			"⬆ Upgrade  (%s)" % _cost_text(cost), 15)
		upgrade_btn.disabled = not ResourceManager.can_afford(cost)
		upgrade_btn.pressed.connect(func(): BuildingManager.upgrade(entity))
		_info_content.add_child(upgrade_btn)

	_info_panel.visible = true


func _on_building_upgraded(entity: BuildingEntity, _new_level: int) -> void:
	# Refresh the info panel if the upgraded building is the one shown.
	if entity == BuildingManager.selected:
		_on_building_selected(entity)


func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for id in cost:
		var def := DataManager.get_resource_def(id)
		parts.append("%s%d" % [def.icon if def else id + ":", cost[id]])
	return "  ".join(parts)


func _placer() -> BuildingPlacer:
	return get_tree().get_first_node_in_group("building_placer")
