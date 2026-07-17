class_name BasePieceEntity
extends StaticBody3D
## One placed modular building piece in the world.
##
## Deliberately thin: BaseManager owns all bookkeeping (occupancy,
## saving, navigation edges); this node is the piece's physical presence
## — fitted visual, shared box collider, health. Meshes and collision
## shapes are shared per piece type, so a thousand walls cost a thousand
## cheap instances, not a thousand resources.

var piece: BuildingPiece
## The spot this piece occupies (see PiecePlacement for the format).
var spot: Dictionary
var health: int


func setup(new_piece: BuildingPiece, new_spot: Dictionary) -> void:
	piece = new_piece
	spot = new_spot
	health = new_piece.max_health
	transform = PiecePlacement.spot_transform(new_piece, new_spot)
	add_child(PiecePlacement.build_visual(new_piece))

	if new_piece.collision == "box":
		var shape := CollisionShape3D.new()
		shape.shape = PiecePlacement.collision_shape(new_piece)
		shape.position = PiecePlacement.fitted_aabb(new_piece).get_center()
		add_child(shape)


## Grid contract (WorldManager occupancy, cell pieces only): pieces
## block other construction on their cells but never movement — a
## foundation is a floor you walk on.
func blocks_building() -> bool:
	return true


func blocks_movement() -> bool:
	return false


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
	return out
