class_name BattleScene
extends CanvasLayer
## The battle overlay: a small 3D arena where the squad and the horde
## fight automatically while the player uses a few abilities.
##
## Structure: a full-screen SubViewport renders the 3D fight (angled
## orthographic camera, ground, character models) and the UI (status,
## ability bar, speed toggle, result panel) is drawn on a Control on top.
## Lives on a CanvasLayer above the game world (time-frozen in the BATTLE
## state) — no scene change, so the settlement is untouched underneath.
## CombatManager spawns this, feeds it a mission spec and a squad, and
## resolves the emitted outcome into roster/reward changes.

## Raw battle outcome; CombatManager turns this into a mission result.
signal finished(outcome: Dictionary)
## Player dismissed the result screen.
signal continue_pressed()

## The player's ability loadout. Future abilities: append here.
## Must use preload — class_name references aren't constant expressions,
## and a non-constant const kills this script and everything that
## depends on it (this exact line broke all combat).
const ABILITIES: Array = [
	preload("res://scripts/combat/abilities/heal_ability.gd"),
	preload("res://scripts/combat/abilities/retreat_ability.gd"),
]

## Arena half-extents in meters (XZ plane, centered on origin).
const ARENA_HALF := Vector2(9.0, 5.0)
## Camera framing — matches the Clash-style world view.
const CAMERA_PITCH := -50.0
const CAMERA_YAW := 40.0
const CAMERA_SIZE := 14.0

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

var _units: Array[CombatUnit] = []
var _dead_survivors: Array = []      # roster Survivors killed in this fight
var _zombies_killed: int = 0
var _xp_earned: int = 0
var _running: bool = false
var _squad: Array = []               # roster Survivors sent in

var _viewport: SubViewport
var _camera: Camera3D
var _arena_root: Node3D
var _root: Control
var _status_label: Label
var _ability_bar: HBoxContainer
var _abilities: Array = []           # {ability, button, cooldown_left, uses_left}


func _ready() -> void:
	layer = 85  # above HUD (80), below UIManager screens (90)
	_build_layout()


## Entry point, called by CombatManager.
## [param spec] = {"zombies": Array[CombatantDefinition]}.
func start(spec: Dictionary, squad: Array) -> void:
	_squad = squad
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Squad lines up on the left (−X), facing the horde.
	var survivors: Array = squad
	for i in survivors.size():
		var survivor = survivors[i]
		var role := DataManager.get_role(survivor.role)
		if role == null:
			role = DataManager.all_roles().front()
		var unit := _spawn_unit(CombatUnit.Team.SURVIVORS, role, survivor)
		unit.position = _row_position(-1, i, survivors.size())

	# Horde shambles in from the right (+X).
	var horde: Array = spec.get("zombies", [])
	for i in horde.size():
		var unit := _spawn_unit(CombatUnit.Team.ZOMBIES, horde[i])
		unit.position = Vector3(
			ARENA_HALF.x - 1.2 - rng.randf_range(0.0, 3.0), 0.0,
			rng.randf_range(-ARENA_HALF.y + 1.0, ARENA_HALF.y - 1.0))

	_running = true
	_update_status()

	# Degenerate roll (all ranges hit zero): nothing to fight — instant
	# victory instead of an arena that can never end.
	if team_units(CombatUnit.Team.ZOMBIES).is_empty():
		end_battle("victory")


## Even vertical spread along one side of the arena.
func _row_position(side: int, index: int, count: int) -> Vector3:
	var spread := ARENA_HALF.y * 1.4
	var z := 0.0 if count <= 1 else lerpf(-spread / 2.0, spread / 2.0, float(index) / float(count - 1))
	return Vector3(side * (ARENA_HALF.x - 1.5) + side * (index % 2) * 0.8, 0.0, z)


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


## Clamp a unit position to the arena floor (XZ plane, Y untouched).
func clamp_to_arena(pos: Vector3) -> Vector3:
	pos.x = clampf(pos.x, -ARENA_HALF.x + 0.5, ARENA_HALF.x - 0.5)
	pos.z = clampf(pos.z, -ARENA_HALF.y + 0.5, ARENA_HALF.y - 0.5)
	pos.y = 0.0
	return pos


## Floating combat text (damage, MISS, CRIT, heals, deaths). Takes a 3D
## world position and projects it onto the UI layer so the numbers read
## flat over the fight.
func spawn_popup(world_pos: Vector3, text: String, color: Color) -> void:
	if _camera == null:
		return
	var screen := _camera.unproject_position(world_pos)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)
	label.position = screen + Vector2(randf_range(-14, 14), -18)
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
	_arena_root.add_child(unit)
	unit.setup(self, team, def, survivor)
	unit.died.connect(_on_unit_died)
	_units.append(unit)
	return unit


func _on_unit_died(unit: CombatUnit) -> void:
	_units.erase(unit)
	spawn_popup(unit.global_position + Vector3(0, 0.5, 0), "💀", Color(0.9, 0.9, 0.9))
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


# ── Layout: 3D arena viewport + UI overlay ───────────────────────────────

func _build_layout() -> void:
	# Opaque backdrop so the frozen world doesn't bleed through.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.05, 0.06, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var vp_container := SubViewportContainer.new()
	vp_container.stretch = true
	vp_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vp_container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	vp_container.add_child(_viewport)

	_arena_root = Node3D.new()
	_viewport.add_child(_arena_root)
	_build_arena_environment()

	# UI overlay above the viewport.
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

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


## Ground plane, angled orthographic camera, sun + ambient light.
func _build_arena_environment() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = ARENA_HALF * 2.0 + Vector2(2, 2)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.28, 0.26, 0.22)
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	_arena_root.add_child(ground)

	# Brass border strip so the arena reads as a bounded pit.
	var border := MeshInstance3D.new()
	var border_mesh := PlaneMesh.new()
	border_mesh.size = ARENA_HALF * 2.0 + Vector2(2.4, 2.4)
	border.mesh = border_mesh
	var border_mat := StandardMaterial3D.new()
	border_mat.albedo_color = UIStyle.BRASS.darkened(0.35)
	border.material_override = border_mat
	border.position.y = -0.02
	_arena_root.add_child(border)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAMERA_SIZE
	_camera.rotation_degrees = Vector3(CAMERA_PITCH, CAMERA_YAW, 0)
	_camera.position = _camera.transform.basis.z * 60.0
	_camera.near = 1.0
	_camera.far = 200.0
	_arena_root.add_child(_camera)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	_arena_root.add_child(sun)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.06, 0.06, 0.08)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.72, 0.72)
	environment.ambient_light_energy = 0.6
	env.environment = environment
	_arena_root.add_child(env)


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
