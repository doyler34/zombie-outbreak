extends Node
## SaveManager — versioned JSON persistence (autoload).
##
## Systems that want to be saved register a named section with a provider
## object implementing:
##     get_save_data() -> Variant      (Dictionary or Array)
##     apply_save_data(data) -> void
##
## SaveManager itself knows nothing about game content — adding a new
## persistent system is one register_section() call. Files are JSON in
## user://saves/, with a version number and a migration hook so old saves
## keep working as the format evolves.

const SAVE_DIR := "user://saves"

var _providers: Dictionary = {}  # section name -> provider Object


func register_section(section: String, provider: Object) -> void:
	_providers[section] = provider


# ── API ──────────────────────────────────────────────────────────────────

func save_game(slot: int = -1) -> bool:
	slot = _resolve_slot(slot)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var payload := {
		"version": DataManager.settings.save_version,
		"timestamp": Time.get_unix_time_from_system(),
		"sections": {},
	}
	for section in _providers:
		payload.sections[section] = _providers[section].get_save_data()

	var file := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] Cannot write save: %s" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	EventBus.save_completed.emit(slot)
	return true


func load_game(slot: int = -1) -> bool:
	slot = _resolve_slot(slot)
	var file := FileAccess.open(_slot_path(slot), FileAccess.READ)
	if file == null:
		return false
	var payload: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if payload == null or not payload is Dictionary:
		push_error("[SaveManager] Corrupt save in slot %d" % slot)
		return false

	payload = _migrate(payload)
	var sections: Dictionary = payload.get("sections", {})
	for section in _providers:
		if sections.has(section):
			_providers[section].apply_save_data(sections[section])
	EventBus.load_completed.emit(slot)
	return true


func has_save(slot: int = -1) -> bool:
	return FileAccess.file_exists(_slot_path(_resolve_slot(slot)))


func delete_save(slot: int = -1) -> void:
	slot = _resolve_slot(slot)
	if has_save(slot):
		DirAccess.remove_absolute(_slot_path(slot))


# ── Internal ─────────────────────────────────────────────────────────────

## Upgrade old save payloads to the current version, step by step.
## Add one `if` block per version bump.
func _migrate(payload: Dictionary) -> Dictionary:
	var version := int(payload.get("version", 1))
	# Example for a future format change:
	# if version < 2:
	#     payload.sections["survivors"] = ...transform...
	#     version = 2
	payload["version"] = version
	return payload


func _resolve_slot(slot: int) -> int:
	return DataManager.settings.default_save_slot if slot < 0 else slot


func _slot_path(slot: int) -> String:
	return SAVE_DIR.path_join("slot_%d.json" % slot)
