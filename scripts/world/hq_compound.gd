class_name HqCompound
extends Node3D
## The starting Headquarters compound — a ruined base the player
## reclaims. Everything is driven by data/tables/hq_compound.json; this
## node contains zero knowledge of specific buildings or future module
## behaviour.
##
## Two responsibilities, cleanly split by lifetime:
##  - build_initial() (NEW games only, via GameManager): pre-places the
##    damaged HQ, a broken wall/gate perimeter with deterministic gaps
##    (some spilling rubble), and authored debris — all through
##    BuildingManager/ObstacleManager, so every piece occupies the grid
##    (that IS the game's collision), interacts (gate opens, crates
##    gather), and saves/loads like anything player-made.
##  - construction-zone markers (EVERY load): flat foundation slabs with
##    corner stubs and a name, marking where future modules (hospital,
##    workshop...) belong. Pure scenery — they reserve nothing, block
##    nothing, and the future building system just places real
##    buildings on the same cells.
##
## The zone footprints double as gravel patches in the ground paint
## (RegionMap reads the same table), so the compound floor reads worn
## and prepared without any extra art.

const SLAB_COLOR := Color(0.45, 0.44, 0.42, 0.55)
const STUB_COLOR := Color(0.55, 0.53, 0.5)
const LABEL_COLOR := Color(0.85, 0.8, 0.65, 0.9)

## Shared meshes/materials — zone markers instance these (slab meshes
## cached per footprint size, so differing zone sizes stay correct).
var _slab_meshes: Dictionary = {}
var _slab_material: StandardMaterial3D
var _stub_mesh: BoxMesh
var _stub_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("hq_compound")
	EventBus.world_ready.connect(_on_world_ready)


## Fresh maps only (GameManager calls before obstacle scatter): spawn
## the ruined structures. Saved games restore them via the managers.
func build_initial() -> void:
	var table: Variant = DataManager.get_table("hq_compound")
	if table == null or not (table is Dictionary):
		return
	_place_hq(table.get("hq", {}))
	_place_perimeter(table.get("perimeter", {}))
	for entry in table.get("debris", []):
		ObstacleManager.place(String(entry.get("id", "")),
			Vector2i(int(entry.cell[0]), int(entry.cell[1])))


## Every world load: rebuild zone markers and re-apply the HQ's ruined
## look (cosmetic state isn't saved; the entity is rebuilt each load).
func _on_world_ready() -> void:
	for child in get_children():
		child.queue_free()
	var table: Variant = DataManager.get_table("hq_compound")
	if table == null or not (table is Dictionary):
		return
	for zone in table.get("zones", []):
		_build_zone_marker(zone)
	_apply_worn_look(table.get("hq", {}))


# ── World-gen structures ─────────────────────────────────────────────────

func _place_hq(hq: Dictionary) -> void:
	if hq.is_empty():
		return
	BuildingManager.place_prebuilt(String(hq.get("building", "safe_house")),
		Vector2i(int(hq.cell[0]), int(hq.cell[1])))


## Broken rectangle of wall segments with a gate on the east side
## (where the main road meets the compound). Gaps are deterministic per
## cell so every new game gets the same authored-feeling ruin.
func _place_perimeter(config: Dictionary) -> void:
	if config.is_empty():
		return
	var extent := int(config.get("half_extent", 6))
	var wall := String(config.get("wall", "wall"))
	var gate := String(config.get("gate", "gate"))
	var gap_chance := float(config.get("gap_chance", 0.3))
	var rubble_chance := float(config.get("rubble_in_gap_chance", 0.45))
	var rubble := String(config.get("rubble", "rubble"))

	# Segments are 2x1; sides step by 2. rotation 1 turns them vertical.
	for step in range(-extent, extent, 2):
		_perimeter_segment(wall, Vector2i(step, -extent), 0, gap_chance, rubble, rubble_chance)
		_perimeter_segment(wall, Vector2i(step, extent), 0, gap_chance, rubble, rubble_chance)
		_perimeter_segment(wall, Vector2i(-extent, step), 1, gap_chance, rubble, rubble_chance)
		if step == 0:
			# The east segment on the road line is the compound gate.
			BuildingManager.place_prebuilt(gate, Vector2i(extent, step), 1)
		else:
			_perimeter_segment(wall, Vector2i(extent, step), 1, gap_chance, rubble, rubble_chance)


func _perimeter_segment(wall: String, cell: Vector2i, rot: int,
		gap_chance: float, rubble: String, rubble_chance: float) -> void:
	var roll := float(absi(hash(cell)) % 1000) / 1000.0
	if roll < gap_chance:
		# Collapsed section: sometimes the old wall's rubble remains.
		if float(absi(hash(cell * 31)) % 1000) / 1000.0 < rubble_chance:
			ObstacleManager.place(rubble, cell)
		return
	BuildingManager.place_prebuilt(wall, cell, rot)


func _apply_worn_look(hq: Dictionary) -> void:
	var entity: BuildingEntity = BuildingManager.first_of(
		String(hq.get("building", "safe_house")))
	if entity == null:
		return
	var t: Array = hq.get("worn_tint", [0.62, 0.57, 0.5])
	entity.set_worn(Color(float(t[0]), float(t[1]), float(t[2])))


# ── Construction-zone markers (scenery only) ─────────────────────────────

func _build_zone_marker(zone: Dictionary) -> void:
	var cell := Vector2i(int(zone.cell[0]), int(zone.cell[1]))
	var size := Vector2i(int(zone.size[0]), int(zone.size[1]))
	var footprint := Vector2(size) * WorldManager.cell_size()
	var center := WorldManager.area_center(cell, size)

	var root := Node3D.new()
	root.position = center + Vector3(0, 0.04, 0)
	add_child(root)

	# Foundation slab (mesh shared per size, material shared by all).
	var size_key := "%dx%d" % [size.x, size.y]
	if not _slab_meshes.has(size_key):
		var mesh := PlaneMesh.new()
		mesh.size = footprint * 0.94
		_slab_meshes[size_key] = mesh
	if _slab_material == null:
		_slab_material = StandardMaterial3D.new()
		_slab_material.albedo_color = SLAB_COLOR
		_slab_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_slab_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var slab := MeshInstance3D.new()
	slab.mesh = _slab_meshes[size_key]
	slab.material_override = _slab_material
	root.add_child(slab)

	# Four corner stubs — old foundation piles.
	if _stub_mesh == null:
		_stub_mesh = BoxMesh.new()
		_stub_mesh.size = Vector3(0.5, 0.55, 0.5)
		_stub_material = StandardMaterial3D.new()
		_stub_material.albedo_color = STUB_COLOR
		_stub_material.roughness = 0.95
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var stub := MeshInstance3D.new()
		stub.mesh = _stub_mesh
		stub.material_override = _stub_material
		stub.position = Vector3(
			corner.x * (footprint.x / 2.0 - 0.4), 0.24,
			corner.y * (footprint.y / 2.0 - 0.4))
		root.add_child(stub)

	var label := Label3D.new()
	label.text = String(zone.get("label", zone.get("id", "")))
	label.font_size = 64
	label.pixel_size = 0.012
	label.modulate = LABEL_COLOR
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position.y = 0.9
	root.add_child(label)
