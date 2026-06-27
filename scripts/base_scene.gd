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

# Panel references (set in _ready via load)
var building_panel: Control
var survivor_panel: Control
var mission_panel: Control
var menu_panel: Control

# Day/night
var day_night_timer: float = 0.0
const FULL_CYCLE := 120.0

func _ready() -> void:
	# Load panel scenes
	var bp_scene = load("res://ui/building_panel_ui.tscn")
	if bp_scene:
		building_panel = bp_scene.instantiate()
		ui_layer.add_child(building_panel)

	var sp_scene = load("res://ui/survivor_panel_ui.tscn")
	if sp_scene:
		survivor_panel = sp_scene.instantiate()
		ui_layer.add_child(survivor_panel)

	var mp_scene = load("res://ui/mission_panel_ui.tscn")
	if mp_scene:
		mission_panel = mp_scene.instantiate()
		ui_layer.add_child(mission_panel)

	# Simple menu panel (back to menu)
	_create_menu_panel()

	# Connect signals
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.day_passed.connect(_on_day_passed)
	EventBus.survivor_added.connect(_on_population_changed)
	EventBus.survivor_died.connect(_on_population_changed)
	EventBus.notification.connect(_show_notification)
	EventBus.game_over.connect(_on_game_over)

	# Connect UI button signals
	if building_panel and buildings_btn:
		buildings_btn.pressed.connect(func(): building_panel.show_panel())
	if survivor_panel and survivors_btn:
		survivors_btn.pressed.connect(func(): survivor_panel.show_panel())
	if mission_panel and mission_btn:
		mission_btn.pressed.connect(func(): mission_panel.show_panel())
	if menu_btn:
		menu_btn.pressed.connect(func(): menu_panel.visible = true)

	# Connect notification timer
	notification_timer.timeout.connect(_on_notification_timeout)

	# Initialize UI
	_refresh_resource_display()
	_refresh_day_display()

	# Day/night start state
	day_night_timer = GameState.day_timer
	_adjust_day_night_overlay()

func _create_menu_panel() -> void:
	menu_panel = Control.new()
	menu_panel.layout_mode = 3
	menu_panel.anchors_preset = Control.PRESET_FULL_RECT
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
