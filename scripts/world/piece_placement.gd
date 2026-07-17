class_name PiecePlacement
extends RefCounted
## Pure helpers for the modular base-building grid: cell/edge coordinate
## math, model auto-fitting and spot transforms. No state beyond caches —
## the placed-piece bookkeeping lives in BaseManager.
##
## Grid model:
##  - CELL pieces (foundations, floors, roofs) occupy whole world-grid
##    cells at a vertical level. Key: Vector3i(cell.x, cell.y, level).
##  - EDGE pieces (walls, doors, windows, gates) occupy one cell border.
##    An edge is (x, z, axis): axis 0 runs along X on the cell's -Z
##    border, axis 1 runs along Z on the cell's -X border. Key with
##    level: Vector4i(x, z, axis, level).
## Levels are storeys: base Y = ground + level * level_height.
##
## A "spot" is the Dictionary the whole system passes around:
##   {"placement": "cell"|"edge", "cell": Vector2i, "axis": int,
##    "level": int}
## axis is meaningful for edges only (cell spots carry 0).

## Fitted-model numbers per piece id: {"scale": Vector3, "offset":
## Vector3, "aabb": AABB}. Computed once, reused by every ghost/entity —
## no per-placement AABB walks.
static var _fit_cache: Dictionary = {}
## Shared collision shapes per piece id (thousands of walls, one shape).
static var _shape_cache: Dictionary = {}


static func level_height() -> float:
	return DataManager.settings.build_level_height


# ── Coordinate math ──────────────────────────────────────────────────────

static func cell_key(cell: Vector2i, level: int) -> Vector3i:
	return Vector3i(cell.x, cell.y, level)


static func edge_key(edge: Vector3i, level: int) -> Vector4i:
	return Vector4i(edge.x, edge.y, edge.z, level)


## The four edges bordering [param cell]: N, S, W, E.
static func edges_of_cell(cell: Vector2i) -> Array:
	return [
		Vector3i(cell.x, cell.y, 0),      # north  (-Z border, runs along X)
		Vector3i(cell.x, cell.y + 1, 0),  # south
		Vector3i(cell.x, cell.y, 1),      # west   (-X border, runs along Z)
		Vector3i(cell.x + 1, cell.y, 1),  # east
	]


## The two cells an edge separates.
static func cells_beside_edge(edge: Vector3i) -> Array:
	if edge.z == 0:
		return [Vector2i(edge.x, edge.y - 1), Vector2i(edge.x, edge.y)]
	return [Vector2i(edge.x - 1, edge.y), Vector2i(edge.x, edge.y)]


## Edges collinear with [param edge] on either end (gate↔fence runs).
static func collinear_edges(edge: Vector3i) -> Array:
	if edge.z == 0:
		return [Vector3i(edge.x - 1, edge.y, 0), Vector3i(edge.x + 1, edge.y, 0)]
	return [Vector3i(edge.x, edge.y - 1, 1), Vector3i(edge.x, edge.y + 1, 1)]


## Center of an edge segment on the ground plane (Y = 0).
static func edge_center(edge: Vector3i) -> Vector3:
	var cs := WorldManager.cell_size()
	if edge.z == 0:
		return Vector3((edge.x + 0.5) * cs, 0.0, edge.y * cs)
	return Vector3(edge.x * cs, 0.0, (edge.y + 0.5) * cs)


## The edge of [param cell] nearest to [param world_pos]; when
## [param axis_lock] is 0 or 1 only edges of that axis are considered
## (that's what the rotate control toggles). Returns Vector3i.
static func nearest_edge(cell: Vector2i, world_pos: Vector3, axis_lock: int = -1) -> Vector3i:
	var best: Vector3i = Vector3i(cell.x, cell.y, 0)
	var best_d := INF
	for edge: Vector3i in edges_of_cell(cell):
		if axis_lock >= 0 and edge.z != axis_lock:
			continue
		var d := edge_center(edge).distance_squared_to(Vector3(world_pos.x, 0, world_pos.z))
		if d < best_d:
			best_d = d
			best = edge
	return best


## World transform for a piece at [param spot]: origin on the spot
## center at the spot's storey height, yawed so edge pieces lie along
## their edge (axis 1 = rotated 90°).
static func spot_transform(piece: BuildingPiece, spot: Dictionary) -> Transform3D:
	var origin: Vector3
	if spot.placement == "cell":
		var cs := WorldManager.cell_size()
		var cell: Vector2i = spot.cell
		origin = Vector3(
			(cell.x + piece.grid_size.x * 0.5) * cs, 0.0,
			(cell.y + piece.grid_size.y * 0.5) * cs)
	else:
		origin = edge_center(spot.edge)
	origin.y = WorldManager.ground_height(origin) + spot.level * level_height()
	var basis := Basis.IDENTITY
	if spot.placement == "edge" and (spot.edge as Vector3i).z == 1:
		basis = Basis(Vector3.UP, -PI / 2.0)  # +X → +Z: run along Z
	return Transform3D(basis, origin)


# ── Model fitting ────────────────────────────────────────────────────────

## Instance the piece's model fitted to its grid footprint: recentered
## on the origin in X/Z with its base at Y = 0, so placing it is just
## setting the spot transform. Fit numbers are cached per piece id.
static func build_visual(piece: BuildingPiece) -> Node3D:
	var root := Node3D.new()
	var holder := Node3D.new()
	root.add_child(holder)
	var scene: PackedScene = null
	if piece.model_path != "" and ResourceLoader.exists(piece.model_path):
		scene = load(piece.model_path) as PackedScene
	if scene != null:
		holder.add_child(scene.instantiate())
	else:
		holder.add_child(_placeholder(piece))

	var fit := _fit_for(piece, holder)
	holder.transform = Transform3D(
		Basis.from_scale(fit.scale) * Basis.from_euler(piece.mesh_rotation_degrees * (PI / 180.0)),
		fit.offset)
	return root


## Fitted, origin-centered bounds of the piece (for colliders and
## previews). Cached with the fit itself.
static func fitted_aabb(piece: BuildingPiece) -> AABB:
	if not _fit_cache.has(piece.id):
		# Force the cache through a throwaway visual.
		build_visual(piece)
	return _fit_cache[piece.id].aabb


## Shared box collision shape for a piece type.
static func collision_shape(piece: BuildingPiece) -> BoxShape3D:
	if not _shape_cache.has(piece.id):
		var shape := BoxShape3D.new()
		shape.size = fitted_aabb(piece).size.max(Vector3.ONE * 0.05)
		_shape_cache[piece.id] = shape
	return _shape_cache[piece.id]


static func _fit_for(piece: BuildingPiece, holder: Node3D) -> Dictionary:
	if _fit_cache.has(piece.id):
		return _fit_cache[piece.id]

	# Measure with the authored correction applied, unscaled.
	holder.rotation_degrees = piece.mesh_rotation_degrees
	var bounds := ModelFactory._combined_aabb(holder, Transform3D.IDENTITY)
	holder.rotation_degrees = Vector3.ZERO
	if bounds.size.length() < 0.001:
		bounds = AABB(Vector3(-0.5, 0, -0.1), Vector3(1, 1, 0.2))

	var cs := WorldManager.cell_size()
	var scale := piece.mesh_scale
	if scale == Vector3.ZERO:
		match piece.fit_mode:
			"tile":
				var sx := piece.grid_size.x * cs / maxf(bounds.size.x, 0.001)
				var sz := piece.grid_size.y * cs / maxf(bounds.size.z, 0.001)
				scale = Vector3(sx, minf(sx, sz), sz)
			"contain":
				var s := minf(piece.grid_size.x * cs / maxf(bounds.size.x, 0.001),
					piece.grid_size.y * cs / maxf(bounds.size.z, 0.001))
				scale = Vector3.ONE * s
			_:  # "edge"
				scale = Vector3(cs / maxf(bounds.size.x, 0.001), 1.0, 1.0)

	var offset: Vector3
	if piece.anchor == "authored":
		offset = piece.mesh_offset
	else:
		var center := bounds.get_center()
		offset = Vector3(-center.x * scale.x, -bounds.position.y * scale.y, -center.z * scale.z)
	var fitted := AABB(bounds.position * scale + offset, bounds.size * scale)
	var fit := {"scale": scale, "offset": offset, "aabb": fitted}
	_fit_cache[piece.id] = fit
	return fit


static func _placeholder(piece: BuildingPiece) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 1, 0.2) if piece.placement == "edge" else Vector3(1, 0.2, 1)
	var material := StandardMaterial3D.new()
	material.albedo_color = piece.color
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position.y = mesh.size.y / 2.0
	return instance
