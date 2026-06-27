# base_scene.gd - Main game scene controller (updated with panels)
extends Node2D

@onready var day_night_overlay: ColorRect = $DayNightOverlay
@onready var ui_layer: Control = $UILayer
@onready var top_bar: HBoxContainer = $UILayer/TopBar
@onready var bottom_bar: HBoxContainer = $UILayer/BottomBar
@onready var day_label: Label = $UILayer/TopBar/DayLabel
@onready var food_label: Label = $UILayer/TopBar/FoodLabel
@onready var water_label: Label = $UILayer/TopBar/WaterLabel
@onready var wood_label: Label = $UILayer/TopBar/WoodLabel
@onready var metal_label: Label = $UILayer/TopBar/MetalLabel
@onready var med_label: Label = $UILayer/TopBar/MedicineLabel
@onready var ammo_label: Label = $UILayer/TopBar/AmmoLabel
@onready var pop_label: Label = $UILayer/TopBar/PopLabel
@onready var notification_label: Label = $UILayer/NotificationLabel
@onready var notification_timer: Timer = $NotificationTimer

@onready var buildings_btn: Button = $UILayer/BottomBar/BuildingsBtn
@onready var survivors_btn: Button = $UILayer/BottomBar/SurvivorsBtn
@onready var mission_btn: Button = $UILayer/BottomBar/MissionBtn
@onready var menu_btn: Button = $UILayer/BottomBar/MenuBtn

# Panel references (built in _ready)
var building_panel: Control
var building_list: VBoxContainer
var buildings_data: Array = []
var survivor_panel: Control
var mission_panel: Control
var menu_panel: Control

# Day/night
var day_night_timer: float = 0.0
const FULL_CYCLE := 120.0

func _ready() -> void:
	# Build all panels in code (no tscn loading — avoids export path issues)
	_create_building_panel()

	# Survivor panel placeholder
	survivor_panel = Control.new()
	survivor_panel.visible = false
	survivor_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(survivor_panel)

	# Mission panel placeholder
	mission_panel = Control.new()
	mission_panel.visible = false
	mission_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(mission_panel)

	_create_menu_panel()

	# Connect signals
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.day_passed.connect(_on_day_passed)
	EventBus.survivor_added.connect(_on_population_changed)
	EventBus.survivor_died.connect(_on_population_changed)
	EventBus.notification.connect(_show_notification)
	EventBus.game_over.connect(_on_game_over)

	# Building panel button
	buildings_btn.pressed.connect(func(): _show_building_panel())
	if survivors_btn:
		survivors_btn.pressed.connect(func(): survivor_panel.visible = true)
	if mission_btn:
		mission_btn.pressed.connect(func(): mission_panel.visible = true)
	if menu_btn:
		menu_btn.pressed.connect(func(): menu_panel.visible = true)

	notification_timer.timeout.connect(_on_notification_timeout)

	# Initialize UI
	_refresh_resource_display()
	_refresh_day_display()

	day_night_timer = GameState.day_timer
	_adjust_day_night_overlay()

## ---- BUILDING PANEL (fully code-built, no .tscn dependency) ----

func _create_building_panel() -> void:
	# Load building data
	var file = FileAccess.open("res://data/buildings.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			buildings_data = json.get_data().buildings
		file.close()

	# Root control (full screen, hidden by default)
	building_panel = Control.new()
	building_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	building_panel.visible = false
	building_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Dimming background
	var dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	building_panel.add_child(dim)

	# Panel container (centered, 640x760)
	var panel_bg = Panel.new()
	panel_bg.set_anchors_preset(Control.PRESET_CENTER)
	panel_bg.offset_left = -320
	panel_bg.offset_top = -380
	panel_bg.offset_right = 320
	panel_bg.offset_bottom = 380
	building_panel.add_child(panel_bg)

	# Title
	var title = Label.new()
	title.layout_mode = 1
	title.anchor_right = 1.0
	title.offset_bottom = 45
	title.text = "  BUILDINGS"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
	panel_bg.add_child(title)

	# Close button
	var close = Button.new()
	close.layout_mode = 1
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.offset_left = -55
	close.offset_bottom = 45
	close.text = "✕"
	close.add_theme_font_size_override("font_size", 22)
	close.custom_minimum_size = Vector2(55, 45)
	close.pressed.connect(func(): building_panel.visible = false)
	panel_bg.add_child(close)

	# Scroll container for building list
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 50
	scroll.offset_bottom = -10
	panel_bg.add_child(scroll)

	# Building list VBox
	building_list = VBoxContainer.new()
	building_list.layout_mode = 2
	building_list.add_theme_constant_override("separation", 10)
	scroll.add_child(building_list)

	ui_layer.add_child(building_panel)

func _show_building_panel() -> void:
	_populate_building_list()
	building_panel.visible = true

func _populate_building_list() -> void:
	# Clear
	for child in building_list.get_children():
		child.queue_free()

	for bld in buildings_data:
		var row = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 55)
		row.add_theme_constant_override("separation", 10)

		var current_level = GameState.buildings.get(bld.id, 0)
		var is_placed = GameState.buildings.has(bld.id)
		var is_broken = is_placed and current_level == 0

		# Name label
		var name_label = Label.new()
		if is_broken:
			name_label.text = "🏚️ %s (Broken)" % bld.name
		else:
			name_label.text = "%s (Lv %d)" % [bld.name, current_level]
		name_label.custom_minimum_size = Vector2(170, 0)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 17)
		name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		row.add_child(name_label)

		# Build/repair/upgrade button
		var btn = Button.new()
		if is_broken:
			btn.text = "Repair 🔧"
		elif not is_placed:
			btn.text = "Build"
		elif current_level < bld.max_level:
			btn.text = "Upgrade → Lv%d" % (current_level + 1)
		else:
			btn.text = "MAX"
			btn.disabled = true

		btn.custom_minimum_size = Vector2(160, 45)
		btn.add_theme_font_size_override("font_size", 16)
		var bld_ref = bld
		var lvl = current_level
		btn.pressed.connect(func(): _do_build(bld_ref, lvl))
		row.add_child(btn)

		# Cost label
		var costs = _get_cost_for_level(bld, current_level + 1)
		var cost_parts = []
		for key in costs:
			if costs[key] > 0:
				cost_parts.append("%s: %d" % [key, costs[key]])
		var cost_text = " | ".join(cost_parts)

		var cost_label = Label.new()
		cost_label.text = cost_text
		cost_label.custom_minimum_size = Vector2(150, 0)
		cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cost_label.add_theme_font_size_override("font_size", 14)
		cost_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
		row.add_child(cost_label)

		building_list.add_child(row)

func _get_cost_for_level(bld: Dictionary, target_level: int) -> Dictionary:
	var costs = bld.base_cost.duplicate()
	for i in range(target_level - 1):
		for key in bld.cost_per_level:
			costs[key] = costs.get(key, 0) + bld.cost_per_level[key]
	return costs

func _do_build(bld: Dictionary, current_level: int) -> void:
	var target_level = current_level + 1
	if target_level > bld.max_level:
		return

	var costs = _get_cost_for_level(bld, target_level)
	if ResourceManager.pay(costs):
		GameState.buildings[bld.id] = target_level
		GameState._recalculate_base_stats()
		EventBus.building_built.emit(bld.id, target_level)
		if current_level == 0:
			_show_notification("%s repaired! Your base grows stronger." % bld.name, "#00FF00")
		else:
			_show_notification("%s upgraded to level %d!" % [bld.name, target_level], "#00FF00")
		_populate_building_list()
	else:
		_show_notification("Not enough resources for %s!" % bld.name, "#FF4444")

## ---- MENU PANEL ----

func _create_menu_panel() -> void:
	menu_panel = Control.new()
	menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_panel.visible = false

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.7)
	menu_panel.add_child(bg)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -100
	vbox.offset_top = -60
	vbox.offset_right = 100
	vbox.offset_bottom = 60
	vbox.add_theme_constant_override("separation", 15)
	menu_panel.add_child(vbox)

	var save_btn = Button.new()
	save_btn.text = "💾 Save Game"
	save_btn.custom_minimum_size = Vector2(200, 50)
	save_btn.pressed.connect(func():
		GameState.save_game()
		_show_notification("Game saved!", "#00FF00")
	)
	vbox.add_child(save_btn)

	var menu_btn2 = Button.new()
	menu_btn2.text = "🏠 Main Menu"
	menu_btn2.custom_minimum_size = Vector2(200, 50)
	menu_btn2.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	vbox.add_child(menu_btn2)

	var close_btn = Button.new()
	close_btn.text = "✕ Close"
	close_btn.custom_minimum_size = Vector2(200, 50)
	close_btn.pressed.connect(func(): menu_panel.visible = false)
	vbox.add_child(close_btn)

	ui_layer.add_child(menu_panel)

## ---- GAME LOGIC ----

func _process(delta: float) -> void:
	day_night_timer += delta
	if day_night_timer >= FULL_CYCLE:
		day_night_timer -= FULL_CYCLE
		_advance_day()

	_adjust_day_night_overlay()
	GameState.day_timer = day_night_timer

func _advance_day() -> void:
	GameState.current_day += 1
	GameState.is_night = false

	GameState.process_daily_production()
	GameState.process_survivor_needs()
	_check_zombie_attack()
	GameState.save_game()

	EventBus.day_passed.emit(GameState.current_day)
	_refresh_day_display()

func _adjust_day_night_overlay() -> void:
	var fraction = day_night_timer / FULL_CYCLE
	var alpha: float

	if fraction < 0.55:
		var day_fraction = fraction / 0.55
		if day_fraction < 0.1:
			alpha = lerpf(0.3, 0.0, day_fraction / 0.1)
		elif day_fraction > 0.9:
			alpha = lerpf(0.0, 0.3, (day_fraction - 0.9) / 0.1)
		else:
			alpha = 0.0
		GameState.is_night = false
	else:
		var night_fraction = (fraction - 0.55) / 0.45
		alpha = lerpf(0.3, 0.55, night_fraction)
		GameState.is_night = true

	day_night_overlay.color = Color(0.0, 0.0, 0.1, alpha)

func _check_zombie_attack() -> void:
	var zombies_data = _load_json("res://data/zombies.json")
	if zombies_data == null:
		return

	var chance = zombies_data.attack_triggers.daily_chance + GameState.noise_level
	if randf() < chance:
		var horde_key = "small"
		if GameState.current_day > 7:
			horde_key = "medium"
		if GameState.current_day > 14:
			horde_key = "large"

		var horde = zombies_data.horde_sizes[horde_key]
		var size = randi_range(horde.min, horde.max)
		_trigger_zombie_attack(horde_key, size)

func _trigger_zombie_attack(_size_key: String, size: int) -> void:
	EventBus.zombie_attack_started.emit(size)

	var defense = GameState.base_defense
	var zombies_killed = 0
	var survivors_lost = 0

	for i in range(size):
		if randi() % 100 < defense * 2:
			zombies_killed += 1
		else:
			var alive = []
			for s in GameState.survivors:
				if s.alive:
					alive.append(s)
			if alive.size() > 0:
				var target = alive[randi() % alive.size()]
				var zombie_data = _load_json("res://data/zombies.json")
				var ztype = zombie_data.zombie_types[randi() % zombie_data.zombie_types.size()]
				target.health -= ztype.damage
				if target.health <= 0:
					target.alive = false
					survivors_lost += 1
					EventBus.survivor_died.emit(target.name)

	EventBus.zombie_attack_ended.emit(survivors_lost)
	_show_notification(
		"Night attack! %d zombies. Killed: %d. Lost: %d." % [size, zombies_killed, survivors_lost],
		"#FF4444" if survivors_lost > 0 else "#FFAA00"
	)
	GameState.noise_level = max(0, GameState.noise_level - 0.15)

	if GameState.alive_count() <= 0:
		EventBus.game_over.emit("All survivors have died.")

func _refresh_resource_display() -> void:
	food_label.text = "🍗%d" % ResourceManager.get_resource("food")
	water_label.text = "💧%d" % ResourceManager.get_resource("water")
	wood_label.text = "🪵%d" % ResourceManager.get_resource("wood")
	metal_label.text = "🔩%d" % ResourceManager.get_resource("metal")
	med_label.text = "💊%d" % ResourceManager.get_resource("medicine")
	ammo_label.text = "🔫%d" % ResourceManager.get_resource("ammo")

func _refresh_day_display() -> void:
	var night_text = "🌙" if GameState.is_night else "☀️"
	day_label.text = "%s Day %d" % [night_text, GameState.current_day]
	pop_label.text = "👥%d/%d" % [GameState.alive_count(), GameState.population_cap]

func _show_notification(text: String, color: String = "#FFFFFF") -> void:
	notification_label.text = text
	notification_label.modulate = Color(color)
	notification_label.visible = true
	notification_timer.start()

func _on_notification_timeout() -> void:
	notification_label.visible = false

func _on_resource_changed(_resource: String, _amount: int, _total: int) -> void:
	_refresh_resource_display()

func _on_day_passed(_day: int) -> void:
	_refresh_day_display()

func _on_population_changed(_data = null) -> void:
	_refresh_day_display()

func _on_game_over(reason: String) -> void:
	_show_notification("GAME OVER: " + reason, "#FF0000")
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _load_json(path: String) -> Variant:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK:
		return null
	return json.get_data()
