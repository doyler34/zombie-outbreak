class_name HealAbility
extends CombatAbility
## Simple Heal — patches up every living survivor for a chunk of their
## missing health. The prototype's "keep the squad alive" button.

const HEAL_FRACTION := 0.35


func _init() -> void:
	id = "heal"
	display_name = "HEAL"
	icon = "➕"
	cooldown = 15.0
	max_uses = 2


func execute(battle: Node) -> bool:
	var healed_anyone := false
	for unit: CombatUnit in battle.team_units(CombatUnit.Team.SURVIVORS):
		if unit.is_alive() and unit.hp < unit.stats.max_health:
			unit.heal(int(unit.stats.max_health * HEAL_FRACTION))
			healed_anyone = true
	return healed_anyone
