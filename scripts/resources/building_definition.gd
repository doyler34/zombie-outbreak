class_name BuildingDefinition
extends Resource
## Defines one building type, fully data-driven.
##
## To add a new building, create a .tres in data/buildings/ using this
## script. DataManager discovers it automatically; the build menu,
## placement system, production and save system all work from this data.

## Unique id used in save files and lookups.
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Icon shown in the build menu.
@export var texture: Texture2D
## Path to the 3D model (imported .glb), loaded lazily at spawn time.
## Stored as a PATH, not a PackedScene ext_resource, on purpose: a model
## that fails to load (e.g. a missing external texture in an exported
## build) must NOT drop the whole building from the data — the building
## still appears in the menu and falls back to the placeholder in-world.
@export var model_path: String = ""
## Uniform scale applied to the model. 0 = auto-fit to the grid
## footprint (the default for normalized AI exports); set an explicit
## value when an asset should be larger or smaller than its plot.
@export var model_scale: float = 0.0
## Placeholder color used when no model is assigned or it fails to load.
@export var color: Color = Color(0.55, 0.45, 0.35)
## Footprint on the grid, in cells.
@export var grid_size: Vector2i = Vector2i(2, 2)
## Highest level this building can be upgraded to.
@export var max_level: int = 1
## Real-time seconds to construct (and to upgrade one level).
@export var build_time: float = 10.0
## Whether this building appears in the build menu from the start.
## Locked buildings are the hook for a future research/tech system.
@export var unlocked_from_start: bool = true
## Order in the build menu (lower = first).
@export var sort_order: int = 100

@export_group("Economy")
## Cost to build level 1, e.g. {"wood": 60, "stone": 40}.
@export var base_cost: Dictionary = {}
## Additional cost per level above 1, e.g. {"wood": 40}.
@export var cost_per_level: Dictionary = {}
## Resources generated per in-game day at level 1,
## e.g. {"food": 6}. Scales with production_per_level.
@export var production: Dictionary = {}
## Added to production for each level above 1.
@export var production_per_level: Dictionary = {}

@export_group("Effects")
## Passive stat contributions at level 1,
## e.g. {"population_cap": 6, "defense": 3}.
@export var effects: Dictionary = {}
## Added to effects for each level above 1.
@export var effects_per_level: Dictionary = {}


## Total cost to reach [param level] from the level below it.
func cost_for_level(level: int) -> Dictionary:
	var cost := base_cost.duplicate()
	if level > 1:
		for key in cost_per_level:
			cost[key] = cost.get(key, 0) + cost_per_level[key] * (level - 1)
	return cost


## Daily production at [param level].
func production_at_level(level: int) -> Dictionary:
	return _scaled(production, production_per_level, level)


## Passive effects at [param level].
func effects_at_level(level: int) -> Dictionary:
	return _scaled(effects, effects_per_level, level)


func _scaled(base: Dictionary, per_level: Dictionary, level: int) -> Dictionary:
	var out := base.duplicate()
	if level > 1:
		for key in per_level:
			out[key] = out.get(key, 0) + per_level[key] * (level - 1)
	return out
