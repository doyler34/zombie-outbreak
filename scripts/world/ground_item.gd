class_name GroundItem
extends Node3D
## A loose item lying in the world, waiting to be picked up.
##
## Pure presentation + one Interactable: a small tinted marker with the
## item's icon floating over it. Picking up routes through
## InventoryManager.add_item — if only part of the stack fits, the rest
## stays on the ground; if nothing fits the manager shows the
## "Inventory full!" toast and the pickup stays put.
##
## Spawned by GroundItems (world-gen scatter, dropped slots, future
## loot). Not saved yet — pickups are transient set dressing until a
## loot persistence pass.

const BOB_HEIGHT := 0.12
const BOB_SPEED := 2.2

var item_id: String
var count: int = 1

var _icon: Label3D
var _time := 0.0


func setup(id: String, amount: int) -> void:
	item_id = id
	count = amount
	var def := DataManager.get_item(id)

	# Small tinted marker so pickups read even if the emoji font ever
	# fails on a device; the icon floats above it.
	var marker := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.35, 0.35, 0.35)
	marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = def.icon_color if def != null else Color.WHITE
	mat.roughness = 0.6
	marker.material_override = mat
	marker.position.y = 0.25
	marker.rotation_degrees = Vector3(35, 45, 0)
	add_child(marker)

	_icon = Label3D.new()
	_icon.text = def.icon if def != null else "❔"
	_icon.font_size = 96
	_icon.pixel_size = 0.01
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.no_depth_test = true
	_icon.position.y = 0.85
	add_child(_icon)

	var label := "%s ×%d" % [def.display_name, count] if count > 1 \
		else (def.display_name if def != null else id)
	Interactable.attach(self, "Pick up %s" % label,
		DataManager.settings.interaction_reach + 0.6, _on_interacted)


func _process(delta: float) -> void:
	_time += delta
	if _icon != null:
		_icon.position.y = 0.85 + sin(_time * BOB_SPEED) * BOB_HEIGHT


func _on_interacted(_actor: Node3D) -> void:
	var added := InventoryManager.add_item(item_id, count)
	if added <= 0:
		return  # add_item already toasted "Inventory full!"
	var def := DataManager.get_item(item_id)
	EventBus.notify("+%d %s %s" % [added,
		def.icon if def != null else "",
		def.display_name if def != null else item_id], 2)
	count -= added
	if count <= 0:
		queue_free()
