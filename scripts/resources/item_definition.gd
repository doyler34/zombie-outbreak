class_name ItemDefinition
extends Resource
## Defines one inventory item (material, consumable, weapon, tool, ...).
##
## To add a new item to the game, create a new .tres in data/items/
## using this script — no code changes required. DataManager discovers
## it automatically and the inventory, hotbar and pickup systems all
## pick it up. Future systems (combat damage, tool gathering power)
## read their numbers from here too, so an item's whole identity stays
## in its data file.

enum Type {
	MATERIAL,    ## Stackable crafting/building resource (wood, scrap...)
	CONSUMABLE,  ## Used from the hotbar; one is consumed per use.
	WEAPON,      ## Equippable; becomes the active weapon when selected.
	TOOL,        ## Equippable; becomes the active tool when selected.
	ARMOR,       ## Wearable protection (equip flow arrives with combat).
	GEAR,        ## Special usable equipment (flares, traps, keys...).
}

## Unique id used in save files, loot tables and stack merging.
@export var id: String = ""
@export var display_name: String = ""
## Emoji/text icon shown in slots and tooltips (same convention as
## ResourceDefinition — real icon art can replace this later).
@export var icon: String = "❔"
@export var icon_color: Color = Color.WHITE
@export_multiline var description: String = ""
@export var type: Type = Type.MATERIAL
## Max units per slot. 1 = non-stackable (weapons, tools, armor).
@export var max_stack: int = 1
## Order inside menus (lower = earlier).
@export var sort_order: int = 100

@export_group("Use Effects")
## Health restored when a CONSUMABLE is used (future health system;
## already consumed and reported today).
@export var heal_amount: int = 0

@export_group("Equip Stats")
## Damage dealt by a WEAPON (read by the future combat system).
@export var damage: int = 0
## Gathering power of a TOOL (read by the future gathering system).
@export var tool_power: int = 0


func is_stackable() -> bool:
	return max_stack > 1


## Can one be consumed/activated from the hotbar?
func is_usable() -> bool:
	return type == Type.CONSUMABLE or type == Type.GEAR


## Does selecting it in the hotbar equip it?
func is_equippable() -> bool:
	return type == Type.WEAPON or type == Type.TOOL


## What the hotbar accepts: quick-use and equippable items — raw
## materials and armor stay in the backpack.
func hotbar_allowed() -> bool:
	return type != Type.MATERIAL and type != Type.ARMOR


func type_name() -> String:
	match type:
		Type.MATERIAL: return "Material"
		Type.CONSUMABLE: return "Consumable"
		Type.WEAPON: return "Weapon"
		Type.TOOL: return "Tool"
		Type.ARMOR: return "Armor"
		Type.GEAR: return "Gear"
	return "Item"
