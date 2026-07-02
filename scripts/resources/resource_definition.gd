class_name ResourceDefinition
extends Resource
## Defines one player resource type (wood, stone, food, ...).
##
## To add a new resource to the game, create a new .tres in
## data/resources/ using this script — no code changes required.
## DataManager discovers it automatically and ResourceManager, the HUD
## and cost displays all pick it up.

## Unique id used in costs, production tables and save files.
@export var id: String = ""
@export var display_name: String = ""
## Emoji/text icon shown in the HUD and cost rows.
@export var icon: String = "❔"
@export var icon_color: Color = Color.WHITE
## Amount the player starts a new game with.
@export var starting_amount: int = 0
## Storage cap. 0 means unlimited.
@export var max_storage: int = 0
## Order in HUD displays (lower = further left).
@export var sort_order: int = 100
