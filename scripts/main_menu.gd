# main_menu.gd - Main menu controller
extends Control

@onready var new_game_btn: Button = $VBoxContainer/NewGameBtn
@onready var load_game_btn: Button = $VBoxContainer/LoadGameBtn
@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var version_label: Label = $VBoxContainer/VersionLabel

func _ready() -> void:
	new_game_btn.grab_focus()

	# Hide load button if no save exists
	if not GameState.has_save():
		load_game_btn.visible = false

	new_game_btn.pressed.connect(_on_new_game)
	load_game_btn.pressed.connect(_on_load_game)

func _on_new_game() -> void:
	GameState.new_game()
	get_tree().change_scene_to_file("res://scenes/base_scene.tscn")

func _on_load_game() -> void:
	if GameState.load_game():
		get_tree().change_scene_to_file("res://scenes/base_scene.tscn")
