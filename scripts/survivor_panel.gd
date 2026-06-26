# survivor_panel.gd - Survivor management UI
extends Control

@onready var panel: Panel = $Panel
@onready var survivor_list: VBoxContainer = $Panel/ScrollContainer/SurvivorList
@onready var close_btn: Button = $Panel/CloseBtn

func _ready() -> void:
	visible = false
	close_btn.pressed.connect(_on_close)

func show_panel() -> void:
	_populate_list()
	visible = true
	close_btn.grab_focus()

func _on_close() -> void:
	visible = false

func _populate_list() -> void:
	for child in survivor_list.get_children():
		child.queue_free()

	for survivor in GameState.survivors:
		if not survivor.alive:
			continue

		var row = VBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 80)
		row.add_theme_constant_override("separation", 4)

		# Name + mood
		var top_row = HBoxContainer.new()
		var name_label = Label.new()
		var mood_icon = "😊" if survivor.mood in ["Happy", "Content"] else "😐" if survivor.mood in ["Neutral", "Worried"] else "😡"
		name_label.text = "%s  %s" % [mood_icon, survivor.name]
		name_label.custom_minimum_size = Vector2(250, 0)
		name_label.label_settings = LabelSettings.new()
		name_label.label_settings.font_size = 16
		name_label.label_settings.font_color = Color(1, 1, 1, 1)
		top_row.add_child(name_label)

		# Health bar (text-based)
		var health_label = Label.new()
		health_label.text = "HP: %d/100" % survivor.health
		health_label.label_settings = LabelSettings.new()
		health_label.label_settings.font_size = 14
		if survivor.health < 30:
			health_label.label_settings.font_color = Color(1, 0.2, 0.2, 1)
		elif survivor.health < 60:
			health_label.label_settings.font_color = Color(1, 0.7, 0.2, 1)
		else:
			health_label.label_settings.font_color = Color(0.3, 1, 0.3, 1)
		top_row.add_child(health_label)

		row.add_child(top_row)

		# Hunger + skills
		var bottom_row = HBoxContainer.new()
		var hunger_label = Label.new()
		hunger_label.text = "Food: %d%%" % survivor.hunger
		hunger_label.label_settings = LabelSettings.new()
		hunger_label.label_settings.font_size = 12
		hunger_label.label_settings.font_color = Color(0.7, 0.5, 0.2, 1)
		bottom_row.add_child(hunger_label)

		var skills_text = "Skills: "
		for skill_id in survivor.skills:
			skills_text += "%s(Lv%d) " % [skill_id, survivor.skills[skill_id]]
		var skills_label = Label.new()
		skills_label.text = skills_text
		skills_label.label_settings = LabelSettings.new()
		skills_label.label_settings.font_size = 12
		skills_label.label_settings.font_color = Color(0.5, 0.5, 0.8, 1)
		skills_label.custom_minimum_size = Vector2(300, 0)
		bottom_row.add_child(skills_label)

		row.add_child(bottom_row)
		survivor_list.add_child(row)
