extends SceneTree
## CI compound smoke test:
##   godot --headless --path . -s tools/debug_compound.gd
##
## Actually BUILDS the HQ compound through the real managers and
## asserts the result: the ruined Capital exists, the broken perimeter
## has walls, exactly one gate sits on the east road, authored debris
## spawned, all six construction-zone markers exist, and the compound
## interior stays walkable for the Commander. Prints COMPOUND_OK /
## COMPOUND_BROKEN for the workflow grep.
##
## NOTE: -s entry scripts compile BEFORE autoload singletons register,
## so managers are fetched via get_node at runtime — never referenced
## by their autoload identifiers here.

func _initialize() -> void:
	# Autoload managers finish entering the tree after -s scripts
	# initialize — run a couple of frames later so they're all ready.
	await process_frame
	await process_frame

	var bm: Node = root.get_node("BuildingManager")
	var om: Node = root.get_node("ObstacleManager")
	var wm: Node = root.get_node("WorldManager")

	var container := Node3D.new()
	root.add_child(container)
	bm.register_container(container)
	om.register_container(container)

	var compound: Node3D = load("res://scripts/world/hq_compound.gd").new()
	root.add_child(compound)
	compound.build_initial()

	var failures: Array[String] = []

	# ── Structures ────────────────────────────────────────────────────
	var hq: Node = bm.first_of("safe_house")
	var walls: int = bm.count_of("wall")
	var gates: int = bm.count_of("gate")
	print("hq=", hq != null, " walls=", walls, " gates=", gates)
	if hq == null:
		failures.append("no pre-placed HQ")
	if walls < 10:
		failures.append("perimeter too sparse (%d walls)" % walls)
	if gates != 1:
		failures.append("expected exactly 1 gate, got %d" % gates)

	var gate: Node = bm.first_of("gate")
	if gate != null:
		print("gate cell=", gate.cell, " (east wall is x=+6)")
		if gate.cell.x != 6:
			failures.append("gate not on the east wall")

	# ── Debris ────────────────────────────────────────────────────────
	var debris := 0
	for node in container.get_children():
		if node.has_method("blocks_building") and "definition" in node \
				and node.definition != null \
				and String(node.definition.id) in ["rubble", "debris", "food_crate", "medical_crate"]:
			debris += 1
	print("authored debris entities=", debris)
	if debris < 4:
		failures.append("too little authored debris (%d)" % debris)

	# ── Zone markers (scenery pass) ───────────────────────────────────
	compound._on_world_ready()
	await process_frame
	var markers := compound.get_child_count()
	print("zone markers=", markers)
	if markers != 6:
		failures.append("expected 6 zone markers, got %d" % markers)

	# ── Navigation: interior open, HQ/walls block ─────────────────────
	for cell in [Vector2i(1, 1), Vector2i(-4, 0), Vector2i(0, -4), Vector2i(4, 4)]:
		if not wm.is_cell_walkable(cell):
			failures.append("interior cell %s blocked" % cell)
	if wm.is_cell_walkable(Vector2i(-1, -1)):
		failures.append("HQ interior unexpectedly walkable")
	# Construction zones must stay completely free for future buildings.
	for zone_corner in [Vector2i(-5, -5), Vector2i(3, -5), Vector2i(-5, -1),
			Vector2i(3, 3), Vector2i(-5, 3), Vector2i(-1, 3)]:
		if not wm.is_area_free(zone_corner, Vector2i(2, 2)):
			failures.append("construction zone at %s is obstructed" % zone_corner)

	# ── Gate opens into a walkable passage ────────────────────────────
	if gate != null:
		gate.gate_open = true
		if gate.blocks_movement():
			failures.append("open gate still blocks movement")

	for f in failures:
		print("FAIL: ", f)
	print("COMPOUND_OK" if failures.is_empty() else "COMPOUND_BROKEN")
	quit(0 if failures.is_empty() else 1)
