class_name ObstacleDefinition
extends Resource
## Defines one natural obstacle type (tree, rock, debris, ...).
##
## To add a new obstacle, create a .tres in data/obstacles/ — DataManager
## discovers it, world generation can spawn it (add it to
## data/tables/world_generation.json), and clearing/rewards/workers all
## work from this data. No code changes, ever.

## Unique id used in save files, lookups and the world-generation table.
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var texture: Texture2D
## Footprint on the grid, in cells.
@export var grid_size: Vector2i = Vector2i(1, 1)

@export_group("Blocking")
## Decorative objects set this false — they can never be removed.
@export var clearable: bool = true
## Whether this obstacle occupies build space.
@export var blocks_building: bool = true
## Whether units can walk through (for the future movement/pathfinding
## system — stored now so map data doesn't need migrating later).
@export var blocks_movement: bool = true

@export_group("Clearing")
## Resources consumed to start the clearing task, e.g. {"food": 5}.
@export var clear_cost: Dictionary = {}
## Resources granted when clearing completes, e.g. {"wood": 40}.
@export var clear_rewards: Dictionary = {}
## Base task duration in real-time seconds (with zero workers assigned).
@export var clear_time: float = 15.0
## Durability for future mechanics (combat, tools degrading, multi-stage
## demolition). Unused by the base clearing flow.
@export var health: int = 100

@export_group("Workers")
## Workers required before the task can start (0 = optional).
@export var min_workers: int = 0
## Most workers that can help at once.
@export var max_workers: int = 3
## Speed multiplier added per assigned worker:
## effective_time = clear_time / (1 + worker_time_bonus × workers).
@export var worker_time_bonus: float = 0.5

@export_group("Future Hooks")
## Technology id that must be researched before clearing ("" = none).
## Checked by ObstacleManager; the future research system just has to
## answer is_tech_unlocked().
@export var required_tech: String = ""
## In-game days until this obstacle regrows after clearing (0 = never).
## Vegetation like bushes can use this.
@export var regrow_days: int = 0
## Free-form behaviour markers for future systems, e.g. "infested"
## (triggers combat when clearing starts), "rare_node", "high_level".
@export var tags: Array[String] = []


## Task duration with [param workers] assigned.
func effective_clear_time(workers: int) -> float:
	return clear_time / (1.0 + worker_time_bonus * maxf(workers, 0))


func has_tag(tag: String) -> bool:
	return tags.has(tag)
