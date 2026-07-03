extends UIScreen
## The world map — Last Day on Earth style location layer.
##
## Home base sits at the center; LocationDefinitions place themselves via
## map_position. Territory states are color-coded (locked / available /
## cleared / controlled) and the active expedition shows its phase and
## timer live on its location marker.
##
## Tapping an AVAILABLE location opens the shared squad-select briefing;
## the mission then runs through WorldMapManager (travel → auto combat →
## rewards → territory update).

const SQUAD_SELECT_SCENE := preload("res://scenes/ui/squad_select.tscn")
const MAP_SIZE := Vector2(1100, 430)
const HOME_POSITION := Vector2(510, 195)

## The manager's script — needed to reference its enum in constants
## (the autoload singleton itself isn't a compile-time constant).
const WorldMapStates := preload("res://scripts/managers/world_map_manager.gd")

const STATE_COLORS := {
	WorldMapStates.LocationState.LOCKED: Color(0.16, 0.15, 0.14),
	WorldMapStates.LocationState.AVAILABLE: Color(0.24, 0.18, 0.09),
	WorldMapStates.LocationState.CLEARED: Color(0.10, 0.20, 0.10),
	WorldMapStates.LocationState.CONTROLLED: Color(0.26, 0.20, 0.04),
}
const STATE_MARKS := {
	WorldMapStates.LocationState.LOCKED: "🔒",
	WorldMapStates.LocationState.AVAILABLE: "",
	WorldMapStates.LocationState.CLEARED: "✔",
	WorldMapStates.LocationState.CONTROLLED: "🏴",
}
const PHASE_MARKS := {"travel_out": "🚶", "combat": "⚔", "return": "🏠"}

var _map_area: Control
var _status_line: Label
var _buttons: Dictionary = {}  # location id -> Button


func _init() -> void:
	panel_size = Vector2(1180, 620)


func _build_content() -> void:
	var content := build_frame("🗺  WORLD MAP")

	_map_area = Control.new()
	_map_area.custom_minimum_size = MAP_SIZE
	_map_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_map_area)

	_status_line = Label.new()
	_status_line.add_theme_font_size_override("font_size", 14)
	_status_line.add_theme_color_override("font_color", UIStyle.TEXT_WARM)
	content.add_child(_status_line)

	var legend := Label.new()
	legend.text = "🔒 Locked      ⚔ Available      ✔ Cleared      🏴 Controlled territory"
	legend.add_theme_font_size_override("font_size", 12)
	legend.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	content.add_child(legend)

	EventBus.location_state_changed.connect(func(_id, _s): _rebuild_map())
	EventBus.expedition_updated.connect(func(_id, _p): _rebuild_map())
	EventBus.game_tick.connect(_refresh_dynamic)

	_rebuild_map()


# ── Map construction ─────────────────────────────────────────────────────

func _rebuild_map() -> void:
	if not is_instance_valid(_map_area):
		return
	for child in _map_area.get_children():
		_map_area.remove_child(child)
		child.queue_free()
	_buttons.clear()

	# Home base marker.
	var home := Label.new()
	home.text = "🏰\nHOME BASE"
	home.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	home.add_theme_font_size_override("font_size", 15)
	home.add_theme_color_override("font_color", UIStyle.BRASS_BRIGHT)
	home.position = HOME_POSITION
	_map_area.add_child(home)

	for def in DataManager.all_locations():
		var button := _make_location_button(def)
		_map_area.add_child(button)
		button.position = def.map_position
		_buttons[def.id] = button
	_refresh_dynamic()


func _make_location_button(def: LocationDefinition) -> Button:
	var state := WorldMapManager.state_of(def.id)
	var button := Button.new()
	button.text = _button_text(def)
	UIStyle.style_button(button, 13)
	var style := UIStyle.button_style(STATE_COLORS[state],
		UIStyle.BRASS if state == WorldMapStates.LocationState.AVAILABLE else UIStyle.BRASS.darkened(0.45))
	button.add_theme_stylebox_override("normal", style)
	if state == WorldMapStates.LocationState.LOCKED:
		button.add_theme_color_override("font_color", Color(0.5, 0.47, 0.42))
	button.pressed.connect(func(): _on_location_pressed(def))
	return button


func _button_text(def: LocationDefinition) -> String:
	var state := WorldMapManager.state_of(def.id)
	var mark: String = STATE_MARKS[state]
	var expedition := WorldMapManager.expedition()
	if not expedition.is_empty() and expedition.location_id == def.id:
		mark = "%s %ds" % [PHASE_MARKS.get(expedition.phase, ""), maxi(int(expedition.timer), 0)] \
			if expedition.phase != "combat" else "⚔ fighting"
	return "%s %s %s\n☠ %s" % [def.icon, def.display_name, mark, def.threat_label()]


## Light per-tick refresh: only the travelling location's label changes.
func _refresh_dynamic() -> void:
	var expedition := WorldMapManager.expedition()
	if expedition.is_empty():
		_status_line.text = "No squad deployed."
	else:
		var def := DataManager.get_location(str(expedition.location_id))
		var squad_size: int = expedition.squad.size()
		_status_line.text = "Expedition: %d survivors — %s (%s)" % [
			squad_size, def.display_name, str(expedition.phase).replace("_", " ")]
		if _buttons.has(def.id):
			_buttons[def.id].text = _button_text(def)


# ── Interaction ──────────────────────────────────────────────────────────

func _on_location_pressed(def: LocationDefinition) -> void:
	var state := WorldMapManager.state_of(def.id)
	if state == WorldMapStates.LocationState.LOCKED:
		var names: Array[String] = []
		for required_id in def.requires:
			var required := DataManager.get_location(required_id)
			names.append(required.display_name if required else required_id)
		EventBus.notify("🔒 %s — requires: %s" % [def.display_name, ", ".join(names)], 1)
	elif state == WorldMapStates.LocationState.CLEARED:
		EventBus.notify("%s has been cleared." % def.display_name, 0)
	elif state == WorldMapStates.LocationState.CONTROLLED:
		EventBus.notify("%s is under your control." % def.display_name, 2)
	else:
		_open_briefing(def)


func _open_briefing(def: LocationDefinition) -> void:
	if WorldMapManager.has_active_expedition():
		EventBus.notify("A squad is already deployed.", 1)
		return
	var enemies_min := 0
	var enemies_max := 0
	for zombie_id in def.zombies:
		var zombie_range: Array = def.zombies[zombie_id]
		enemies_min += int(zombie_range[0])
		enemies_max += int(zombie_range[1])
	UIManager.push_screen(SQUAD_SELECT_SCENE, func(screen):
		screen.briefing = {
			"title": def.display_name.to_upper(),
			"risk": def.threat_label(),
			"enemies_min": enemies_min,
			"enemies_max": enemies_max,
			"rewards": def.rewards,
			"travel_time": def.travel_time,
			"note": def.description,
		}
		screen.on_start = func(squad: Array): WorldMapManager.send_squad(def.id, squad)
	)
