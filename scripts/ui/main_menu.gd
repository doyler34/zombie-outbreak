extends Control
## Main menu — entry point scene. Pure UI; all flow goes through
## GameManager so the menu has no knowledge of scenes or saves beyond
## asking "is there one?".


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	var title := Label.new()
	title.text = "ZOMBIE OUTBREAK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", UIStyle.BRASS_BRIGHT)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "— eight years after the fall —"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	box.add_child(subtitle)

	box.add_child(_spacer(24))

	var continue_btn := UIStyle.make_button("Continue", 22)
	continue_btn.disabled = not SaveManager.has_save()
	continue_btn.pressed.connect(func(): GameManager.continue_game())
	box.add_child(continue_btn)

	var new_btn := UIStyle.make_button("New Game", 22)
	new_btn.pressed.connect(func(): GameManager.start_new_game())
	box.add_child(new_btn)

	var quit_btn := UIStyle.make_button("Quit", 22)
	quit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_btn)


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c
