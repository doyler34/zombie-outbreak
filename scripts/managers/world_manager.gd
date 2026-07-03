extends Node
## WorldManager — grid math and tile occupancy (autoload).
##
## The world is a uniform grid of square cells (size from GameSettings).
## This manager is the single source of truth for:
##  - coordinate conversion (world px ↔ grid cell)
##  - which cells are occupied, and by what
##  - world bounds (used by the camera and placement)
##
## It deliberately knows nothing about WHAT occupies a cell beyond a Node
## reference — buildings, future props and blockers all use the same API.

var _occupancy: Dictionary = {}  # Vector2i -> Node


func reset() -> void:
	_occupancy.clear()


# ── Grid math ────────────────────────────────────────────────────────────
# Cells are 2D indices; world positions are Vector3 on the XZ ground
# plane (cell.x → world X, cell.y → world Z, ground at Y = 0).

func cell_size() -> float:
	return DataManager.settings.cell_size


## World bounds on the XZ plane in meters, centered on the origin.
func world_rect() -> Rect2:
	var size := Vector2(DataManager.settings.world_size) * cell_size()
	return Rect2(-size / 2.0, size)


func world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / cell_size()),
		floori(world_pos.z / cell_size()))


## Corner of a cell (minimum X/Z), on the ground plane.
func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * cell_size(), 0.0, cell.y * cell_size())


## Center of a footprint whose corner cell is [param cell].
func area_center(cell: Vector2i, size_in_cells: Vector2i) -> Vector3:
	return cell_to_world(cell) + Vector3(
		size_in_cells.x * cell_size() / 2.0, 0.0, size_in_cells.y * cell_size() / 2.0)


func is_cell_inside_world(cell: Vector2i) -> bool:
	var half := DataManager.settings.world_size / 2
	return cell.x >= -half.x and cell.x < half.x \
		and cell.y >= -half.y and cell.y < half.y


# ── Occupancy ────────────────────────────────────────────────────────────

func is_area_free(cell: Vector2i, size_in_cells: Vector2i) -> bool:
	for x in size_in_cells.x:
		for y in size_in_cells.y:
			var c := cell + Vector2i(x, y)
			if not is_cell_inside_world(c) or _occupancy.has(c):
				return false
	return true


## Like is_area_free, but occupants that don't block building (decorative
## props, walkable rubble) don't count. Building placement uses this;
## raw spawning uses is_area_free.
func is_area_buildable(cell: Vector2i, size_in_cells: Vector2i) -> bool:
	for x in size_in_cells.x:
		for y in size_in_cells.y:
			var c := cell + Vector2i(x, y)
			if not is_cell_inside_world(c):
				return false
			var occupant: Node = _occupancy.get(c)
			if occupant == null:
				continue
			# Occupants without the contract block by default (buildings).
			if not occupant.has_method("blocks_building") or occupant.blocks_building():
				return false
	return true


## For the future movement/pathfinding system: can a unit stand here?
func is_cell_walkable(cell: Vector2i) -> bool:
	if not is_cell_inside_world(cell):
		return false
	var occupant: Node = _occupancy.get(cell)
	if occupant == null:
		return true
	return occupant.has_method("blocks_movement") and not occupant.blocks_movement()


func occupy_area(cell: Vector2i, size_in_cells: Vector2i, occupant: Node) -> void:
	for x in size_in_cells.x:
		for y in size_in_cells.y:
			_occupancy[cell + Vector2i(x, y)] = occupant


func vacate_area(cell: Vector2i, size_in_cells: Vector2i) -> void:
	for x in size_in_cells.x:
		for y in size_in_cells.y:
			_occupancy.erase(cell + Vector2i(x, y))


## The node occupying [param cell], or null.
func occupant_at(cell: Vector2i) -> Node:
	return _occupancy.get(cell)
