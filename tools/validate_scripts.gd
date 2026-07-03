extends SceneTree
## CI validation entry point:
##   godot --headless --path . -s tools/validate_scripts.gd
##
## Force-loads every script, scene and resource in the project so any
## GDScript parse/compile error, broken scene reference or corrupt .tres
## is printed (as SCRIPT ERROR / ERROR lines) instead of silently
## shipping a build where features "don't load". The CI step greps the
## output and fails the build if anything is wrong.

var _failures: int = 0


func _initialize() -> void:
	var count := 0
	for dir in ["res://scripts", "res://scenes", "res://data"]:
		count += _load_dir(dir)
	print("[validate] loaded %d resources, %d failures" % [count, _failures])
	quit(1 if _failures > 0 else 0)


func _load_dir(dir_path: String) -> int:
	var loaded := 0
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := dir_path.path_join(entry)
		if dir.current_is_dir():
			loaded += _load_dir(path)
		elif entry.get_extension() in ["gd", "tscn", "tres"]:
			var res: Resource = load(path)
			if res == null:
				push_error("[validate] FAILED to load: %s" % path)
				_failures += 1
			else:
				# Instantiate scenes too — catches script attach errors.
				if res is PackedScene:
					var node: Node = (res as PackedScene).instantiate()
					if node == null:
						push_error("[validate] FAILED to instantiate: %s" % path)
						_failures += 1
					else:
						node.free()
			loaded += 1
		entry = dir.get_next()
	return loaded
