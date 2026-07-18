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
## Cell borders walled off by base pieces: Vector3i(x, z, axis) -> Node.
## Axis 0 = border along X at the cell's -Z side, 1 = along Z at -X
## (see PiecePlacement). Movement code asks is_move_allowed().
var _blocked_edges: Dictionary = {}
## Elevation source registered by the world scene (null = flat world).
var _heightfield: Heightfield = null


func reset() -> void:
	_occupancy.clear()
	_blocked_edges.clear()
	_cell_surfaces.clear()


# ── Elevation ────────────────────────────────────────────────────────────

## Registered by WorldDecorator once the region's terrain is built;
## everything that stands on the ground asks here so gameplay and the
## rendered terrain can never disagree.
func set_heightfield(heightfield: Heightfield) -> void:
	_heightfield = heightfield


func ground_height(world_pos: Vector3) -> float:
	if _heightfield == null:
		return 0.0
	return _heightfield.height_at(Vector2(world_pos.x, world_pos.z))


# ── Standing surfaces (base-piece decks on top of the terrain) ───────────
## BaseManager registers each foundation's deck height per cell, so
## characters stand ON player-built floors instead of wading through
## them. Kept here so movement code has a single elevation authority.

var _cell_surfaces: Dictionary = {}  # Vector2i -> deck height (m)


func set_cell_surface(cell: Vector2i, height: float) -> void:
	_cell_surfaces[cell] = height


func clear_cell_surface(cell: Vector2i) -> void:
	_cell_surfaces.erase(cell)


## Terrain height plus any built deck at this position — where feet go.
func stand_height(world_pos: Vector3) -> float:
	return ground_height(world_pos) \
		+ float(_cell_surfaces.get(world_to_cell(world_pos), 0.0))


# ── Grid math ────────────────────────────────────────────────────────────
# Cells are 2D indices; world positions are Vector3 on the XZ ground
# plane (cell.x → world X, cell.y → world Z, Y from ground_height).

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


## Corner of a cell (minimum X/Z), resting on the ground.
func cell_to_world(cell: Vector2i) -> Vector3:
	var pos := Vector3(cell.x * cell_size(), 0.0, cell.y * cell_size())
	pos.y = ground_height(pos)
	return pos


## Center of a footprint whose corner cell is [param cell], resting on
## the ground — so everything placed by cell is automatically at the
## right elevation.
func area_center(cell: Vector2i, size_in_cells: Vector2i) -> Vector3:
	var pos := Vector3(
		cell.x * cell_size() + size_in_cells.x * cell_size() / 2.0,
		0.0,
		cell.y * cell_size() + size_in_cells.y * cell_size() / 2.0)
	pos.y = ground_height(pos)
	return pos


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


# ── Edge blocking (thin walls between walkable cells) ────────────────────

func block_edge(edge: Vector3i, blocker: Node) -> void:
	_blocked_edges[edge] = blocker


func unblock_edge(edge: Vector3i) -> void:
	_blocked_edges.erase(edge)


func is_edge_blocked(edge: Vector3i) -> bool:
	return _blocked_edges.has(edge)


## Can a ground unit step from one cell into an adjacent one? True when
## the target is walkable AND no wall-type piece blocks the shared
## border. Same-cell moves are always allowed; axis-separated movement
## (Commander, NPCs) never produces diagonals.
func is_move_allowed(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if not is_cell_walkable(to_cell):
		return false
	var step := to_cell - from_cell
	if step == Vector2i.ZERO:
		return true
	if step.x != 0:
		var x := maxi(from_cell.x, to_cell.x)
		if _blocked_edges.has(Vector3i(x, from_cell.y, 1)):
			return false
	if step.y != 0:
		var z := maxi(from_cell.y, to_cell.y)
		if _blocked_edges.has(Vector3i(from_cell.x, z, 0)):
			return false
	return true
