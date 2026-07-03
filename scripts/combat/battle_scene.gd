class_name BattleScene
extends CanvasLayer
## The battle overlay: a small top-down arena where the squad and the
## horde fight automatically while the player uses a few abilities.
##
## Lives on a CanvasLayer above the game world (which is time-frozen in
## the BATTLE state) — no scene change, so the settlement is untouched
## underneath. CombatManager spawns this, feeds it a mission spec and a
## squad, and resolves the emitted outcome into roster/reward changes.

## Raw battle outcome; CombatManager turns this into a mission result.
signal finished(outcome: Dictionary)
## Player dismissed the result screen.
signal continue_pressed()

## The player's ability loadout. Future abilities: append here.
const ABILITIES: Array = [HealAbility, RetreatAbility]

## World-map expeditions run hands-off: no ability bar, pure auto-battle.
## Set by CombatManager before this node enters the tree.
var auto_mode: bool = false

## Watch-speed multiplier (viewing control, not a combat control) —
## cycled by the ⏩ button through these steps.
## NOTE: deliberately untyped — typed const collections have broken
## script compilation in this project before (see BUILDING_OFFSETS bug).
const SPEED_STEPS := [1.0, 2.0, 3.0]
var combat_speed: float = 1.0

var _speed_button: Button

var _arena: Rect2
var _units: Array[CombatUnit] = []
var _dead_survivors: Array = []      # roster Survivors killed in this fight
var _zombies_killed: int = 0
var _xp_earned: int = 0
var _running: bool = false
var _squad: Array = []               # roster Survivors sent in

var _root: Control
var _status_label: Label
var _ability_bar: HBoxContainer
var _abilities: Array = []           # {ability, button, cooldown_left, uses_left}


func _ready() -> void:
	layer = 85  # above HUD (80), below UIManager screens (90)
	_build_layout()


## Entry point, called by CombatManager.
## [param spec] = {"zombies": Array[ZombieDefinition]}.
func start(spec: Dictionary, squad: Array) -> void:
	_squad = squad
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Squad enters from the left, spread vertically.
	for i in squad.size():
		var survivor = squad[i]
		var role := DataManager.get_role(survivor.role)
		if role == null:
			role = DataManager.all_roles().front()
		var unit := _spawn_unit(CombatUnit.Team.SURVIVORS, role, survivor)
		unit.position = Vector2(
			_arena.position.x + 70 + (i % 2) * 50,
			_arena.get_center().y + (i - squad.size() / 2.0) * 70)

	# Horde shambles in from the right.
	for zombie_def: ZombieDefinition in spec.get("zombies", []):
		var unit := _spawn_unit(CombatUnit.Team.ZOMBIES, zombie_def)
		unit.position = Vector2(
			_arena.end.x - 70 - rng.randf_range(0, 120),
			rng.randf_range(_arena.position.y + 50, _arena.end.y - 50))

	_running = true
	_update_status()

	# Degenerate roll (all ranges hit zero): nothing to fight — instant
	# victory instead of an arena that can never end.
	if team_units(CombatUnit.Team.ZOMBIES).is_empty():
		end_battle("victory")


func _process(delta: float) -> void:
	if not _running:
		return
	for entry: Dictionary in _abilities:
		if entry.cooldown_left > 0.0:
			entry.cooldown_left = maxf(entry.cooldown_left - delta * combat_speed, 0.0)
		_refresh_ability_button(entry)


# ── Queries used by units and abilities ──────────────────────────────────

func is_running() -> bool:
	return _running


func team_units(team: CombatUnit.Team) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	for unit in _units:
		if is_instance_valid(unit) and unit.is_alive() and unit.team == team:
			out.append(unit)
	return out


func nearest_enemy(from: CombatUnit) -> CombatUnit:
	var enemy_team := CombatUnit.Team.ZOMBIES \
		if from.team == CombatUnit.Team.SURVIVORS else CombatUnit.Team.SURVIVORS
	var best: CombatUnit = null
	var best_distance := INF
	for unit in team_units(enemy_team):
		var d := from.position.distance_squared_to(unit.position)
		if d < best_distance:
			best_distance = d
			best = unit
	return best


## The hurt ally closest to death (excluding self), or null if none.
func most_injured_ally(from: CombatUnit) -> CombatUnit:
	var best: CombatUnit = null
	var best_ratio := 1.0
	for unit in team_units(from.team):
		if unit == from:
			continue
		var ratio := float(unit.hp) / float(unit.stats.max_health)
		if ratio < 1.0 and ratio < best_ratio:
			best_ratio = ratio
			best = unit
	return best


func clamp_to_arena(pos: Vector2) -> Vector2:
	return pos.clamp(_arena.position + Vector2.ONE * 30, _arena.end - Vector2.ONE * 30)


## Floating combat text (damage, MISS, CRIT, heals, deaths) so the
## real-time fight is readable at a glance.
func spawn_popup(at: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.position = at + Vector2(randf_range(-14, 14), -34)
	var tween := label.create_tween()
	tween.set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 34, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


# ── Battle end ───────────────────────────────────────────────────────────

func end_battle(result: String) -> void:
	if not _running:
		return
	_running = false
	var survivor_states := []
	for survivor in _squad:
		var state := {"survivor": survivor, "alive": not _dead_survivors.has(survivor), "hp_ratio": 0.0}
		for unit in team_units(CombatUnit.Team.SURVIVORS):
			if unit.survivor == survivor:
				state.hp_ratio = float(unit.hp) / float(unit.stats.max_health)
		survivor_states.append(state)
	finished.emit({
		"result": result,
		"zombies_killed": _zombies_killed,
		"xp_earned": _xp_earned,
		"survivors": survivor_states,
	})


## Called by CombatManager with the resolved mission result.
func show_result(result: Dictionary) -> void:
	_ability_bar.visible = false
	_speed_button.visible = false

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.panel_style())
	panel.custom_minimum_size = Vector2(460, 0)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var titles := {"victory": "☠  ZONE CLEARED", "defeat": "✝  SQUAD LOST", "retreat": "🏳  RETREAT"}
	var title := Label.new()
	title.text = titles.get(result.outcome, "BATTLE OVER")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color",
		UIStyle.BRASS_BRIGHT if result.outcome == "victory" else UIStyle.DANGER)
	box.add_child(title)

	_add_result_line(box, "Zombies killed:  %d" % result.zombies_killed)
	if not result.dead.is_empty():
		_add_result_line(box, "Lost:  " + ", ".join(result.dead))
	if not result.injured.is_empty():
		_add_result_line(box, "Injured:  " + ", ".join(result.injured))
	if not result.rewards.is_empty():
		var parts: Array[String] = []
		for id in result.rewards:
			var def := DataManager.get_resource_def(id)
			parts.append("+%d %s" % [result.rewards[id], def.icon if def else id])
		_add_result_line(box, "Salvage:  " + "  ".join(parts))
	if result.xp_each > 0:
		_add_result_line(box, "XP gained:  +%d each" % result.xp_each)
	for rescued_name in result.rescued:
		_add_result_line(box, "🎉 Rescued:  %s" % rescued_name)

	var continue_btn := UIStyle.make_button("CONTINUE", 18)
	continue_btn.pressed.connect(func(): continue_pressed.emit())
	box.add_child(continue_btn)


# ── Internal ─────────────────────────────────────────────────────────────

func _spawn_unit(team: CombatUnit.Team, def: CombatantDefinition, survivor = null) -> CombatUnit:
	var unit := CombatUnit.new()
	add_child(unit)
	unit.setup(self, team, def, survivor)
	unit.died.connect(_on_unit_died)
	_units.append(unit)
	return unit


func _on_unit_died(unit: CombatUnit) -> void:
	_units.erase(unit)
	spawn_popup(unit.position, "💀", Color(0.9, 0.9, 0.9))
	if unit.team == CombatUnit.Team.ZOMBIES:
		_zombies_killed += 1
		_xp_earned += (unit.stats as ZombieDefinition).xp_value
		if team_units(CombatUnit.Team.ZOMBIES).is_empty():
			end_battle("victory")
	else:
		_dead_survivors.append(unit.survivor)
		if team_units(CombatUnit.Team.SURVIVORS).is_empty():
			end_battle("defeat")
	_update_status()


func _update_status() -> void:
	_status_label.text = "👥 %d    vs    🧟 %d" % [
		team_units(CombatUnit.Team.SURVIVORS).size(),
		team_units(CombatUnit.Team.ZOMBIES).size()]


func _build_layout() -> void:
	var viewport_size := Vector2(1280, 720)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # block world input
	add_child(_root)
	# Use the real viewport once inside the tree.
	viewport_size = _root.get_viewport_rect().size if _root.is_inside_tree() else viewport_size

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.06, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	_arena = Rect2(40, 80, viewport_size.x - 80, viewport_size.y - 200)
	var arena_rect := Panel.new()
	var arena_style := StyleBoxFlat.new()
	arena_style.bg_color = Color(0.10, 0.10, 0.08)
	arena_style.set_border_width_all(2)
	arena_style.border_color = UIStyle.BRASS.darkened(0.3)
	arena_style.set_corner_radius_all(8)
	arena_rect.add_theme_stylebox_override("panel", arena_style)
	arena_rect.position = _arena.position
	arena_rect.size = _arena.size
	arena_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(arena_rect)

	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status_label.offset_top = 26
	_status_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.add_theme_color_override("font_color", UIStyle.BRASS_BRIGHT)
	_root.add_child(_status_label)

	# Watch-speed toggle — a viewing control, available in both modes.
	_speed_button = UIStyle.make_button("⏩ 1x", 15)
	_speed_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_speed_button.offset_top = 18
	_speed_button.offset_right = -24
	_speed_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_speed_button.pressed.connect(_cycle_speed)
	_root.add_child(_speed_button)

	_ability_bar = HBoxContainer.new()
	_ability_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ability_bar.offset_bottom = -24
	_ability_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ability_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ability_bar.add_theme_constant_override("separation", 16)
	_root.add_child(_ability_bar)

	if auto_mode:
		var auto_label := Label.new()
		auto_label.text = "⚙ AUTO COMBAT"
		auto_label.add_theme_font_size_override("font_size", 15)
		auto_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		_ability_bar.add_child(auto_label)
		return

	for ability_class in ABILITIES:
		var ability: CombatAbility = ability_class.new()
		var button := UIStyle.make_button("%s  %s" % [ability.icon, ability.display_name], 18)
		var entry := {"ability": ability, "button": button, "cooldown_left": 0.0, "uses_left": ability.max_uses}
		button.pressed.connect(func(): _use_ability(entry))
		_ability_bar.add_child(button)
		_abilities.append(entry)


func _cycle_speed() -> void:
	var index := (SPEED_STEPS.find(combat_speed) + 1) % SPEED_STEPS.size()
	combat_speed = SPEED_STEPS[index]
	_speed_button.text = "⏩ %dx" % int(combat_speed)


func _use_ability(entry: Dictionary) -> void:
	if not _running or entry.cooldown_left > 0.0 or entry.uses_left == 0:
		return
	var ability: CombatAbility = entry.ability
	if ability.execute(self):
		entry.cooldown_left = ability.cooldown
		if entry.uses_left > 0:
			entry.uses_left -= 1
		_refresh_ability_button(entry)


func _refresh_ability_button(entry: Dictionary) -> void:
	var ability: CombatAbility = entry.ability
	var button: Button = entry.button
	if entry.uses_left == 0:
		button.text = "%s  %s (used)" % [ability.icon, ability.display_name]
		button.disabled = true
	elif entry.cooldown_left > 0.0:
		button.text = "%s  %s (%ds)" % [ability.icon, ability.display_name, ceili(entry.cooldown_left)]
		button.disabled = true
	else:
		button.text = "%s  %s" % [ability.icon, ability.display_name]
		button.disabled = false


func _add_result_line(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", UIStyle.TEXT_WARM)
	parent.add_child(label)
