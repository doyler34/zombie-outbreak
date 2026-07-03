class_name LocationDefinition
extends Resource
## One fixed location on the world map (Forest, Police Station, ...).
##
## Fully data-driven: a .tres in data/locations/ places itself on the
## map, defines its enemies/loot/travel time, and declares its unlock
## requirements. WorldMapManager builds the territory graph from these —
## adding a location never touches code.

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Marker glyph on the world map.
@export var icon: String = "📍"
## Danger rating 1 (Low) … 5 (Extreme); drives the threat label.
@export_range(1, 5) var difficulty: int = 1
## Position on the world map canvas (see WorldMapScreen.MAP_SIZE).
@export var map_position: Vector2 = Vector2.ZERO
## One-way travel time in real seconds of game time.
@export var travel_time: float = 20.0

@export_group("Mission")
## Zombie composition as ranges, e.g. {"walker": [3, 5], "runner": [0, 2]}.
@export var zombies: Dictionary = {}
## Victory loot ranges, e.g. {"wood": [20, 40]}.
@export var rewards: Dictionary = {}
## Flat XP on top of per-kill XP.
@export var bonus_xp: int = 0
## Chance (0..1) to bring home a rescued survivor on victory.
@export var rescue_chance: float = 0.0

@export_group("Territory")
## Location ids that must be cleared/controlled before this unlocks.
@export var requires: Array[String] = []
## If true, clearing makes this CONTROLLED (expands player territory)
## instead of just CLEARED.
@export var unlocks_territory: bool = false
## Future hook: passive income/bonuses while controlled,
## e.g. {"wood": 5} per day. Not consumed by any system yet.
@export var resource_bonus: Dictionary = {}

const THREAT_LABELS := ["Low", "Moderate", "High", "Severe", "Extreme"]


func threat_label() -> String:
	return THREAT_LABELS[clampi(difficulty, 1, 5) - 1]


## The generic mission spec consumed by CombatManager.
func to_mission_spec() -> Dictionary:
	return {
		"zombies": zombies,
		"rewards": rewards,
		"bonus_xp": bonus_xp,
		"rescue_chance": rescue_chance,
	}
