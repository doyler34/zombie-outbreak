class_name RecipeDefinition
extends Resource
## Defines one crafting recipe.
##
## To add a recipe, create a .tres in data/recipes/ — DataManager
## discovers it and the crafting screen lists it automatically. All
## display information (icon, name, description) comes from the result
## item's ItemDefinition, so a recipe is nothing but ingredients → item.
##
## Future hooks are data, not code: `station` stays "" until crafting
## stations land (a workbench just filters recipes by its station tag),
## and `unlocked_from_start` mirrors the buildings' research gate.

## Unique id (usually matches the result item).
@export var id: String = ""
## ItemDefinition.id this recipe produces.
@export var result_item: String = ""
@export var result_count: int = 1
## Ingredients consumed from the Commander's inventory: {item_id: count}.
@export var ingredients: Dictionary = {}
## Order in the crafting list (lower = earlier).
@export var sort_order: int = 100

@export_group("Future Hooks")
## Required crafting station id ("" = craftable by hand anywhere).
@export var station: String = ""
## Hidden from the list until a research system unlocks it.
@export var unlocked_from_start: bool = true


func result_definition() -> ItemDefinition:
	return DataManager.get_item(result_item)
