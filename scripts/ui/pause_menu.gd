extends UIScreen
## In-game pause/system menu: save, return to main menu, close.


func _init() -> void:
	panel_size = Vector2(360, 0)


func _build_content() -> void:
	var content := build_frame("☰  MENU")

	var save_btn := UIStyle.make_button("Save Game")
	save_btn.pressed.connect(func():
		SaveManager.save_game()
		EventBus.notify("Game saved.", 2)
	)
	content.add_child(save_btn)

	var menu_btn := UIStyle.make_button("Main Menu")
	menu_btn.pressed.connect(func():
		UIManager.pop_screen()
		GameManager.return_to_menu()
	)
	content.add_child(menu_btn)

	var close_btn := UIStyle.make_button("Close")
	close_btn.pressed.connect(func(): UIManager.pop_screen())
	content.add_child(close_btn)
