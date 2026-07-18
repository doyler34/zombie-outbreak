class_name BasePieceEntity
extends StaticBody3D
## One placed modular building piece in the world.
##
## Deliberately thin: BaseManager owns all bookkeeping (occupancy,
## saving, navigation edges); this node is the piece's physical presence
## — fitted visual, shared colliders, health, and (for openable pieces
## like door leafs) the hinge state + Commander interaction. Meshes and
## collision shapes are shared per piece type, so a thousand walls cost
## a thousand cheap instances, not a thousand resources.

## Hinge swing (rad) and animation time for openable pieces.
const OPEN_ANGLE := -PI / 2.0
const SWING_SECONDS := 0.3

var piece: BuildingPiece
## The spot this piece occupies (see PiecePlacement for the format).
var spot: Dictionary
var health: int
## Openable pieces only; doors default closed.
var is_open: bool = false

var _hinge: Node3D
var _interactable: Interactable
var _swing_tween: Tween


func setup(new_piece: BuildingPiece, new_spot: Dictionary) -> void:
	piece = new_piece
	spot = new_spot
	health = new_piece.max_health
	transform = PiecePlacement.spot_transform(new_piece, new_spot)

	var visual := PiecePlacement.build_visual(new_piece)
	# Deterministic per-spot colour variation (survives save/load — the
	# spot IS the seed), so wall runs don't read as copy-paste.
	if new_piece.variation_tints.size() > 0:
		var tint: Color = new_piece.variation_tints[
			absi(hash(new_spot)) % new_piece.variation_tints.size()]
		_apply_tint(visual, PiecePlacement.variation_material(tint))

	if new_piece.openable:
		# Swing around the leaf's own left edge: hinge sits on it, the
		# visual is offset back so the closed pose renders identically.
		var left := PiecePlacement.fitted_aabb(new_piece).position.x
		_hinge = Node3D.new()
		_hinge.position = Vector3(left, 0, 0)
		visual.position = Vector3(-left, 0, 0)
		_hinge.add_child(visual)
		add_child(_hinge)
		_interactable = Interactable.attach(self, "Open Door",
			DataManager.settings.interaction_reach,
			func(_actor: Node3D) -> void: set_open(not is_open))
	else:
		add_child(visual)

	match new_piece.collision:
		"box":
			var shape := CollisionShape3D.new()
			shape.shape = PiecePlacement.collision_shape(new_piece)
			shape.position = PiecePlacement.fitted_aabb(new_piece).get_center()
			add_child(shape)
		"frame":
			for part: Dictionary in PiecePlacement.frame_shapes(new_piece):
				var post := CollisionShape3D.new()
				post.shape = part.shape
				post.position = part.position
				add_child(post)


## Grid contract (WorldManager occupancy, cell pieces only): pieces
## block other construction on their cells but never movement — a
## foundation is a floor you walk on.
func blocks_building() -> bool:
	return true


func blocks_movement() -> bool:
	return false


## Open/close an openable piece: 90° hinge swing, edge block follows
## (closed door stops the Commander, survivors and zombies; open door
## and bare doorways let everyone through). [param animate] false snaps
## instantly (save restore).
func set_open(open: bool, animate: bool = true) -> void:
	if not piece.openable or is_open == open:
		return
	is_open = open
	if _interactable != null:
		_interactable.prompt = "Close Door" if open else "Open Door"
	if spot.level == 0 and piece.blocks_movement:
		if open:
			WorldManager.unblock_edge(spot.edge)
		else:
			WorldManager.block_edge(spot.edge, self)
	var target := OPEN_ANGLE if open else 0.0
	if _swing_tween != null:
		_swing_tween.kill()
	if animate and is_inside_tree():
		_swing_tween = create_tween()
		_swing_tween.tween_property(_hinge, "rotation:y", target, SWING_SECONDS) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_hinge.rotation.y = target


## Future combat hook: chip health, collapse at zero.
func apply_damage(amount: int) -> void:
	health = maxi(health - amount, 0)
	if health == 0:
		BaseManager.remove_piece(self)


func get_save_data() -> Dictionary:
	var out := {
		"id": piece.id,
		"p": spot.placement,
		"lv": spot.level,
		"hp": health,
	}
	if spot.placement == "cell":
		out["x"] = spot.cell.x
		out["z"] = spot.cell.y
	else:
		var edge: Vector3i = spot.edge
		out["x"] = edge.x
		out["z"] = edge.y
		out["a"] = edge.z
	if is_open:
		out["open"] = true  # absent (old saves) = closed
	return out


func _apply_tint(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_apply_tint(child, material)
