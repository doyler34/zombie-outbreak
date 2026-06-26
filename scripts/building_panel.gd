# building_panel.gd - Building management UI panel
extends Control

@onready var panel: Panel = $Panel
@onready var building_list: VBoxContainer = $Panel/ScrollContainer/BuildingList
@onready var close_btn: Button = $Panel/CloseBtn
var buildings_data: Array = []

func _ready() -> void:
	visible = false
	close_btn.pressed.connect(_on_close)
	_load_building_data()
	_populate_list()

func show_panel() -> void:
	_populate_list()
	visible = true
	close_btn.grab_focus()

func _on_close() -> void:
	visible = false

func _load_building_data() -> void:
	var file = FileAccess.open("res://data/buildings.json", FileAccess.READ)
	if file == null:
		return
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) == OK:
		buildings_data = json.get_data().buildings

func _populate_list() -> void:
	# Clear existing entries
	for child in building_list.get_children():
		child.queue_free()

	for bld in buildings_data:
		var row = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 50)
		row.add_theme_constant_override("separation", 10)

		# Building name + current level
		var current_level = GameState.buildings.get(bld.id, 0)
		var name_label = Label.new()
		name_label.text = "%s (Lv %d)" % [bld.name, current_level]
		name_label.custom_minimum_size = Vector2(200, 0)
		name_label.label_settings = LabelSettings.new()
		name_label.label_settings.font_size = 16
		name_label.label_settings.font_color = Color(1, 1, 1, 1)
		row.add_child(name_label)

		# Build/upgrade button
		var btn = Button.new()
		if current_level == 0:
			btn.text = "Build"
		elif current_level < bld.max_level:
			btn.text = "Upgrade → Lv%d" % (current_level + 1)
		else:
			btn.text = "MAX"
			btn.disabled = true

		btn.custom_minimum_size = Vector2(150, 45)
		btn.theme_override_font_sizes = {font_size = 14}
		btn.pressed.connect(_on_build_pressed.bind(bld, current_level))
		row.add_child(btn)

		# Cost label
		var cost_label = Label.new()
		var costs = _get_cost_for_level(bld, current_level + 1)
		var cost_text = _format_costs(costs)
		cost_label.text = cost_text
		cost_label.custom_minimum_size = Vector2(180, 0)
		cost_label.label_settings = LabelSettings.new()
		cost_label.label_settings.font_size = 12
		cost_label.label_settings.font_color = Color(0.7, 0.7, 0.7, 1)
		row.add_child(cost_label)

		building_list.add_child(row)

func _get_cost_for_level(bld: Dictionary, target_level: int) -> Dictionary:
	var costs = bld.base_cost.duplicate()
	for i in range(target_level - 1):
		for key in bld.cost_per_level:
			costs[key] = costs.get(key, 0) + bld.cost_per_level[key]
	return costs

func _format_costs(costs: Dictionary) -> String:
	var parts = []
	for key in costs:
		if costs[key] > 0:
			parts.append("%s: %d" % [key, costs[key]])
	return " | ".join(parts)

func _on_build_pressed(bld: Dictionary, current_level: int) -> void:
	var target_level = current_level + 1
	if target_level > bld.max_level:
		return

	var costs = _get_cost_for_level(bld, target_level)

	if ResourceManager.pay(costs):
		GameState.buildings[bld.id] = target_level
		GameState._recalculate_base_stats()
		EventBus.building_built.emit(bld.id, target_level)
		EventBus.notification.emit("%s built to level %d!" % [bld.name, target_level], "#00FF00")
		_populate_list()
	else:
		EventBus.notification.emit("Not enough resources for %s!" % bld.name, "#FF4444")
