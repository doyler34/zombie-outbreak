extends SceneTree
## CI animation smoke test + diagnostic:
##   godot --headless --path . -s tools/debug_animations.gd
##
## Builds the Commander exactly like the game does, plays the resolved
## idle clip and verifies bones actually move. Prints the imported node
## trees and track paths so a failure shows WHY (wrong node path, no
## clips merged, unresolved tracks...) instead of a silent T-pose on
## device. The CI step greps for ANIMATION_OK / ANIMATION_BROKEN.

func _initialize() -> void:
	print("=== imported character scene tree ===")
	var char_scene: PackedScene = load("res://assets/characters/universal_base/Superhero_Male_FullBody.gltf")
	var char_inst: Node = char_scene.instantiate()
	_dump(char_inst, 0)
	char_inst.free()

	print("=== imported UAL2 library scene tree ===")
	var lib_scene: PackedScene = load("res://assets/animations/UAL2_Standard.glb")
	var lib_inst: Node = lib_scene.instantiate()
	_dump(lib_inst, 0)
	var lib_player := ModelFactory.find_animation_player(lib_inst)
	if lib_player != null:
		print("lib player root_node=", lib_player.root_node)
		var names := lib_player.get_animation_list()
		print("lib clips=", names.size())
		if names.size() > 1:
			var sample: Animation = lib_player.get_animation(names[1])
			print("sample clip '", names[1], "' tracks=", sample.get_track_count())
			for t in mini(3, sample.get_track_count()):
				print("  track ", t, " type=", sample.track_get_type(t),
					" path=", sample.track_get_path(t))
	lib_inst.free()

	print("=== combatant_model end-to-end ===")
	var def: CombatantDefinition = load("res://data/characters/commander.tres")
	var model := ModelFactory.combatant_model(def)
	root.add_child(model)

	var player := ModelFactory.find_animation_player(model)
	if player == null:
		print("no AnimationPlayer at all -> ANIMATION_BROKEN")
		quit(1)
		return
	print("player parent=", player.get_parent().get_class(),
		" root_node=", player.root_node,
		" libraries=", player.get_animation_library_list())

	# Deep dump: exactly which link between the source glb and
	# has_animation() drops the clips.
	for lib_name in player.get_animation_library_list():
		var lib := player.get_animation_library(lib_name)
		var clip_names := lib.get_animation_list()
		print("library '", lib_name, "': ", clip_names.size(),
			" clips: ", clip_names)
	print("player.get_animation_list()[0..7]=",
		player.get_animation_list().slice(0, 7))
	print("has 'shared/Idle_FoldArms_Loop' = ",
		player.has_animation("shared/Idle_FoldArms_Loop"))
	var skel_probe := _find_skeleton(model)
	print("char find_bone pelvis=", skel_probe.find_bone("pelvis"),
		" DEF-hips=", skel_probe.find_bone("DEF-hips"))
	var source: Array = ModelFactory._libraries_from("res://assets/animations/UAL2_Standard.glb")
	print("source libs from cache=", source.size())
	if source.size() > 0:
		var src_lib: AnimationLibrary = source[0]
		print("source lib clip count=", src_lib.get_animation_list().size())

	var idle := ModelFactory.find_anim(player, ModelFactory.IDLE_CANDIDATES)
	var walk := ModelFactory.find_anim(player, ModelFactory.WALK_CANDIDATES)
	print("resolved idle='", idle, "' walk='", walk, "'")
	if idle == "":
		print("no idle clip resolved -> ANIMATION_BROKEN")
		quit(1)
		return

	var clip: Animation = player.get_animation(idle)
	print("idle clip length=", clip.length, " tracks=", clip.get_track_count())
	for t in mini(3, clip.get_track_count()):
		print("  remapped track ", t, " path=", clip.track_get_path(t))

	var skeleton := _find_skeleton(model)
	var bone := skeleton.find_bone("hand_l")
	var pos_before: Vector3 = skeleton.get_bone_pose_position(bone)
	var rot_before: Quaternion = skeleton.get_bone_pose_rotation(bone)

	player.play(idle)
	player.advance(0.4)

	var pos_after: Vector3 = skeleton.get_bone_pose_position(bone)
	var rot_after: Quaternion = skeleton.get_bone_pose_rotation(bone)
	var moved := pos_before.distance_to(pos_after) > 0.0001 \
		or not rot_before.is_equal_approx(rot_after)
	print("hand_l pose before=", pos_before, " ", rot_before)
	print("hand_l pose after =", pos_after, " ", rot_after)
	print("ANIMATION_OK" if moved else "ANIMATION_BROKEN")
	quit(0 if moved else 1)


func _dump(node: Node, depth: int) -> void:
	if depth > 4:
		return
	print("  ".repeat(depth), "- ", node.name, " (", node.get_class(), ")")
	for child in node.get_children():
		_dump(child, depth + 1)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
