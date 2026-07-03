class_name SurvivorRoleDefinition
extends CombatantDefinition
## A survivor combat role (Fighter, Scavenger, Medic, ...). One .tres per
## role in data/roles/ — new roles are pure data unless they need a new
## behaviour hook like heal_power.

@export_group("Role Bonuses")
## Extra mission loot fraction this role contributes (Scavenger: 0.25
## = +25%). Bonuses from multiple squad members stack additively.
@export var loot_bonus: float = 0.0
## Extra mission reward fraction (Engineer). Same stacking rule.
@export var reward_bonus: float = 0.0
## If > 0 this unit heals injured allies (per attack tick) instead of
## fighting while anyone is hurt (Medic).
@export var heal_power: int = 0
