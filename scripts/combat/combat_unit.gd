class_name CombatUnit
extends Node3D
## One unit in the 3D battle arena — survivor or zombie, the same code.
##
## Fully automatic: acquire the nearest enemy, walk into range, attack on
## a cooldown. Medics (heal_power > 0) tend the most injured ally instead
## while anyone is hurt. All stats come from a CombatantDefinition, so
## new roles/zombie types change behaviour through data alone.
##
## Visual is a real character model (ModelFactory.combatant_model) driven
## by whatever AnimationPlayer the imported .glb carries — clip names
## are resolved per rig from candidate lists (Kenney's "idle"/"die",
## the shared libraries' "Idle_Loop"/"Death01", the zombie set...).
## A billboard health bar and floating combat text are built by hand
## (no textures needed for those).

# Param untyped on purpose: a signal typing a parameter with the class
# it is declared in is a self-reference some Godot versions reject.
signal died(unit)

enum Team { SURVIVORS, ZOMBIES }

const BAR_WIDTH := 0.7
const BAR_HEIGHT := 0.08
const DEATH_LINGER := 0.9

## Clip-name candidates covering every rig in the roster: Kenney minis
## ("idle"/"attack-melee-right"...), the shared animation libraries
## ("Idle_Loop"/"Punch_Cross"...) and their zombie set. Resolved per
## unit in setup() — zombies prefer their shamble/scratch clips.
const ATTACK_CANDIDATES: Array[String] = ["attack-melee-right", "Punch_Cross", "Sword_Attack", "Melee_Hook"]
const DIE_CANDIDATES: Array[String] = ["die", "Death01", "Hit_Knockback"]

var _anim_idle := ""
var _anim_walk := ""
var _anim_attack := ""
var _anim_die := ""

var team: Team
var stats: CombatantDefinition
var hp: int
## The roster Survivor this unit represents (null for zombies) — lets the
## mission result map battle damage back onto the settlement.
var survivor  # SurvivorManager.Survivor

var _battle: Node  # BattleScene — provides target queries + spawn_popup
var _cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()
var _anim_player: AnimationPlayer
var _dying: bool = false
## While a one-shot clip (attack/die) is mid-play, movement animations
## must not interrupt it — otherwise the attack shows for a single frame.
var _oneshot_active: bool = false
## Playback speed so a fixed-length attack clip keeps pace with the
## watch-speed toggle and matches the attack cooldown.
var _anim_speed: float = 1.0

var _health_fill: MeshInstance3D


func setup(battle: Node, unit_team: Team, definition: CombatantDefinition, roster_survivor = null) -> void:
	_battle = battle
	team = unit_team
	stats = definition
	hp = definition.max_health
	survivor = roster_survivor
	_rng.randomize()

	var model := ModelFactory.combatant_model(definition)
	add_child(model)
	if definition is SurvivorRoleDefinition and definition.weapon != null:
		ModelFactory.attach_weapon(model, definition.weapon, definition.model_scale,
			definition.weapon_bone, definition.weapon_offset, definition.weapon_rotation,
			definition.weapon_length)
	_anim_player = ModelFactory.find_animation_player(model)
	_resolve_anims(definition is ZombieDefinition)
	if _anim_player != null:
		# One-shot clips must not loop, or animation_finished never fires
		# and the unit freezes mid-swing.
		_force_no_loop(_anim_attack)
		_force_no_loop(_anim_die)
		_anim_player.animation_finished.connect(_on_anim_finished)
	_play_anim(_anim_idle)

	_build_health_bar(ModelFactory.model_height(model))


## Pick this unit's clips from what its rig actually ships. Zombies try
## their dedicated shamble/scratch set first, then the shared names.
func _resolve_anims(zombie: bool) -> void:
	_anim_idle = _resolve(zombie, "Zombie_Idle_Loop", ModelFactory.IDLE_CANDIDATES)
	_anim_walk = _resolve(zombie, "Zombie_Walk_Fwd_Loop", ModelFactory.WALK_CANDIDATES)
	_anim_attack = _resolve(zombie, "Zombie_Scratch", ATTACK_CANDIDATES)
	_anim_die = _resolve(zombie, "", DIE_CANDIDATES)


func _resolve(zombie: bool, zombie_clip: String, base: Array[String]) -> String:
	var candidates: Array[String] = []
	if zombie and zombie_clip != "":
		candidates.append(zombie_clip)
	candidates.append_array(base)
	return ModelFactory.find_anim(_anim_player, candidates)


func _force_no_loop(anim_name: String) -> void:
	if anim_name != "" and _anim_player.has_animation(anim_name):
		_anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_NONE


func _on_anim_finished(anim_name: StringName) -> void:
	if String(anim_name) == _anim_attack:
		_oneshot_active = false


func is_alive() -> bool:
	return hp > 0 and not _dying


func _process(delta: float) -> void:
	if not is_alive() or not _battle.is_running():
		return
	# combat_speed is the battle's watch-speed toggle (1x/2x/3x). Keep the
	# animation playback in step so fast-forward looks right.
	if _anim_player != null and not is_equal_approx(_anim_player.speed_scale, _current_anim_speed()):
		_anim_player.speed_scale = _current_anim_speed()
	delta *= _battle.combat_speed
	_cooldown = maxf(_cooldown - delta, 0.0)

	# Medic behaviour: while an ally is hurt, heal instead of fighting.
	if stats is SurvivorRoleDefinition and stats.heal_power > 0:
		var patient: CombatUnit = _battle.most_injured_ally(self)
		if patient != null:
			_pursue(patient, delta, func(): patient.heal(stats.heal_power))
			return

	var target: CombatUnit = _battle.nearest_enemy(self)
	if target != null:
		_pursue(target, delta, func(): _attack(target))


## Move toward [param other] until in range, then run [param action] on
## the attack cooldown. Movement is on the XZ ground plane (Y stays 0).
func _pursue(other: CombatUnit, delta: float, action: Callable) -> void:
	var to_other := other.position - position
	to_other.y = 0.0
	var distance := to_other.length()
	if distance > stats.attack_range:
		var dir := to_other / distance
		position += dir * stats.move_speed * delta
		position = _battle.clamp_to_arena(position)
		_face(dir)
		_play_anim(_anim_walk)
	else:
		if distance > 0.05:
			_face(to_other / distance)
		if _cooldown <= 0.0:
			_cooldown = stats.attack_interval
			action.call()
		elif not _oneshot_active:
			_play_anim(_anim_idle)


func _face(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	# Kenney mini-characters model forward as +Z; look_at aims −Z at the
	# target, so aim at the point behind to face the travel direction.
	look_at(global_position - dir, Vector3.UP)


func _attack(target: CombatUnit) -> void:
	_play_oneshot(_anim_attack)
	var dmg := stats.damage
	var crit := _rng.randf() < stats.crit_chance
	if crit:
		dmg *= 2
	target.take_damage(dmg, crit)


func take_damage(amount: int, crit: bool = false) -> void:
	if not is_alive():
		return
	if _rng.randf() < stats.dodge_chance:
		_battle.spawn_popup(_popup_origin(), "MISS", Color(0.7, 0.7, 0.7))
		return
	var dealt := maxi(amount - stats.armor, 1)
	hp -= dealt
	if crit:
		_battle.spawn_popup(_popup_origin(), "CRIT %d" % dealt, Color(1.0, 0.85, 0.2))
	else:
		_battle.spawn_popup(_popup_origin(), str(dealt), Color(1.0, 0.45, 0.35))
	_update_health_bar()
	if hp <= 0:
		hp = 0
		died.emit(self)
		_die()


func heal(amount: int) -> void:
	if not is_alive():
		return
	var before := hp
	hp = mini(hp + amount, stats.max_health)
	if hp > before:
		_battle.spawn_popup(_popup_origin(), "+%d" % (hp - before), Color(0.45, 0.9, 0.4))
	_update_health_bar()


func _die() -> void:
	# died.emit() already fired above (battle end-checks time off it);
	# only visuals are delayed so the death animation gets to play.
	_dying = true
	# Death overrides any in-progress swing.
	_oneshot_active = false
	_play_oneshot(_anim_die)
	if _health_fill != null:
		_health_fill.get_parent().visible = false
	var tw := create_tween()
	tw.tween_interval(DEATH_LINGER)
	tw.tween_callback(queue_free)


# ── Health bar (billboard quads) ─────────────────────────────────────────

func _build_health_bar(model_height: float) -> void:
	var bar_root := Node3D.new()
	bar_root.position = Vector3(0, model_height + 0.18, 0)
	add_child(bar_root)

	var bg := MeshInstance3D.new()
	bg.mesh = _bar_quad(BAR_WIDTH, BAR_HEIGHT)
	bg.material_override = _billboard_material(Color(0, 0, 0, 0.7))
	bar_root.add_child(bg)

	_health_fill = MeshInstance3D.new()
	_health_fill.mesh = _bar_quad(BAR_WIDTH, BAR_HEIGHT)
	var fill_color := Color(0.35, 0.8, 0.3) if team == Team.SURVIVORS else Color(0.8, 0.3, 0.25)
	_health_fill.material_override = _billboard_material(fill_color)
	_health_fill.position.z = 0.005  # avoid z-fighting with the background
	bar_root.add_child(_health_fill)


func _update_health_bar() -> void:
	if _health_fill == null:
		return
	var ratio := clampf(float(hp) / float(stats.max_health), 0.0, 1.0)
	_health_fill.scale.x = maxf(ratio, 0.001)
	_health_fill.position.x = -BAR_WIDTH * (1.0 - ratio) / 2.0


func _bar_quad(width: float, height: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(width, height)
	return q


func _billboard_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	return mat


func _popup_origin() -> Vector3:
	return global_position + Vector3(0, 0.3, 0)


# ── Animation ────────────────────────────────────────────────────────────

## Play a looping locomotion clip (idle/walk). Never interrupts an active
## one-shot (attack/die) or restarts a clip that is already playing.
func _play_anim(anim_name: String) -> void:
	if _anim_player == null or _oneshot_active:
		return
	if not _anim_player.has_animation(anim_name):
		return
	if _anim_player.current_animation == anim_name:
		return
	_anim_player.play(anim_name)


## Play a protected one-shot clip. _on_anim_finished clears the lock for
## attack; die stays locked (the unit is freed shortly after).
func _play_oneshot(anim_name: String) -> void:
	if _anim_player == null or not _anim_player.has_animation(anim_name):
		return
	_oneshot_active = true
	_anim_player.play(anim_name)


## Attack clips are fixed-length; scale playback so one plays within the
## attack cooldown (and with the watch-speed toggle) instead of lagging.
func _current_anim_speed() -> float:
	var speed: float = _battle.combat_speed
	if _oneshot_active and _anim_attack != "" and _anim_player.has_animation(_anim_attack):
		var clip_len := _anim_player.get_animation(_anim_attack).length
		if clip_len > 0.01 and stats.attack_interval > 0.01:
			# Fit the swing into ~80% of the cooldown window.
			speed *= maxf(clip_len / (stats.attack_interval * 0.8), 1.0)
	return speed
