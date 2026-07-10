class_name WorldDecorator
extends Node3D
## Turns the RegionMap layout into a lived-in looking world: paints the
## ground splat map (roads, footpaths, the HQ slab, zone tinting) and
## scatters instanced decorative foliage (grass, flowers).
##
## Foliage is pure set dressing — MultiMesh instances with no grid
## presence, no collision and no interaction, so thousands render in a
## single draw call per type. Gameplay props (choppable trees, minable
## rocks) stay ObstacleEntities spawned by ObstacleManager; this class
## never touches the grid.
##
## Density/draw distance come from QualityProfile (PC vs Android), and
## every rule (which zones grow what, how thick) lives in FOLIAGE_RULES
## so tuning is a table edit. When a real terrain backend (Terrain3D)
## lands, the splat build feeds its material instead — the layout
## queries and foliage rules carry over unchanged.

const SPLAT_RESOLUTION := 192
## Deterministic so the same map paints/plants identically every load.
const FOLIAGE_SEED := 1337

## Foliage catalog: model, base instance count (desktop, before the
## quality multiplier), zone density weights (unlisted zone types use
## "default"), and scale jitter.
const FOLIAGE_RULES: Array[Dictionary] = [
	{
		"model": "res://assets/nature/Grass_Common_Short.gltf",
		"count": 2600,
		"weights": {"forest": 1.5, "clearing": 0.45, "rocky": 0.3, "town": 0.25, "default": 1.0},
		"scale_min": 0.8, "scale_max": 1.4,
	},
	{
		"model": "res://assets/nature/Grass_Common_Tall.gltf",
		"count": 1100,
		"weights": {"forest": 1.7, "clearing": 0.2, "rocky": 0.25, "town": 0.3, "default": 1.0},
		"scale_min": 0.9, "scale_max": 1.6,
	},
	{
		"model": "res://assets/nature/Flower_4_Group.gltf",
		"count": 220,
		"weights": {"forest": 1.2, "clearing": 0.5, "rocky": 0.1, "default": 1.0},
		"scale_min": 0.8, "scale_max": 1.2,
	},
]

var _region: RegionMap


## Called by GameWorld after the ground plane exists.
func setup(ground: MeshInstance3D) -> void:
	_region = RegionMap.load_default()
	_paint_ground(ground)
	_plant_foliage()


# ── Ground painting ──────────────────────────────────────────────────────

## Rasterize the layout into the splat the ground shader blends:
## R dirt, G gravel, B asphalt, A concrete.
func _paint_ground(ground: MeshInstance3D) -> void:
	var world := WorldManager.world_rect()
	var img := Image.create(SPLAT_RESOLUTION, SPLAT_RESOLUTION, false, Image.FORMAT_RGBA8)
	for py in SPLAT_RESOLUTION:
		for px in SPLAT_RESOLUTION:
			var xz := world.position + world.size * Vector2(
				(px + 0.5) / SPLAT_RESOLUTION, (py + 0.5) / SPLAT_RESOLUTION)
			img.set_pixel(px, py, _splat_for(xz))
	var material := ground.material_override as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("splat_map", ImageTexture.create_from_image(img))
	material.set_shader_parameter("world_origin", world.position)
	material.set_shader_parameter("world_extent", world.size)


func _splat_for(xz: Vector2) -> Color:
	var c := Color(0, 0, 0, 0)
	match _region.surface_at(xz):
		"concrete":
			c.a = 1.0
		"asphalt":
			c.b = 1.0
		"gravel":
			c.g = 1.0
		"dirt":
			c.r = 1.0
		_:
			# Natural ground: zones leave soft fingerprints so areas read
			# differently even before their props load in.
			match _region.zone_type_at(xz):
				"rocky":
					c.g = 0.45 * _blotch(xz, 0.22)
				"forest":
					c.r = 0.35 * _blotch(xz, 0.16)
				"campsite":
					c.g = 0.6 * _blotch(xz, 0.5)
				"resource":
					c.r = 0.25 * _blotch(xz, 0.3)
				"town":
					c.b = 0.3 * _blotch(xz, 0.25)
	return c


## Cheap value noise in [0,1] for organic patchiness (mirrors the
## shader's hash so painted areas and detail noise feel related).
func _blotch(xz: Vector2, frequency: float) -> float:
	var p := xz * frequency
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector2.ONE * 3.0 - 2.0 * f)
	var a := _hash(i)
	var b := _hash(i + Vector2(1, 0))
	var c := _hash(i + Vector2(0, 1))
	var d := _hash(i + Vector2(1, 1))
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)


func _hash(p: Vector2) -> float:
	return fposmod(sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)


# ── Foliage ──────────────────────────────────────────────────────────────

func _plant_foliage() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = FOLIAGE_SEED
	var density := QualityProfile.foliage_density()
	for rule in FOLIAGE_RULES:
		var mesh := _mesh_from_scene(String(rule.model))
		if mesh == null:
			continue
		_scatter(mesh, rule, int(int(rule.count) * density), rng)


## One MultiMesh per foliage type = one draw call for thousands of
## plants. Rejection sampling keeps them off pavement and the HQ ring;
## zone weights make forests lush and clearings sparse.
func _scatter(mesh: Mesh, rule: Dictionary, count: int, rng: RandomNumberGenerator) -> void:
	var world := WorldManager.world_rect()
	var weights: Dictionary = rule.get("weights", {})
	var transforms: Array[Transform3D] = []
	var attempts := count * 6
	while transforms.size() < count and attempts > 0:
		attempts -= 1
		var xz := world.position + Vector2(rng.randf(), rng.randf()) * world.size
		if _region.is_paved(xz):
			continue
		var weight: float = weights.get(_region.zone_type_at(xz), weights.get("default", 1.0))
		if rng.randf() > weight:
			continue
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
			.scaled(Vector3.ONE * rng.randf_range(
				float(rule.scale_min), float(rule.scale_max))),
			Vector3(xz.x, 0, xz.y))
		transforms.append(xf)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = QualityProfile.foliage_view_distance()
	instance.visibility_range_end_margin = 8.0
	add_child(instance)


## Pull the first mesh out of an imported foliage scene (with its
## imported material attached) so a MultiMesh can instance it.
func _mesh_from_scene(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		push_warning("[WorldDecorator] Missing foliage model: %s" % path)
		return null
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var instance := scene.instantiate()
	var mesh := _find_mesh(instance)
	instance.free()
	return mesh


func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		# Bake surface overrides (imported materials) into the mesh so
		# the MultiMesh renders identically to the source scene.
		for i in mesh.get_surface_count():
			var override := mi.get_surface_override_material(i)
			if override != null:
				mesh.surface_set_material(i, override)
		return mesh
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
