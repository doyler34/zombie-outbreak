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

@export_group("Weapon")
## Weapon model (imported .fbx/.glb) attached to the character's hand.
## Empty = unarmed. Purely cosmetic for now; damage still comes from the
## role's stats (a WeaponDefinition with its own stats can come later).
@export var weapon: PackedScene
## Skeleton bone the weapon rides. Kenney mini-characters have single-bone
## arms; "arm-right" is the armed hand.
@export var weapon_bone: String = "arm-right"
## Placement of the weapon relative to the bone, in the bone's local
## space. These are eyeball knobs — tune per weapon in the .tres.
@export var weapon_offset: Vector3 = Vector3.ZERO
@export var weapon_rotation: Vector3 = Vector3.ZERO  # Euler degrees
@export var weapon_scale: float = 1.0
