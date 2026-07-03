class_name CombatUnit
extends Node2D
## One unit in the battle arena — survivor or zombie, the same code.
##
## Fully automatic: acquire the nearest enemy, walk into range, attack on
## a cooldown. Medics (heal_power > 0) tend the most injured ally instead
## while anyone is hurt. All stats come from a CombatantDefinition, so
## new roles/zombie types change behaviour through data alone.
##
## Visuals are drawn in _draw (colored disc + health bar) with a glyph
## label — no textures needed for the prototype; swapping in animated
## sprites later only touches this file.

# Param untyped on purpose: a signal typing a parameter with the class
# it is declared in is a self-reference some Godot versions reject.
signal died(unit)

enum Team { SURVIVORS, ZOMBIES }

const BODY_RADIUS := 18.0

var team: Team
var stats: CombatantDefinition
var hp: int
## The roster Survivor this unit represents (null for zombies) — lets the
## mission result map battle damage back onto the settlement.
var survivor  # SurvivorManager.Survivor

var _battle: Node  # BattleScene — provides target queries
var _cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup(battle: Node, unit_team: Team, definition: CombatantDefinition, roster_survivor = null) -> void:
	_battle = battle
	team = unit_team
	stats = definition
	hp = definition.max_health
	survivor = roster_survivor
	_rng.randomize()

	var glyph := Label.new()
	glyph.text = definition.icon
	glyph.add_theme_font_size_override("font_size", 18)
	glyph.position = Vector2(-11, -14)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glyph)


func is_alive() -> bool:
	return hp > 0


func _process(delta: float) -> void:
	if not is_alive() or not _battle.is_running():
		return
	# combat_speed is the battle's watch-speed toggle (1x/2x/3x).
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
## the attack cooldown.
func _pursue(other: CombatUnit, delta: float, action: Callable) -> void:
	var distance := position.distance_to(other.position)
	if distance > stats.attack_range:
		position += position.direction_to(other.position) * stats.move_speed * delta
		position = _battle.clamp_to_arena(position)
	elif _cooldown <= 0.0:
		_cooldown = stats.attack_interval
		action.call()


func _attack(target: CombatUnit) -> void:
	var dmg := stats.damage
	var crit := _rng.randf() < stats.crit_chance
	if crit:
		dmg *= 2
	# Quick lunge toward the target so attacks read on screen.
	var punch := position.direction_to(target.position) * 12.0
	var tween := create_tween()
	tween.tween_property(self, "position", punch, 0.07).as_relative()
	tween.tween_property(self, "position", -punch, 0.09).as_relative()
	target.take_damage(dmg, crit)


func take_damage(amount: int, crit: bool = false) -> void:
	if not is_alive():
		return
	if _rng.randf() < stats.dodge_chance:
		_battle.spawn_popup(position, "MISS", Color(0.7, 0.7, 0.7))
		return
	var dealt := maxi(amount - stats.armor, 1)
	hp -= dealt
	if crit:
		_battle.spawn_popup(position, "CRIT %d" % dealt, Color(1.0, 0.85, 0.2))
	else:
		_battle.spawn_popup(position, str(dealt), Color(1.0, 0.45, 0.35))
	queue_redraw()
	if hp <= 0:
		hp = 0
		died.emit(self)
		queue_free()


func heal(amount: int) -> void:
	if not is_alive():
		return
	var before := hp
	hp = mini(hp + amount, stats.max_health)
	if hp > before:
		_battle.spawn_popup(position, "+%d" % (hp - before), Color(0.45, 0.9, 0.4))
	queue_redraw()


func _draw() -> void:
	# Body disc with a darker rim.
	draw_circle(Vector2.ZERO, BODY_RADIUS, stats.color.darkened(0.35))
	draw_circle(Vector2.ZERO, BODY_RADIUS - 3.0, stats.color)
	# Health bar above the unit.
	var ratio := float(hp) / float(stats.max_health)
	var bar := Rect2(-20, -BODY_RADIUS - 14, 40, 6)
	draw_rect(bar, Color(0, 0, 0, 0.7))
	var fill_color := Color(0.35, 0.8, 0.3) if team == Team.SURVIVORS else Color(0.8, 0.3, 0.25)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), fill_color)
