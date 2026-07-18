extends SceneTree
## CI base-building smoke test:
##   godot --headless --path . -s tools/debug_base_building.gd
##
## Exercises the modular building system through the real managers:
## discovers pieces, builds a 2x2 hut (foundations → walls/doorway/
## window → door leaf → roof), asserts every placement rule the design
## promises (no floating pieces, no overlap, out-of-zone rejected, door
## only in doorways, roofs need walls), checks snapping, navigation
## edges and the save round-trip. Prints BASEBUILD_OK / BASEBUILD_BROKEN
## for the workflow grep.
##
## NOTE: -s entry scripts compile BEFORE autoload singletons register,
## so managers are fetched via get_node at runtime — never referenced
## by their autoload identifiers here.

func _initialize() -> void:
	await process_frame
	await process_frame

	var dm: Node = root.get_node("DataManager")
	var bm: Node = root.get_node("BaseManager")
	var wm: Node = root.get_node("WorldManager")
	var rm: Node = root.get_node("ResourceManager")

	var container := Node3D.new()
	root.add_child(container)
	bm.register_container(container)

	var failures: Array[String] = []

	# ── Discovery: every piece loads, models resolve ──────────────────
	var pieces: Array = dm.all_pieces()
	print("pieces discovered: ", pieces.size())
	if pieces.size() < 9:
		failures.append("expected >= 9 building pieces, found %d" % pieces.size())
	for piece in pieces:
		if piece.model_path != "" and not ResourceLoader.exists(piece.model_path):
			failures.append("%s: missing model %s" % [piece.id, piece.model_path])

	var foundation: Resource = dm.get_piece("foundation_wood")
	var wall: Resource = dm.get_piece("wall_wood")
	var doorway: Resource = dm.get_piece("doorway_wood")
	var door: Resource = dm.get_piece("door_wood")
	var window: Resource = dm.get_piece("window_wood")
	var roof: Resource = dm.get_piece("roof_wood")

	# ── Rule: nothing floats — wall/roof before any foundation ────────
	var w_spot := {"placement": "edge", "cell": Vector2i(0, 0),
		"edge": Vector3i(0, 0, 0), "axis": 0, "level": 0}
	if bm.can_place(wall, w_spot):
		failures.append("wall allowed with no foundation (floating)")
	if bm.can_place(roof, {"placement": "cell", "cell": Vector2i(0, 0), "axis": 0, "level": 1}):
		failures.append("roof allowed with no walls (floating)")

	# ── Build a 2x2 hut at the zone center ─────────────────────────────
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		if bm.place(foundation, {"placement": "cell", "cell": cell, "axis": 0, "level": 0}, true) == null:
			failures.append("foundation refused at %s" % cell)

	# Overlap: same cell twice must fail.
	if bm.can_place(foundation, {"placement": "cell", "cell": Vector2i(0, 0), "axis": 0, "level": 0}):
		failures.append("overlapping foundation allowed")

	# Outside the HQ zone must fail.
	if bm.can_place(foundation, {"placement": "cell", "cell": Vector2i(40, 40), "axis": 0, "level": 0}):
		failures.append("foundation allowed outside the build zone")

	# Walls around the perimeter, one doorway south, one window east.
	var edge_specs := [
		[wall, Vector3i(0, 0, 0)], [wall, Vector3i(1, 0, 0)],      # north
		[doorway, Vector3i(0, 2, 0)], [wall, Vector3i(1, 2, 0)],   # south
		[wall, Vector3i(0, 0, 1)], [wall, Vector3i(0, 1, 1)],      # west
		[window, Vector3i(2, 0, 1)], [wall, Vector3i(2, 1, 1)],    # east
	]
	for spec in edge_specs:
		var spot := {"placement": "edge", "cell": Vector2i(0, 0),
			"edge": spec[1], "axis": (spec[1] as Vector3i).z, "level": 0}
		if bm.place(spec[0], spot, true) == null:
			failures.append("%s refused at edge %s" % [spec[0].id, spec[1]])

	# ── Snapping: hover inside cell (0,0) near the north wall ─────────
	var cs: float = wm.cell_size()
	var snap: Dictionary = bm.best_spot_for(wall, Vector3(0.5 * cs, 0, 0.15 * cs), -1)
	if snap.placement != "edge" or snap.edge != Vector3i(0, 0, 0):
		failures.append("wall snap picked %s, wanted north edge of (0,0)" % [snap])
	elif snap.level != 1:
		failures.append("occupied edge should stack to level 1, got %d" % snap.level)
	# Door hovered mid-hut: snaps to the one open doorway, not a wall.
	var door_snap: Dictionary = bm.best_spot_for(door, Vector3(0.6 * cs, 0, 1.5 * cs), -1)
	if door_snap.get("edge", Vector3i.MAX) != Vector3i(0, 2, 0):
		failures.append("door did not snap to the nearest doorway: %s" % [door_snap])

	# ── Door: only into doorways ───────────────────────────────────────
	var door_on_wall := {"placement": "edge", "cell": Vector2i(0, 0),
		"edge": Vector3i(0, 0, 0), "axis": 0, "level": 0}
	if bm.can_place(door, door_on_wall):
		failures.append("door allowed on a plain wall")
	# The empty doorway is walkable BEFORE a door fills it.
	if not wm.is_move_allowed(Vector2i(0, 1), Vector2i(0, 2)):
		failures.append("empty doorway blocks movement")
	var door_spot := {"placement": "edge", "cell": Vector2i(0, 1),
		"edge": Vector3i(0, 2, 0), "axis": 0, "level": 0}
	var door_entity: Node = bm.place(door, door_spot, true)
	if door_entity == null:
		failures.append("door refused in a doorway")
	elif bm.can_place(door, door_spot):
		failures.append("second door allowed in a filled doorway")

	# ── Door states: closed blocks, open lets everyone through ───────
	if door_entity != null:
		if wm.is_move_allowed(Vector2i(0, 1), Vector2i(0, 2)):
			failures.append("closed door does not block movement")
		door_entity.set_open(true, false)
		if not wm.is_move_allowed(Vector2i(0, 1), Vector2i(0, 2)):
			failures.append("open door blocks movement")
		if not door_entity.is_open:
			failures.append("door state did not flip to open")

	# ── Barricades: window slots take window barricades only ──────────
	var barricade_window: Resource = dm.get_piece("barricade_window")
	var barricade_door: Resource = dm.get_piece("barricade_door")
	var window_spot := {"placement": "edge", "cell": Vector2i(1, 0),
		"edge": Vector3i(2, 0, 1), "axis": 1, "level": 0}
	if bm.can_place(barricade_door, window_spot):
		failures.append("door barricade allowed on a window opening")
	if bm.place(barricade_window, window_spot, true) == null:
		failures.append("window barricade refused on a window")

	# ── Roof: needs walls, then attaches ──────────────────────────────
	var roof_spot: Dictionary = bm.best_spot_for(roof, Vector3(0.5 * cs, 0, 0.5 * cs), -1)
	if roof_spot.level != 1:
		failures.append("roof over walled cell should sit at level 1, got %d" % roof_spot.level)
	if bm.place(roof, roof_spot, true) == null:
		failures.append("roof refused above completed walls")
	if bm.can_place(roof, {"placement": "cell", "cell": Vector2i(3, 3), "axis": 0, "level": 1}):
		failures.append("roof allowed over an unwalled cell")

	# ── Navigation: solid wall blocks the crossing ────────────────────
	if wm.is_move_allowed(Vector2i(0, 0), Vector2i(0, -1)):
		failures.append("north wall does not block movement")
	if not wm.is_move_allowed(Vector2i(0, 0), Vector2i(0, 1)):
		failures.append("open interior crossing wrongly blocked")

	# ── Save round-trip (door left OPEN going in) ─────────────────────
	var placed: int = bm.piece_count()
	var saved: Array = bm.get_save_data()
	bm.reset()
	bm.register_container(container)
	if bm.piece_count() != 0:
		failures.append("reset left pieces behind")
	bm.apply_save_data(saved)
	print("placed=", placed, " restored=", bm.piece_count())
	if bm.piece_count() != placed:
		failures.append("save round-trip lost pieces: %d -> %d" % [placed, bm.piece_count()])
	if not wm.is_edge_blocked(Vector3i(0, 0, 0)):
		failures.append("restored wall did not re-block its edge")
	if not wm.is_move_allowed(Vector2i(0, 1), Vector2i(0, 2)):
		failures.append("door open state lost in save round-trip")

	# Old saves have no "open" key — the door must come back CLOSED.
	var legacy: Array = []
	for entry: Dictionary in saved:
		var copy: Dictionary = entry.duplicate()
		copy.erase("open")
		legacy.append(copy)
	bm.reset()
	bm.register_container(container)
	bm.apply_save_data(legacy)
	if wm.is_move_allowed(Vector2i(0, 1), Vector2i(0, 2)):
		failures.append("legacy save door did not default to closed")

	# ── Textures really bound: kit panels must carry the palette ──────
	# (the WINDOW still uses a kit FBX panel with the New Palitra atlas;
	# wall/foundation/doorway are authored plank models with plain or
	# vertex-colour materials and legitimately carry no texture)
	var kit_scene: PackedScene = load(window.model_path)
	var kit_model: Node = kit_scene.instantiate()
	root.add_child(kit_model)
	if not _has_textured_mesh(kit_model):
		failures.append("kit panel imported without its palette texture")
	kit_model.queue_free()

	# ── Authored plank models: exact kit bounds so grid math holds ────
	var wall_aabb: AABB = load("res://scripts/world/piece_placement.gd").fitted_aabb(wall)
	if absf(wall_aabb.size.x - cs) > 0.01 or absf(wall_aabb.size.y - 3.0) > 0.01:
		failures.append("plank wall fitted size off: %s" % wall_aabb)
	var found_aabb: AABB = load("res://scripts/world/piece_placement.gd").fitted_aabb(foundation)
	if absf(found_aabb.size.x - cs) > 0.01 or absf(found_aabb.size.z - cs) > 0.01:
		failures.append("plank foundation fitted size off: %s" % found_aabb)

	# ── Ghost visuals really exist (fitted, non-empty) ─────────────────
	for piece in [foundation, wall, doorway, door, window, roof]:
		var visual: Node3D = load("res://scripts/world/piece_placement.gd").build_visual(piece)
		root.add_child(visual)
		var aabb: AABB = load("res://scripts/world/piece_placement.gd").fitted_aabb(piece)
		print(piece.id, " fitted size=", aabb.size)
		if aabb.size.length() < 0.1:
			failures.append("%s: fitted model is empty" % piece.id)
		visual.queue_free()

	# ── Verdict ────────────────────────────────────────────────────────
	if failures.is_empty():
		print("BASEBUILD_OK")
	else:
		for failure in failures:
			print("FAIL: ", failure)
		print("BASEBUILD_BROKEN")
	quit(0 if failures.is_empty() else 1)


func _first_textured_material(node: Node) -> BaseMaterial3D:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		for i in mesh_node.get_surface_override_material_count():
			var material := mesh_node.get_active_material(i)
			if material is BaseMaterial3D and (material as BaseMaterial3D).albedo_texture != null:
				return material
	for child in node.get_children():
		var found := _first_textured_material(child)
		if found != null:
			return found
	return null


func _has_textured_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		for i in mesh_node.get_surface_override_material_count():
			var material := mesh_node.get_active_material(i)
			if material is BaseMaterial3D and (material as BaseMaterial3D).albedo_texture != null:
				return true
	for child in node.get_children():
		if _has_textured_mesh(child):
			return true
	return false
