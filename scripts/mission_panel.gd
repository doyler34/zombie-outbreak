# mission_panel.gd - Scavenging and rescue mission UI (updated)
extends Control

@onready var panel: Panel = $Panel
@onready var close_btn: Button = $Panel/CloseBtn
@onready var tab_container: TabContainer = $Panel/TabContainer
@onready var scavenge_list: VBoxContainer = $Panel/TabContainer/Scavenge/MissionListScavenge
@onready var rescue_list: VBoxContainer = $Panel/TabContainer/Rescue/MissionListRescue

var missions_data: Dictionary = {}

func _ready() -> void:
	visible = false
	close_btn.pressed.connect(_on_close)
	_load_mission_data()
	_populate_all()

func show_panel() -> void:
	_populate_all()
	visible = true
	close_btn.grab_focus()

func _on_close() -> void:
	visible = false

func _load_mission_data() -> void:
	var file = FileAccess.open("res://data/missions.json", FileAccess.READ)
	if file == null:
		return
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) == OK:
		missions_data = json.get_data()

func _populate_all() -> void:
	_populate_tab(scavenge_list, missions_data.scavenge_locations, false)
	_populate_tab(rescue_list, missions_data.rescue_missions, true)

func _populate_tab(parent: VBoxContainer, missions: Array, is_rescue: bool) -> void:
	# Clear existing
	for child in parent.get_children():
		child.queue_free()

	for mission in missions:
		var row = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 55)
		row.add_theme_constant_override("separation", 8)

		# Mission name + info
		var info = VBoxContainer.new()
		var name_label = Label.new()
		name_label.text = mission.name
		name_label.label_settings = LabelSettings.new()
		name_label.label_settings.font_size = 16
		name_label.label_settings.font_color = Color(1, 0.85, 0.3, 1)
		info.add_child(name_label)

		var detail_label = Label.new()
		detail_label.text = "🕐 %ds  ⚠️ Danger %d  Survs: %d-%d" % [
			mission.duration, mission.danger, mission.min_survivors, mission.max_survivors
		]
		detail_label.label_settings = LabelSettings.new()
		detail_label.label_settings.font_size = 12
		detail_label.label_settings.font_color = Color(0.6, 0.6, 0.6, 1)
		info.add_child(detail_label)
		row.add_child(info)

		# Launch button
		var btn = Button.new()
		btn.text = "GO"
		btn.custom_minimum_size = Vector2(80, 50)
		btn.theme_override_font_sizes = {font_size = 18}
		btn.pressed.connect(_on_launch_mission.bind(mission, is_rescue))
		row.add_child(btn)

		parent.add_child(row)

func _on_launch_mission(mission: Dictionary, is_rescue: bool) -> void:
	var available = GameState.available_survivors()
	if available.size() < mission.min_survivors:
		EventBus.notification.emit("Need %d survivors for this mission!" % mission.min_survivors, "#FF4444")
		return

	available.shuffle()
	var team = []
	var count = mini(mission.max_survivors, available.size())
	for i in range(count):
		team.append(available[i])

	var total_scavenge = 0
	for s in team:
		var skill = s.skills.get("scavenging", 1)
		total_scavenge += skill

	var success_chance = clampf(0.3 + (total_scavenge * 0.1) - (mission.danger * 0.1), 0.1, 0.95)
	EventBus.mission_started.emit(mission)

	if randf() < success_chance:
		var loot = {}
		for resource in mission.loot_table:
			var cfg = mission.loot_table[resource]
			loot[resource] = randi_range(cfg.min, cfg.max)
			ResourceManager.modify(resource, loot[resource])

		if is_rescue:
			var rescue_count = randi_range(mission.rescue_count.min, mission.rescue_count.max)
			var names_data = _load_json("res://data/survivors.json")
			if names_data:
				for i in range(rescue_count):
					if GameState.alive_count() < GameState.population_cap:
						var s = GameState._generate_survivor(names_data)
						GameState.survivors.append(s)
						EventBus.survivor_added.emit(s)

		var loot_texts: Array[String] = []
		for k in loot:
			loot_texts.append("%s +%d" % [k, loot[k]])
		var loot_text = ", ".join(loot_texts)
		EventBus.mission_completed.emit(mission, loot)
		EventBus.notification.emit("Mission success! " + loot_text, "#00FF00")
	else:
		EventBus.mission_failed.emit(mission, "Team encountered too many zombies.")
		EventBus.notification.emit("Mission failed — team returned empty-handed.", "#FFAA00")

	var zombies_data = _load_json("res://data/zombies.json")
	if zombies_data:
		GameState.noise_level = min(
			zombies_data.attack_triggers.max_noise,
			GameState.noise_level + zombies_data.attack_triggers.noise_per_scavenge
		)

	visible = false

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
