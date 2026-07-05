class_name CombatantDefinition
extends Resource
## Shared stat block for anything that fights — survivor roles and
## zombies both extend this, so combat code has exactly one interface.
##
## Future gear (weapons, armour pieces, buffs) should MODIFY these values
## at runtime through a stats snapshot, not add parallel fields here.

@export var id: String = ""
@export var display_name: String = ""
## Glyph shown next to the unit's name in squad select / results.
@export var icon: String = "●"
## Zombies: multiplied over the model's texture as a tint (sickly greens
## etc). Survivor roles keep their model's natural look — untinted.
@export var color: Color = Color.WHITE
## 3D character model (imported .glb) fought with in the battle arena.
## When empty, ModelFactory falls back to a simple capsule placeholder.
@export var model: PackedScene
## Uniform scale applied to the model. 0 = use as authored.
@export var model_scale: float = 0.0

@export_group("Stats")
@export var max_health: int = 100
@export var damage: int = 10
## Seconds between attacks.
@export var attack_interval: float = 1.0
## Attack reach in battle-arena pixels.
@export var attack_range: float = 40.0
## Movement speed in battle-arena pixels/second.
@export var move_speed: float = 80.0
## Flat damage reduction per hit (min 1 damage always goes through).
@export var armor: int = 0
## 0..1 chance to deal double damage.
@export var crit_chance: float = 0.05
## 0..1 chance to ignore an incoming hit.
@export var dodge_chance: float = 0.05
