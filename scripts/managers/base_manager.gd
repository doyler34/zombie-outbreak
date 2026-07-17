extends Node
## BaseManager — the modular base-building system (autoload).
##
## Owns everything about player-built structures made of BuildingPiece
## resources: build mode state, the piece occupancy maps (cells + edges
## per storey), the placement validator, the snap logic, spawning and
## persistence. Rendering/physics of one piece lives in BasePieceEntity;
## UI lives in BuildModeMenu; input/preview in BuildModeController — all
## of them talk to this manager and the EventBus only.
##
## The validator is socket-based (BuildingPiece.provides/requires), so
## new piece types — turrets, furniture, electricity — are new tokens and
## new .tres files, not new code paths. Nothing here references an
## individual asset.

## Vertical storeys available (ground floor = level 0).
const MAX_LEVELS := 3

var build_mode_active: bool = false

## Occupancy: Vector3i cell key -> BasePieceEntity (foundations, floors).
var _cells: Dictionary = {}
## Vector4i edge key -> BasePieceEntity (walls, windows, gates).
var _edges: Dictionary = {}
## Vector4i edge key -> BasePieceEntity door leafs filling doorways.
var _edge_fills: Dictionary = {}
var _entities: Array = []
## Set by the active GameWorld; parent for spawned piece nodes.
var _container: Node = null
## HQ build zone in grid cells, derived from the compound table.
var _zone: Rect2i
var _zone_ready := false


func _ready() -> void:
	SaveManager.register_section("base_pieces", self)


func register_container(container: Node) -> void:
	_container = container


func reset() -> void:
	exit_build_mode()
	for entity: BasePieceEntity in _entities:
		_unregister(entity)  # vacate cells, unblock nav edges
		entity.queue_free()
	_entities.clear()
	_cells.clear()
	_edges.clear()
	_edge_fills.clear()
	_container = null


# ── Build mode ───────────────────────────────────────────────────────────

## Enter build mode — only while the Commander stands inside the HQ
## build zone (LDoE-style base editing at home, not in the field).
func enter_build_mode() -> bool:
	if build_mode_active:
		return true
	if not is_commander_in_zone():
		EventBus.notify("Move inside the HQ compound to build.", 1)
		return false
	build_mode_active = true
	EventBus.build_mode_changed.emit(true)
	return true


func exit_build_mode() -> void:
	if not build_mode_active:
		return
	build_mode_active = false
	EventBus.build_mode_changed.emit(false)


func is_commander_in_zone() -> bool:
	var commander: Node3D = get_tree().get_first_node_in_group("commander")
	if commander == null:
		return false
	return zone_rect().has_point(WorldManager.world_to_cell(commander.global_position))


## The HQ build zone (grid cells): the interior of the compound
## perimeter, overridable with a "build_zone" block in the table.
func zone_rect() -> Rect2i:
	if not _zone_ready:
		var half := 6
		var table: Variant = DataManager.get_table("hq_compound")
		if table is Dictionary:
			half = int(table.get("build_zone", {}).get("half_extent",
				table.get("perimeter", {}).get("half_extent", half)))
		_zone = Rect2i(-half + 1, -half + 1, 2 * half - 1, 2 * half - 1)
		_zone_ready = true
	return _zone


# ── Snapping ─────────────────────────────────────────────────────────────

## The spot a piece wants under the cursor — the whole "never line
## pieces up by hand" feel lives here. Cell pieces snap to the hovered
## cell (floors/roofs climb to the storey their walls support); edge
## pieces snap to the nearest cell border ([param axis_lock] 0/1 filters
## to one direction — that's the rotate control); doors snap to the
## nearest open doorway. Returns a spot Dictionary (PiecePlacement).
func best_spot_for(piece: BuildingPiece, world_pos: Vector3, axis_lock: int = -1) -> Dictionary:
	var cell := WorldManager.world_to_cell(world_pos)
	if piece.needs("doorway"):
		return _nearest_doorway_spot(cell, world_pos)
	if piece.placement == "cell":
		var level := 0
		if piece.needs("roof_support"):
			level = _supported_level(cell, piece.grid_size)
			while _cell_area_occupied(cell, piece.grid_size, level) and level < MAX_LEVELS - 1:
				level += 1
		return {"placement": "cell", "cell": cell, "axis": 0, "level": level}
	var edge := PiecePlacement.nearest_edge(cell, world_pos, axis_lock)
	var level := 0
	while _edges.has(PiecePlacement.edge_key(edge, level)) and level < MAX_LEVELS - 1:
		level += 1
	return {"placement": "edge", "cell": cell, "edge": edge, "axis": edge.z, "level": level}


## Storey a floor/roof over [param cell] should sit at: one above the
## tallest supporting wall on its perimeter (no walls -> hovers at 1,
## reading as "needs walls" in red).
func _supported_level(cell: Vector2i, size: Vector2i) -> int:
	var top := 0
	for edge: Vector3i in _perimeter_edges(cell, size):
		for level in MAX_LEVELS:
			var occupant: BasePieceEntity = _edges.get(PiecePlacement.edge_key(edge, level))
			if occupant != null and occupant.piece.offers("roof_support"):
				top = maxi(top, level + 1)
	return maxi(top, 1)


func _nearest_doorway_spot(around: Vector2i, world_pos: Vector3) -> Dictionary:
	var flat := Vector3(world_pos.x, 0, world_pos.z)
	var best := {}
	var best_d := INF
	for x in range(around.x - 1, around.x + 2):
		for z in range(around.y - 1, around.y + 2):
			for edge: Vector3i in PiecePlacement.edges_of_cell(Vector2i(x, z)):
				for level in MAX_LEVELS:
					var key := PiecePlacement.edge_key(edge, level)
					var host: BasePieceEntity = _edges.get(key)
					if host == null or not host.piece.offers("doorway") or _edge_fills.has(key):
						continue
					var d := PiecePlacement.edge_center(edge).distance_squared_to(flat)
					if d < best_d:
						best_d = d
						best = {"placement": "edge", "cell": Vector2i(x, z),
							"edge": edge, "axis": edge.z, "level": level}
	if best.is_empty():
		# Nothing to fill nearby — park on the closest edge, invalid (red).
		var edge := PiecePlacement.nearest_edge(around, world_pos)
		best = {"placement": "edge", "cell": around, "edge": edge,
			"axis": edge.z, "level": 0}
	return best


# ── Validation ───────────────────────────────────────────────────────────

## The placement rulebook: inside the zone, on sane terrain, no overlap,
## every required socket present. Grounding is transitive by
## construction — every rule only accepts support that is itself
## supported — so floating structures can't be described at all.
func can_place(piece: BuildingPiece, spot: Dictionary) -> bool:
	if spot.is_empty() or spot.level < 0 or spot.level >= MAX_LEVELS:
		return false
	if piece.placement == "cell":
		return _can_place_cell(piece, spot)
	return _can_place_edge(piece, spot)


func _can_place_cell(piece: BuildingPiece, spot: Dictionary) -> bool:
	var cell: Vector2i = spot.cell
	var level: int = spot.level
	for x in piece.grid_size.x:
		for z in piece.grid_size.y:
			var c := cell + Vector2i(x, z)
			if not zone_rect().has_point(c):
				return false
			if _cells.has(PiecePlacement.cell_key(c, level)):
				return false
			# Ground floor also respects the legacy building/obstacle grid.
			if level == 0 and not WorldManager.is_area_buildable(c, Vector2i.ONE):
				return false
	if piece.needs("terrain"):
		if level != 0 or not _terrain_flat_enough(cell, piece.grid_size):
			return false
	if piece.needs("roof_support"):
		if level == 0 or not _has_roof_support(cell, piece.grid_size, level):
			return false
	if piece.needs("surface"):
		var below: BasePieceEntity = _cells.get(PiecePlacement.cell_key(cell, level))
		if below == null or not below.piece.offers("surface"):
			return false
	return true


func _can_place_edge(piece: BuildingPiece, spot: Dictionary) -> bool:
	var edge: Vector3i = spot.edge
	var level: int = spot.level
	var beside: Array = PiecePlacement.cells_beside_edge(edge)
	if not (zone_rect().has_point(beside[0]) or zone_rect().has_point(beside[1])):
		return false

	if piece.needs("doorway"):
		var key := PiecePlacement.edge_key(edge, level)
		var host: BasePieceEntity = _edges.get(key)
		return host != null and host.piece.offers("doorway") \
			and not _edge_fills.has(key)

	if _edges.has(PiecePlacement.edge_key(edge, level)):
		return false
	if piece.needs("edge_support") and not _has_edge_support(edge, level):
		return false
	if level == 0 and not _terrain_flat_enough_edge(edge):
		return false
	return true


## A wall-type piece stands on a foundation/floor beside its edge at the
## same storey, or on a stackable piece directly below.
func _has_edge_support(edge: Vector3i, level: int) -> bool:
	for cell: Vector2i in PiecePlacement.cells_beside_edge(edge):
		var support: BasePieceEntity = _cells.get(PiecePlacement.cell_key(cell, level))
		if support != null and support.piece.offers("edge_support"):
			return true
	if level > 0:
		var below: BasePieceEntity = _edges.get(PiecePlacement.edge_key(edge, level - 1))
		if below != null and below.piece.offers("stack"):
			return true
	return false


func _has_roof_support(cell: Vector2i, size: Vector2i, level: int) -> bool:
	for edge: Vector3i in _perimeter_edges(cell, size):
		var support: BasePieceEntity = _edges.get(PiecePlacement.edge_key(edge, level - 1))
		if support != null and support.piece.offers("roof_support"):
			return true
	return false


func _perimeter_edges(cell: Vector2i, size: Vector2i) -> Array:
	var out := []
	for x in size.x:
		out.append(Vector3i(cell.x + x, cell.y, 0))           # north row
		out.append(Vector3i(cell.x + x, cell.y + size.y, 0))  # south row
	for z in size.y:
		out.append(Vector3i(cell.x, cell.y + z, 1))           # west column
		out.append(Vector3i(cell.x + size.x, cell.y + z, 1))  # east column
	return out


func _cell_area_occupied(cell: Vector2i, size: Vector2i, level: int) -> bool:
	for x in size.x:
		for z in size.y:
			if _cells.has(PiecePlacement.cell_key(cell + Vector2i(x, z), level)):
				return true
	return false


## Reject builds on broken ground: the corner heights of the footprint
## must stay within the settings threshold.
func _terrain_flat_enough(cell: Vector2i, size: Vector2i) -> bool:
	var cs := WorldManager.cell_size()
	var lo := INF
	var hi := -INF
	for x in size.x + 1:
		for z in size.y + 1:
			var h := WorldManager.ground_height(
				Vector3((cell.x + x) * cs, 0, (cell.y + z) * cs))
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo <= DataManager.settings.build_max_terrain_step


func _terrain_flat_enough_edge(edge: Vector3i) -> bool:
	var cs := WorldManager.cell_size()
	var a := Vector3(edge.x * cs, 0, edge.y * cs)
	var b := a + (Vector3(cs, 0, 0) if edge.z == 0 else Vector3(0, 0, cs))
	return absf(WorldManager.ground_height(a) - WorldManager.ground_height(b)) \
		<= DataManager.settings.build_max_terrain_step


# ── Placement / removal ──────────────────────────────────────────────────

## Validate, pay, spawn, register, wire navigation. Returns the entity
## or null. [param free] skips cost (save loading, world gen).
func place(piece: BuildingPiece, spot: Dictionary, free: bool = false) -> BasePieceEntity:
	if not can_place(piece, spot):
		return null
	if not free and not ResourceManager.spend(piece.cost):
		EventBus.notify("Not enough materials!", 1)
		return null
	assert(_container != null, "No world registered — call register_container() first")

	var entity := BasePieceEntity.new()
	_container.add_child(entity)
	entity.setup(piece, spot)
	_entities.append(entity)
	_register(entity)
	EventBus.piece_placed.emit(entity)
	return entity


func remove_piece(entity: BasePieceEntity) -> void:
	if not _entities.has(entity):
		return
	_unregister(entity)
	_entities.erase(entity)
	EventBus.piece_removed.emit(entity)
	entity.queue_free()


func piece_count() -> int:
	return _entities.size()


func _register(entity: BasePieceEntity) -> void:
	var spot: Dictionary = entity.spot
	if spot.placement == "cell":
		for x in entity.piece.grid_size.x:
			for z in entity.piece.grid_size.y:
				var c: Vector2i = spot.cell + Vector2i(x, z)
				_cells[PiecePlacement.cell_key(c, spot.level)] = entity
				if spot.level == 0:
					WorldManager.occupy_area(c, Vector2i.ONE, entity)
		return
	var key := PiecePlacement.edge_key(spot.edge, spot.level)
	if entity.piece.needs("doorway"):
		_edge_fills[key] = entity
	else:
		_edges[key] = entity
	# Navigation: solid ground-storey pieces wall off their cell border.
	if spot.level == 0 and entity.piece.blocks_movement:
		WorldManager.block_edge(spot.edge, entity)


func _unregister(entity: BasePieceEntity) -> void:
	var spot: Dictionary = entity.spot
	if spot.placement == "cell":
		for x in entity.piece.grid_size.x:
			for z in entity.piece.grid_size.y:
				var c: Vector2i = spot.cell + Vector2i(x, z)
				_cells.erase(PiecePlacement.cell_key(c, spot.level))
				if spot.level == 0:
					WorldManager.vacate_area(c, Vector2i.ONE)
		return
	var key := PiecePlacement.edge_key(spot.edge, spot.level)
	if entity.piece.needs("doorway"):
		_edge_fills.erase(key)
	else:
		_edges.erase(key)
	if spot.level == 0 and entity.piece.blocks_movement:
		WorldManager.unblock_edge(spot.edge)


# ── Save contract ────────────────────────────────────────────────────────

func get_save_data() -> Array:
	var out := []
	for entity: BasePieceEntity in _entities:
		out.append(entity.get_save_data())
	return out


func apply_save_data(data: Array) -> void:
	for entry: Dictionary in data:
		var piece := DataManager.get_piece(str(entry.get("id", "")))
		if piece == null:
			push_warning("[BaseManager] Save references unknown piece: %s" % entry)
			continue
		var spot := {
			"placement": str(entry.get("p", "cell")),
			"cell": Vector2i(int(entry.get("x", 0)), int(entry.get("z", 0))),
			"axis": int(entry.get("a", 0)),
			"level": int(entry.get("lv", 0)),
		}
		if spot.placement == "edge":
			spot["edge"] = Vector3i(int(entry.get("x", 0)), int(entry.get("z", 0)),
				int(entry.get("a", 0)))
		var entity := place(piece, spot, true)
		if entity != null:
			entity.health = int(entry.get("hp", piece.max_health))
