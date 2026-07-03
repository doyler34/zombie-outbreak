extends UIScreen
## Mission briefing + squad picker, shared by every mission source (nest
## fights, world-map expeditions, future story missions).
##
## Callers inject a briefing and a launch callback via
## UIManager.push_screen(scene, setup):
##   briefing = {"title", "risk", "enemies_min", "enemies_max",
##               "rewards" (ranges), "travel_time" (optional),
##               "note" (optional)}
##   on_start = func(squad: Array) — fired after the screen closes.

var briefing: Dictionary = {}
var on_start: Callable = Callable()

var _selected: Array = []  # roster Survivors
var _count_label: Label
var _start_btn: Button


func _init() -> void:
	panel_size = Vector2(640, 560)


func _build_content() -> void:
	var content := build_frame("⚔  %s" % briefing.get("title", "MISSION"))

	content.add_child(_line("Risk:  %s" % briefing.get("risk", "?"), UIStyle.DANGER))
	content.add_child(_line("Enemies:  %d – %d zombies" % [
		briefing.get("enemies_min", 0), briefing.get("enemies_max", 0)], UIStyle.TEXT_DIM))
	if briefing.has("travel_time"):
		content.add_child(_line("Travel:  %ds each way" % int(briefing.travel_time), UIStyle.TEXT_DIM))
	var reward_ranges: Dictionary = briefing.get("rewards", {})
	if not reward_ranges.is_empty():
		var parts: Array[String] = []
		for id in reward_ranges:
			var def := DataManager.get_resource_def(id)
			var reward_range: Array = reward_ranges[id]
			parts.append("%s %d–%d" % [def.icon if def else id, reward_range[0], reward_range[1]])
		content.add_child(_line("Possible salvage:  " + "  ".join(parts), UIStyle.TEXT_DIM))
	if briefing.has("note"):
		content.add_child(_line(str(briefing.note), UIStyle.TEXT_DIM))

	var rule := ColorRect.new()
	rule.color = UIStyle.BRASS.darkened(0.4)
	rule.custom_minimum_size = Vector2(0, 1)
	content.add_child(rule)

	content.add_child(_line("Choose your squad (%d–%d):" % [CombatManager.SQUAD_MIN, CombatManager.SQUAD_MAX], UIStyle.TEXT_WARM))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	var candidates := SurvivorManager.available_for_combat()
	if candidates.is_empty():
		list.add_child(_line("Nobody is available — everyone is out on missions.", UIStyle.DANGER))
	for survivor in candidates:
		list.add_child(_make_row(survivor))

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	content.add_child(footer)

	_count_label = _line("Squad: 0", UIStyle.TEXT_WARM)
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(_count_label)

	_start_btn = UIStyle.make_button("⚔  START MISSION", 17)
	_start_btn.disabled = true
	_start_btn.pressed.connect(_on_start_pressed)
	footer.add_child(_start_btn)


func _make_row(survivor) -> Control:
	var role := DataManager.get_role(survivor.role)
	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.text = "%s  %s   —   %s  Lv%d   ❤ %d%%" % [
		role.icon if role else "●",
		survivor.survivor_name,
		role.display_name if role else survivor.role.capitalize(),
		survivor.level(),
		survivor.health]
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	UIStyle.style_button(toggle, 14)
	toggle.toggled.connect(func(on: bool): _on_toggled(survivor, on, toggle))
	return toggle


func _on_toggled(survivor, on: bool, toggle: Button) -> void:
	if on:
		if _selected.size() >= CombatManager.SQUAD_MAX:
			toggle.set_pressed_no_signal(false)
			EventBus.notify("Squad is full (max %d)." % CombatManager.SQUAD_MAX, 1)
			return
		_selected.append(survivor)
	else:
		_selected.erase(survivor)
	_count_label.text = "Squad: %d" % _selected.size()
	_start_btn.disabled = _selected.size() < CombatManager.SQUAD_MIN


func _on_start_pressed() -> void:
	var squad := _selected.duplicate()
	var launch := on_start
	UIManager.pop_screen()
	if launch.is_valid():
		launch.call(squad)


func _line(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	return label
