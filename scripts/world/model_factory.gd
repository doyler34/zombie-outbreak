class_name ModelFactory
extends RefCounted
## Builds the 3D visual for buildings, obstacles and combat units.
##
## Definitions with a `model` PackedScene (imported .glb) get the real
## asset, auto-fitted to their grid footprint and grounded at Y = 0.
## Everything else gets a chunky, bright primitive placeholder — so new
## content is playable before its art exists, and dropping in a .glb
## later is a data change.

const FOOTPRINT_FILL := 0.92
## Default height (meters) for a combatant with no model — sized to
## roughly match a Kenney mini-character.
const COMBATANT_PLACEHOLDER_HEIGHT := 0.85


## [param footprint] is the building's world-space footprint in meters.
static func building_model(def: BuildingDefinition, footprint: Vector2) -> Node3D:
	if def.model != null:
		return _fitted(def.model, footprint * FOOTPRINT_FILL, def.model_scale)
	return _chunky_house(def.color, footprint)


static func obstacle_model(def: ObstacleDefinition, footprint: Vector2) -> Node3D:
	if def.model != null:
		return _fitted(def.model, footprint * FOOTPRINT_FILL, def.model_scale)
	match def.model_kind:
		"tree": return _tree(footprint)
		"bush": return _bush(footprint)
		"rock": return _rock(footprint, 0.55)
		"boulder": return _rock(footprint, 0.9)
		"log": return _log(footprint)
		"pile": return _pile(footprint)
		"nest": return _nest(footprint)
		_: return _box(Color(0.6, 0.55, 0.5), footprint)


## Recursively set GeometryInstance3D transparency (ghost preview).
static func set_transparency(node: Node, value: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).transparency = value
	for child in node.get_children():
		set_transparency(child, value)


# ── Combat units ─────────────────────────────────────────────────────────

## Instance a CombatantDefinition's model (grounded at Y = 0, uniformly
## scaled), or a simple capsule placeholder when it has none. Returns the
## root Node3D; if the model has an AnimationPlayer it is left alone —
## CombatUnit finds it via find_animation_player() and drives it.
static func combatant_model(def: CombatantDefinition) -> Node3D:
	if def.model == null:
		return _combatant_placeholder(def.color)

	var root := Node3D.new()
	var model: Node3D = def.model.instantiate()
	root.add_child(model)

	var bounds := _combined_aabb(model, Transform3D.IDENTITY)
	if bounds.size.length() > 0.001:
		var s := def.model_scale if def.model_scale > 0.0 else 1.0
		model.scale = Vector3.ONE * s
		var center := bounds.get_center()
		model.position = Vector3(-center.x * s, -bounds.position.y * s, -center.z * s)
	return root


static func _combatant_placeholder(color: Color) -> Node3D:
	var root := Node3D.new()
	var h := COMBATANT_PLACEHOLDER_HEIGHT
	var capsule := CapsuleMesh.new()
	capsule.radius = h * 0.22
	capsule.height = h
	root.add_child(_mesh_node(capsule, color, Vector3(0, h / 2.0, 0)))
	return root


## Recursively multiply every material's albedo by [param tint]
## (duplicating materials first so sibling instances aren't affected).
## Used to give zombies a sickly cast without separate texture skins.
static func tint_model(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var mat := mi.get_surface_override_material(i)
				if mat == null:
					mat = mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					var dup: StandardMaterial3D = mat.duplicate()
					dup.albedo_color = dup.albedo_color * tint
					mi.set_surface_override_material(i, dup)
	for child in node.get_children():
		tint_model(child, tint)


## Total height (meters) of an instanced model, for placing a health bar
## above its head. Falls back to the placeholder height for empty models.
static func model_height(node: Node) -> float:
	var bounds := _combined_aabb(node, Transform3D.IDENTITY)
	return bounds.size.y if bounds.size.y > 0.01 else COMBATANT_PLACEHOLDER_HEIGHT


## Attach a weapon model to a character's skeleton bone so it follows the
## hand through animations. The weapon is AUTO-FIT to [param length]
## meters (longest dimension) and counter-scaled by [param model_scale]
## so it never inherits the character's oversize — regardless of the
## .fbx's native units. No-op (returns null) if the model has no
## Skeleton3D or the bone is missing. Offset/rotation are in bone space.
static func attach_weapon(character_root: Node, weapon_scene: PackedScene, model_scale: float,
		bone: String, offset: Vector3, rotation_degrees: Vector3, length: float) -> BoneAttachment3D:
	if weapon_scene == null:
		return null
	var skeleton := _find_skeleton(character_root)
	if skeleton == null or skeleton.find_bone(bone) < 0:
		push_warning("[ModelFactory] Weapon bone '%s' not found; weapon skipped." % bone)
		return null

	var attach := BoneAttachment3D.new()
	attach.bone_name = bone
	skeleton.add_child(attach)

	var weapon: Node3D = weapon_scene.instantiate()
	attach.add_child(weapon)

	# Fit the weapon to a real length, then divide out the character's
	# model_scale that this node inherits through the skeleton.
	var bounds := _combined_aabb(weapon, Transform3D.IDENTITY)
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var ms := model_scale if model_scale > 0.0 else 1.0
	var fit := (length / maxf(longest, 0.0001)) / ms
	weapon.scale = Vector3.ONE * fit
	weapon.position = offset
	weapon.rotation_degrees = rotation_degrees
	return attach


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


## Recursively find the first AnimationPlayer in an instanced model
## (glTF imports nest it under a few wrapper nodes).
static func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := find_animation_player(child)
		if found != null:
			return found
	return null


# ── GLB fitting ──────────────────────────────────────────────────────────

## Instance a scene, rotate its long axis to match the footprint's,
## uniformly scale to fit, and rest its base on the ground plane.
## [param scale_override] > 0 skips auto-fitting entirely and trusts the
## authored orientation — the tuning knob for assets that should be
## bigger or smaller than their plot (model_scale in the definitions).
static func _fitted(scene: PackedScene, footprint: Vector2, scale_override: float = 0.0) -> Node3D:
	var root := Node3D.new()
	var model: Node3D = scene.instantiate()
	root.add_child(model)

	var bounds := _combined_aabb(model, Transform3D.IDENTITY)
	if bounds.size.length() < 0.001:
		return root

	var s := scale_override
	if s <= 0.0:
		var extent_x := bounds.size.x
		var extent_z := bounds.size.z
		if (extent_x >= extent_z) != (footprint.x >= footprint.y):
			model.rotation.y = PI / 2.0
			var swap := extent_x
			extent_x = extent_z
			extent_z = swap
		s = minf(footprint.x / maxf(extent_x, 0.001), footprint.y / maxf(extent_z, 0.001))
	model.scale = Vector3.ONE * s
	# Recenter horizontally and sit the base on Y = 0. The AABB was
	# measured pre-rotation; a 90° yaw about the center keeps the same
	# center, so recentering by the rotated center stays correct.
	var center := bounds.get_center()
	if model.rotation.y != 0.0:
		center = Vector3(center.z, center.y, -center.x)
	model.position = Vector3(-center.x * s, -bounds.position.y * s, -center.z * s)
	return root


static func _combined_aabb(node: Node, xf: Transform3D) -> AABB:
	var local_xf := xf
	if node is Node3D:
		local_xf = xf * (node as Node3D).transform
	var merged := AABB()
	var found := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		merged = local_xf * (node as MeshInstance3D).mesh.get_aabb()
		found = true
	for child in node.get_children():
		var sub := _combined_aabb(child, local_xf)
		if sub.size.length() > 0.0001:
			merged = merged.merge(sub) if found else sub
			found = true
	return merged


# ── Primitive placeholders (bright + chunky) ─────────────────────────────

static func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat


static func _mesh_node(mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(color)
	mi.position = pos
	return mi


static func _box(color: Color, footprint: Vector2) -> Node3D:
	var root := Node3D.new()
	var h := minf(footprint.x, footprint.y) * 0.7
	var box := BoxMesh.new()
	box.size = Vector3(footprint.x * 0.85, h, footprint.y * 0.85)
	root.add_child(_mesh_node(box, color, Vector3(0, h / 2.0, 0)))
	return root


static func _chunky_house(color: Color, footprint: Vector2) -> Node3D:
	var root := Node3D.new()
	var h := minf(footprint.x, footprint.y) * 0.75
	var body := BoxMesh.new()
	body.size = Vector3(footprint.x * 0.82, h, footprint.y * 0.82)
	root.add_child(_mesh_node(body, color, Vector3(0, h / 2.0, 0)))
	var roof := PrismMesh.new()
	roof.size = Vector3(footprint.x * 0.92, h * 0.55, footprint.y * 0.92)
	root.add_child(_mesh_node(roof, color.darkened(0.35), Vector3(0, h + h * 0.275, 0)))
	return root


static func _tree(fp: Vector2) -> Node3D:
	var root := Node3D.new()
	var s := minf(fp.x, fp.y)
	var trunk := CylinderMesh.new()
	trunk.top_radius = s * 0.08
	trunk.bottom_radius = s * 0.11
	trunk.height = s * 0.5
	root.add_child(_mesh_node(trunk, Color(0.42, 0.30, 0.18), Vector3(0, s * 0.25, 0)))
	var lower := CylinderMesh.new()
	lower.top_radius = 0.0
	lower.bottom_radius = s * 0.42
	lower.height = s * 0.75
	root.add_child(_mesh_node(lower, Color(0.22, 0.52, 0.25), Vector3(0, s * 0.75, 0)))
	var upper := CylinderMesh.new()
	upper.top_radius = 0.0
	upper.bottom_radius = s * 0.30
	upper.height = s * 0.6
	root.add_child(_mesh_node(upper, Color(0.28, 0.60, 0.30), Vector3(0, s * 1.2, 0)))
	return root


static func _bush(fp: Vector2) -> Node3D:
	var root := Node3D.new()
	var s := minf(fp.x, fp.y)
	var blob := SphereMesh.new()
	blob.radius = s * 0.38
	blob.height = s * 0.5
	root.add_child(_mesh_node(blob, Color(0.30, 0.58, 0.28), Vector3(0, s * 0.25, 0)))
	return root


static func _rock(fp: Vector2, bulk: float) -> Node3D:
	var root := Node3D.new()
	var s := minf(fp.x, fp.y) * bulk
	var stone := SphereMesh.new()
	stone.radius = s * 0.5
	stone.height = s * 0.62
	var mi := _mesh_node(stone, Color(0.55, 0.54, 0.52), Vector3(0, s * 0.28, 0))
	mi.scale = Vector3(1.15, 1.0, 0.9)
	root.add_child(mi)
	return root


static func _log(fp: Vector2) -> Node3D:
	var root := Node3D.new()
	var length := maxf(fp.x, fp.y) * 0.8
	var trunk := CylinderMesh.new()
	trunk.top_radius = length * 0.09
	trunk.bottom_radius = length * 0.09
	trunk.height = length
	var mi := _mesh_node(trunk, Color(0.48, 0.34, 0.20), Vector3(0, length * 0.09, 0))
	mi.rotation.z = PI / 2.0
	if fp.y > fp.x:
		mi.rotation.y = PI / 2.0
	root.add_child(mi)
	return root


static func _pile(fp: Vector2) -> Node3D:
	var root := Node3D.new()
	var s := minf(fp.x, fp.y)
	for i in 3:
		var chunk := BoxMesh.new()
		chunk.size = Vector3(s * (0.35 - i * 0.06), s * 0.18, s * (0.30 - i * 0.05))
		var mi := _mesh_node(chunk, Color(0.5, 0.47, 0.43).darkened(i * 0.08),
			Vector3((i - 1) * s * 0.16, s * (0.09 + i * 0.11), (i % 2 - 0.5) * s * 0.2))
		mi.rotation.y = i * 0.6
		root.add_child(mi)
	return root


static func _nest(fp: Vector2) -> Node3D:
	var root := Node3D.new()
	var s := minf(fp.x, fp.y)
	var mound := SphereMesh.new()
	mound.radius = s * 0.5
	mound.height = s * 0.45
	root.add_child(_mesh_node(mound, Color(0.20, 0.16, 0.13), Vector3(0, s * 0.16, 0)))
	for i in 4:
		var spike := CylinderMesh.new()
		spike.top_radius = 0.0
		spike.bottom_radius = s * 0.05
		spike.height = s * 0.55
		var angle := i * TAU / 4.0 + 0.4
		var mi := _mesh_node(spike, Color(0.75, 0.72, 0.65),
			Vector3(cos(angle) * s * 0.3, s * 0.42, sin(angle) * s * 0.3))
		mi.rotation.x = 0.35 * sin(angle)
		mi.rotation.z = 0.35 * cos(angle)
		root.add_child(mi)
	return root
