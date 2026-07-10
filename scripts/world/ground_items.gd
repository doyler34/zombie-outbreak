class_name GroundItems
extends Node3D
## Container + spawner for loose world pickups (GroundItem).
##
## Three ways items land on the ground:
##  - world generation scatters starter pickups on a NEW map (the
##    "ground_items" section of data/tables/world_generation.json;
##    GameManager triggers scatter_initial for fresh worlds only)
##  - the player drops a slot (EventBus.item_dropped → at the
##    Commander's feet)
##  - future systems (zombie loot, airdrops) call spawn() directly.
## Pickups are not persisted yet — see GroundItem's header.

## How far (cells) from the map centre starter pickups scatter.
const SCATTER_RADIUS := 14


func _ready() -> void:
	add_to_group("ground_items")
	EventBus.item_dropped.connect(_on_item_dropped)


## Drop a pickup into the world at a position (snapped to the ground).
func spawn(item_id: String, count: int, world_pos: Vector3) -> GroundItem:
	if DataManager.get_item(item_id) == null:
		push_warning("[GroundItems] Unknown item id: %s" % item_id)
		return null
	var pickup := GroundItem.new()
	add_child(pickup)
	pickup.setup(item_id, count)
	pickup.position = Vector3(world_pos.x,
		WorldManager.ground_height(world_pos), world_pos.z)
	return pickup


## Starter pickups for a fresh map, from world_generation.json:
##   "ground_items": [{"id": "scrap", "count": 2, "nodes": 5}, ...]
## Each entry spawns `nodes` pickups of `count` units on random walkable
## cells near the centre. Called by GameManager for new games only
## (loaded games would duplicate — pickups aren't saved).
func scatter_initial() -> void:
	var table: Variant = DataManager.get_table("world_generation")
	if table == null or not (table is Dictionary):
		return
	var entries: Array = table.get("ground_items", [])
	for entry in entries:
		var id := String(entry.get("id", ""))
		var per := int(entry.get("count", 1))
		for _n in int(entry.get("nodes", 0)):
			var cell := _random_free_cell()
			if cell != Vector2i(-9999, -9999):
				spawn(id, per, WorldManager.area_center(cell, Vector2i.ONE))


func _on_item_dropped(item_id: String, count: int) -> void:
	var commander := get_tree().get_first_node_in_group("commander") as Node3D
	if commander == null:
		return
	# A step in front of a random side, so stacked drops don't overlap.
	var angle := randf() * TAU
	var offset := Vector3(cos(angle), 0, sin(angle)) * 1.2
	spawn(item_id, count, commander.global_position + offset)


func _random_free_cell() -> Vector2i:
	for _attempt in 24:
		var cell := Vector2i(
			randi_range(-SCATTER_RADIUS, SCATTER_RADIUS),
			randi_range(-SCATTER_RADIUS, SCATTER_RADIUS))
		if WorldManager.is_cell_walkable(cell):
			return cell
	return Vector2i(-9999, -9999)
