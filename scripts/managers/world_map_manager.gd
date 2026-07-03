extends Node
## WorldMapManager — the world map layer and territory system (autoload).
##
## Tracks every LocationDefinition's state:
##   LOCKED     requirements not yet met
##   AVAILABLE  can be raided
##   CLEARED    beaten (one-time locations)
##   CONTROLLED beaten + expands player territory (unlocks_territory)
##
## and runs expeditions: send a squad → travel out (game ticks) → the
## battle auto-resolves via CombatManager (auto mode, no abilities) →
## rewards + territory update → travel home → squad returns to the pool.
## One expedition at a time for the prototype; the _expedition dict is
## already shaped to become a list later.

enum LocationState { LOCKED, AVAILABLE, CLEARED, CONTROLLED }

const PHASE_TRAVEL_OUT := "travel_out"
const PHASE_COMBAT := "combat"
const PHASE_RETURN := "return"

var _states: Dictionary = {}      # location id -> LocationState
## Active expedition: {} or {"location_id", "phase", "timer", "squad": Array}
var _expedition: Dictionary = {}


func _ready() -> void:
	SaveManager.register_section("world_map", self)
	EventBus.game_tick.connect(_tick)


func reset() -> void:
	_expedition = {}
	_states.clear()
	for def in DataManager.all_locations():
		_states[def.id] = LocationState.AVAILABLE if def.requires.is_empty() else LocationState.LOCKED


# ── Queries ──────────────────────────────────────────────────────────────

func state_of(location_id: String) -> LocationState:
	return _states.get(location_id, LocationState.LOCKED) as LocationState


func is_conquered(location_id: String) -> bool:
	return state_of(location_id) >= LocationState.CLEARED


func has_active_expedition() -> bool:
	return not _expedition.is_empty()


## {} when idle, else the active expedition (read-only by convention).
func expedition() -> Dictionary:
	return _expedition


# ── Expeditions ──────────────────────────────────────────────────────────

func can_send_squad(location_id: String) -> bool:
	return state_of(location_id) == LocationState.AVAILABLE and not has_active_expedition()


func send_squad(location_id: String, squad: Array) -> bool:
	if not can_send_squad(location_id) or squad.is_empty():
		return false
	var def := DataManager.get_location(location_id)
	if def == null:
		return false
	for survivor in squad:
		survivor.on_mission = true
	_expedition = {
		"location_id": location_id,
		"phase": PHASE_TRAVEL_OUT,
		"timer": def.travel_time,
		"squad": squad,
	}
	EventBus.notify("Squad heading to %s…" % def.display_name, 2)
	EventBus.expedition_updated.emit(location_id, PHASE_TRAVEL_OUT)
	return true


func _tick() -> void:
	if _expedition.is_empty() or _expedition.phase == PHASE_COMBAT:
		return
	_expedition.timer = float(_expedition.timer) - TimeManager.TICK_INTERVAL
	if _expedition.timer > 0.0:
		return
	if _expedition.phase == PHASE_TRAVEL_OUT:
		_begin_battle()
	elif _expedition.phase == PHASE_RETURN:
		_finish_expedition()


func _begin_battle() -> void:
	_expedition.phase = PHASE_COMBAT
	var def := DataManager.get_location(str(_expedition.location_id))
	# Modal screens (world map, menus) sit above the battle layer.
	UIManager.close_all_screens()
	EventBus.expedition_updated.emit(def.id, PHASE_COMBAT)
	EventBus.notify("Squad arrived at %s — contact!" % def.display_name, 1)
	# Auto mode: the fight plays itself out, no abilities.
	CombatManager.launch_battle(def.to_mission_spec(), _expedition.squad, true, _on_battle_resolved)


func _on_battle_resolved(result: Dictionary) -> void:
	var def := DataManager.get_location(str(_expedition.location_id))

	if result.outcome == "victory":
		_set_state(def.id,
			LocationState.CONTROLLED if def.unlocks_territory else LocationState.CLEARED)
		_unlock_dependents()

	# Only survivors still on the roster march home.
	var squad: Array = _expedition.squad
	squad = squad.filter(func(s): return SurvivorManager.all().has(s))
	_expedition.squad = squad
	EventBus.expedition_finished.emit(def.id, result)

	if squad.is_empty():
		# Nobody left to return.
		_expedition = {}
		EventBus.expedition_updated.emit(def.id, "")
		return
	_expedition.phase = PHASE_RETURN
	_expedition.timer = def.travel_time
	EventBus.expedition_updated.emit(def.id, PHASE_RETURN)


func _finish_expedition() -> void:
	var location_id := str(_expedition.location_id)
	for survivor in _expedition.squad:
		survivor.on_mission = false
	_expedition = {}
	EventBus.notify("Squad returned home.", 2)
	EventBus.workers_changed.emit(SurvivorManager.available_workers(), SurvivorManager.count())
	EventBus.expedition_updated.emit(location_id, "")


# ── Territory graph ──────────────────────────────────────────────────────

func _set_state(location_id: String, new_state: LocationState) -> void:
	if _states.get(location_id) == new_state:
		return
	_states[location_id] = new_state
	EventBus.location_state_changed.emit(location_id, new_state)
	if new_state == LocationState.CONTROLLED:
		EventBus.notify("Territory expanded: %s is under your control!" % DataManager.get_location(location_id).display_name, 2)


## Flip LOCKED locations whose requirements are now all met.
func _unlock_dependents() -> void:
	for def in DataManager.all_locations():
		if state_of(def.id) != LocationState.LOCKED:
			continue
		var met := true
		for required_id in def.requires:
			if not is_conquered(required_id):
				met = false
				break
		if met:
			_set_state(def.id, LocationState.AVAILABLE)
			EventBus.notify("New location available: %s" % def.display_name, 2)


# ── Save contract ────────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	var expedition_data := {}
	if not _expedition.is_empty():
		var squad_uids := []
		for survivor in _expedition.squad:
			squad_uids.append(survivor.uid)
		expedition_data = {
			"location_id": _expedition.location_id,
			# A save can't happen mid-battle (world time is frozen), but
			# clamp to a travel phase defensively.
			"phase": _expedition.phase if _expedition.phase != PHASE_COMBAT else PHASE_TRAVEL_OUT,
			"timer": maxf(float(_expedition.timer), 1.0),
			"squad_uids": squad_uids,
		}
	return {"states": _states.duplicate(), "expedition": expedition_data}


func apply_save_data(data: Dictionary) -> void:
	reset()  # rebuild the graph, then overlay saved states
	var saved_states: Dictionary = data.get("states", {})
	for location_id in saved_states:
		_states[location_id] = int(saved_states[location_id])

	_expedition = {}
	var expedition_data: Dictionary = data.get("expedition", {})
	if not expedition_data.is_empty():
		var squad := []
		for uid in expedition_data.get("squad_uids", []):
			var survivor = SurvivorManager.get_by_uid(str(uid))
			if survivor != null:
				survivor.on_mission = true
				squad.append(survivor)
		if not squad.is_empty():
			_expedition = {
				"location_id": str(expedition_data.location_id),
				"phase": str(expedition_data.phase),
				"timer": float(expedition_data.timer),
				"squad": squad,
			}
