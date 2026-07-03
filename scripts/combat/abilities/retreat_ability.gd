class_name RetreatAbility
extends CombatAbility
## Retreat — pull the squad out immediately. Everyone still standing
## keeps their current wounds; no rewards; the danger zone remains.


func _init() -> void:
	id = "retreat"
	display_name = "RETREAT"
	icon = "🏳"
	cooldown = 0.0


func execute(battle: Node) -> bool:
	battle.end_battle("retreat")
	return true
