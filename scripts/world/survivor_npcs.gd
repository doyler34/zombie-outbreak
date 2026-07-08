class_name SurvivorNpcs
extends Node3D
## Spawns a SurvivorNPC in the base for every roster survivor.
##
## Purely presentational: rebuilt from SurvivorManager whenever the
## world loads or the population changes, so it can never drift from
## the roster (the same disposable-view philosophy as the rest of the
## world scene). NPCs cluster on walkable cells around the Capital —
## or the map centre until one is built — and don't occupy the grid.

## How far out (in rings of cells) to look for free standing spots.
const SEARCH_RADIUS := 10


func _ready() -> void:
	EventBus.world_ready.connect(_refresh)
	EventBus.population_changed.connect(func(_count: int, _cap: int): _refresh())


func _refresh() -> void:
	for child in get_children():
		child.queue_free()

	var spots := _standing_spots(_anchor_cell(), SurvivorManager.count())
	var index := 0
	for survivor in SurvivorManager.all():
		if survivor.on_mission or index >= spots.size():
			continue
		var npc := SurvivorNPC.new()
		add_child(npc)
		npc.setup(survivor)
		npc.position = spots[index]
		index += 1


# ── Internal ─────────────────────────────────────────────────────────────

func _anchor_cell() -> Vector2i:
	var hq: BuildingEntity = BuildingManager.first_of("safe_house")
	if hq != null:
		return WorldManager.world_to_cell(hq.global_position)
	return Vector2i.ZERO


## Up to [param wanted] walkable cell centres spiralling out from
## [param center], spaced out so NPCs don't stand shoulder to shoulder.
func _standing_spots(center: Vector2i, wanted: int) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for radius in range(1, SEARCH_RADIUS + 1):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				# Every other ring cell — breathing room between NPCs.
				if posmod(x + y, 2) != 0:
					continue
				var cell := center + Vector2i(x, y)
				if not WorldManager.is_cell_walkable(cell):
					continue
				spots.append(WorldManager.area_center(cell, Vector2i.ONE))
				if spots.size() >= wanted:
					return spots
	return spots
