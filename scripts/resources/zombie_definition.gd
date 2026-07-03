class_name ZombieDefinition
extends CombatantDefinition
## A zombie enemy type. One .tres per type in data/zombies/; mission
## compositions in data/tables/missions.json reference these ids.

@export_group("Rewards")
## XP granted to the squad when this zombie is killed.
@export var xp_value: int = 10
