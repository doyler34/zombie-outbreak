# base_scene.gd - Main game scene controller
extends Node2D

@onready var day_night_overlay: ColorRect = $DayNightOverlay
@onready var ground_bg: ColorRect = $BgLayer/GrassBackground
@onready var ui_layer: Control = $UILayer
@onready var top_bar: HBoxContainer = $UILayer/TopBar
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

@onready var buildings_btn: Button = $UILayer/BuildingsBtn
@onready var survivors_btn: Button = $UILayer/SurvivorsBtn
@onready var mission_btn: Button = $UILayer/MissionBtn
@onready var menu_btn: Button = $UILayer/MenuBtn

var building_panel: Control
var building_list: VBoxContainer
var buildings_data: Array = []

var day_night_timer: float = 0.0
const FULL_CYCLE := 120.0

func _ready() -> void:
	# === DEBUG: Force button positions/sizes in code (bypass anchors) ===
	_build_debug_buttons()

	# Build building panel in code
	_make_building_panel()

	# Menu panel
	_make_menu_panel()

	# Button connections
	buildings_btn.pressed.connect(_show_building_panel)
	survivors_btn.pressed.connect(func(): _show_notification("Crew panel coming soon", "#FFAA00"))
	mission_btn.pressed.connect(func(): _show_notification("Mission panel coming soon", "#FFAA00"))
	menu_btn.pressed.connect(func(): menu_panel.visible = true)

	# Signal connections
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.day_passed.connect(_on_day_passed)
	EventBus.survivor_added.connect(_on_population_changed)
	EventBus.survivor_died.connect(_on_population_changed)
	EventBus.notification.connect(_show_notification)
	EventBus.game_over.connect(_on_game_over)
	notification_timer.timeout.connect(_on_notification_timeout)

	_refresh_resource_display()
	_refresh_day_display()
	day_night_timer = GameState.day_timer
	_adjust_day_night_overlay()
	
	# Update ground shader with actual viewport size for seamless tiling
	_update_ground_shader()
	get_tree().root.size_changed.connect(_update_ground_shader)

func _build_debug_buttons() -> void:
	# Red debug bar at bottom
	var debug_bar = ColorRect.new()
	debug_bar.set_position(Vector2(0, 1200))
	debug_bar.set_size(Vector2(720, 80))
	debug_bar.color = Color(0.8, 0.1, 0.1, 1.0)
	ui_layer.add_child(debug_bar)

	# Create buttons FROM SCRATCH in code — no .tscn dependency
	_build_one_button("BUILD", 30, 1210, 120, 64, _show_building_panel)
	_build_one_button("CREW", 170, 1210, 110, 64, func(): _show_notification("Crew coming soon", "#FFAA00"))
	_build_one_button("MISSION", 300, 1210, 120, 64, func(): _show_notification("Mission coming soon", "#FFAA00"))
	_build_one_button("MENU", 440, 1210, 100, 64, func(): menu_panel.visible = true)

func _build_one_button(text: String, x: float, y: float, w: float, h: float, callback: Callable) -> void:
	var btn = Button.new()
	btn.text = text
	btn.set_position(Vector2(x, y))
	btn.set_size(Vector2(w, h))

	# Bright yellow-green background — impossible to miss
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.7, 0.2, 1.0)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.3, 1.0, 0.4, 1.0)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.pressed.connect(callback)
	ui_layer.add_child(btn)

## BUILDING PANEL

func _make_building_panel() -> void:
	var file = FileAccess.open("res://data/buildings.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			buildings_data = json.get_data().buildings
		file.close()

	building_panel = Control.new()
	building_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	building_panel.visible = false
	building_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Dim background — tap anywhere on it closes the panel
	var dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.75)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			building_panel.visible = false
	)
	building_panel.add_child(dim)

	# Panel box — centered MANUALLY (720x1280 viewport, 600x700 panel)
	var bw = 600
	var bh = 700
	var box = Panel.new()
	box.set_position(Vector2((720 - bw) / 2, (1280 - bh) / 2))
	box.set_size(Vector2(bw, bh))
	# Solid dark background
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.15, 0.98)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.3, 0.3, 0.5, 1)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	box.add_theme_stylebox_override("panel", panel_style)
	building_panel.add_child(box)

	# Title
	var title = Label.new()
	title.set_position(Vector2(15, 10))
	title.set_size(Vector2(bw - 70, 30))
	title.text = "BUILDINGS"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
	box.add_child(title)

	# Close button — bright red, easy to see and tap
	var close = Button.new()
	close.set_position(Vector2(bw - 55, 5))
	close.set_size(Vector2(45, 35))
	close.text = "✕"
	close.add_theme_font_size_override("font_size", 18)
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.7, 0.15, 0.15, 1)
	close_style.corner_radius_top_left = 4
	close_style.corner_radius_top_right = 4
	close_style.corner_radius_bottom_left = 4
	close_style.corner_radius_bottom_right = 4
	close.add_theme_stylebox_override("normal", close_style)
	close.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	close.pressed.connect(func(): building_panel.visible = false)
	box.add_child(close)

	# Scroll container for building list
	var scroll = ScrollContainer.new()
	scroll.set_position(Vector2(10, 50))
	scroll.set_size(Vector2(bw - 20, bh - 60))
	box.add_child(scroll)

	building_list = VBoxContainer.new()
	building_list.layout_mode = 2
	building_list.add_theme_constant_override("separation", 8)
	scroll.add_child(building_list)

	ui_layer.add_child(building_panel)

func _show_building_panel() -> void:
	_populate_building_list()
	building_panel.visible = true
	_show_notification("Build menu opened", "#00FF00")

func _populate_building_list() -> void:
	for child in building_list.get_children():
		child.queue_free()

	for bld in buildings_data:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.custom_minimum_size = Vector2(0, 50)

		var current_level = GameState.buildings.get(bld.id, 0)
		var is_placed = GameState.buildings.has(bld.id)
		var is_broken = is_placed and current_level == 0

		var name_label = Label.new()
		if is_broken:
			name_label.text = "%s (Broken)" % bld.name
		else:
			name_label.text = "%s (Lv %d)" % [bld.name, current_level]
		name_label.custom_minimum_size = Vector2(160, 0)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		row.add_child(name_label)

		var btn = Button.new()
		if is_broken:
			btn.text = "Repair"
		elif not is_placed:
			btn.text = "Build"
		elif current_level < bld.max_level:
			btn.text = "Upgrade Lv%d" % (current_level + 1)
		else:
			btn.text = "MAX"
			btn.disabled = true
		btn.custom_minimum_size = Vector2(140, 42)
		btn.add_theme_font_size_override("font_size", 15)
		var bld_ref = bld
		var lvl = current_level
		btn.pressed.connect(func(): _do_build(bld_ref, lvl))
		row.add_child(btn)

		var costs = _get_cost_for_level(bld, current_level + 1)
		var parts = []
		for key in costs:
			if costs[key] > 0:
				parts.append("%s:%d" % [key, costs[key]])
		var cost_text = "  ".join(parts)
		var cost_label = Label.new()
		cost_label.text = cost_text
		cost_label.custom_minimum_size = Vector2(140, 0)
		cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cost_label.add_theme_font_size_override("font_size", 13)
		cost_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65, 1))
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
			_show_notification("%s repaired!" % bld.name, "#00FF00")
		else:
			_show_notification("%s upgraded to Lv%d!" % [bld.name, target_level], "#00FF00")
		_populate_building_list()
	else:
		_show_notification("Not enough resources!", "#FF4444")

## MENU PANEL

var menu_panel: Control

func _make_menu_panel() -> void:
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
	save_btn.text = "Save Game"
	save_btn.custom_minimum_size = Vector2(200, 50)
	save_btn.pressed.connect(func(): GameState.save_game(); _show_notification("Saved!", "#00FF00"))
	vbox.add_child(save_btn)

	var quit_btn = Button.new()
	quit_btn.text = "Main Menu"
	quit_btn.custom_minimum_size = Vector2(200, 50)
	quit_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	vbox.add_child(quit_btn)

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(200, 50)
	close_btn.pressed.connect(func(): menu_panel.visible = false)
	vbox.add_child(close_btn)

	ui_layer.add_child(menu_panel)

## GAME LOOP

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
		var df = fraction / 0.55
		if df < 0.1:
			alpha = lerpf(0.3, 0.0, df / 0.1)
		elif df > 0.9:
			alpha = lerpf(0.0, 0.3, (df - 0.9) / 0.1)
		else:
			alpha = 0.0
		GameState.is_night = false
	else:
		var nf = (fraction - 0.55) / 0.45
		alpha = lerpf(0.3, 0.55, nf)
		GameState.is_night = true
	day_night_overlay.color = Color(0.0, 0.0, 0.1, alpha)

func _check_zombie_attack() -> void:
	var data = _load_json("res://data/zombies.json")
	if data == null: return
	var chance = data.attack_triggers.daily_chance + GameState.noise_level
	if randf() < chance:
		var key = "small"
		if GameState.current_day > 7: key = "medium"
		if GameState.current_day > 14: key = "large"
		var horde = data.horde_sizes[key]
		_trigger_zombie_attack(key, randi_range(horde.min, horde.max))

func _trigger_zombie_attack(_key: String, size: int) -> void:
	EventBus.zombie_attack_started.emit(size)
	var def = GameState.base_defense
	var killed = 0
	var lost = 0
	for i in range(size):
		if randi() % 100 < def * 2:
			killed += 1
		else:
			var alive = []
			for s in GameState.survivors:
				if s.alive: alive.append(s)
			if alive.size() > 0:
				var t = alive[randi() % alive.size()]
				var zd = _load_json("res://data/zombies.json")
				var zt = zd.zombie_types[randi() % zd.zombie_types.size()]
				t.health -= zt.damage
				if t.health <= 0:
					t.alive = false
					lost += 1
					EventBus.survivor_died.emit(t.name)
	EventBus.zombie_attack_ended.emit(lost)
	_show_notification("Attack! %d zoms. Killed: %d. Lost: %d." % [size, killed, lost],
		"#FF4444" if lost > 0 else "#FFAA00")
	GameState.noise_level = max(0, GameState.noise_level - 0.15)
	if GameState.alive_count() <= 0:
		EventBus.game_over.emit("All dead.")

func _refresh_resource_display() -> void:
	food_label.text = "🍗%d" % ResourceManager.get_resource("food")
	water_label.text = "💧%d" % ResourceManager.get_resource("water")
	wood_label.text = "🪵%d" % ResourceManager.get_resource("wood")
	metal_label.text = "🔩%d" % ResourceManager.get_resource("metal")
	med_label.text = "💊%d" % ResourceManager.get_resource("medicine")
	ammo_label.text = "🔫%d" % ResourceManager.get_resource("ammo")

func _refresh_day_display() -> void:
	var nt = "🌙" if GameState.is_night else "☀️"
	day_label.text = "%s Day %d" % [nt, GameState.current_day]
	pop_label.text = "👥%d/%d" % [GameState.alive_count(), GameState.population_cap]

func _show_notification(text: String, color: String = "#FFFFFF") -> void:
	notification_label.text = text
	notification_label.modulate = Color(color)
	notification_label.visible = true
	notification_timer.start()

func _on_notification_timeout() -> void:
	notification_label.visible = false

func _on_resource_changed(_r, _a, _t) -> void:
	_refresh_resource_display()

func _on_day_passed(_d) -> void:
	_refresh_day_display()

func _on_population_changed(_d = null) -> void:
	_refresh_day_display()

func _on_game_over(reason: String) -> void:
	_show_notification("GAME OVER: " + reason, "#FF0000")
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _load_json(path: String) -> Variant:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK: return null
	return json.get_data()

func _update_ground_shader() -> void:
	var vp_size = get_viewport().get_visible_rect().size
	ground_bg.material.set_shader_parameter("screen_size", vp_size)
