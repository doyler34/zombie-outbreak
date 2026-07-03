extends Node
## SurvivorManager — the survivor roster framework (autoload).
##
## Provides the data model and lifecycle for survivors: generation from
## the name/skill tables in data/tables/survivor_names.json, a population
## cap derived from building effects, and persistence.
##
## Deliberately minimal: rescue missions, job assignment logic, needs and
## moods are future gameplay systems that plug in on top of this roster.

## One survivor. RefCounted (not Node) — survivors are pure data until a
## future system gives them presence in the world.
class Survivor:
	extends RefCounted
	## Stable identity for save references (expeditions, future jobs).
	var uid: String = ""
	var survivor_name: String = ""
	var skill: String = ""
	## Combat role id (SurvivorRoleDefinition in data/roles/).
	var role: String = "fighter"
	## Mission experience; levels derive from it (future progression).
	var xp: int = 0
	var health: int = 100
	var hunger: int = 100
	var mood: String = "Neutral"
	## Building id this survivor works at ("" = unassigned).
	var assigned_building: String = ""
	## True while travelling/fighting on a world-map expedition.
	var on_mission: bool = false

	func _init() -> void:
		uid = "%d-%06d" % [Time.get_ticks_usec(), randi() % 1000000]

	## Level derived from XP — 100 XP per level for the prototype.
	func level() -> int:
		return 1 + xp / 100

	func to_dict() -> Dictionary:
		return {
			"uid": uid, "name": survivor_name, "skill": skill, "role": role,
			"xp": xp, "health": health, "hunger": hunger, "mood": mood,
			"assigned": assigned_building, "on_mission": on_mission,
		}

	static func from_dict(d: Dictionary) -> Survivor:
		var s := Survivor.new()
		if d.has("uid"):
			s.uid = str(d.uid)
		s.survivor_name = str(d.get("name", "Unknown"))
		s.skill = str(d.get("skill", ""))
		s.role = str(d.get("role", "fighter"))
		s.xp = int(d.get("xp", 0))
		s.health = int(d.get("health", 100))
		s.hunger = int(d.get("hunger", 100))
		s.mood = str(d.get("mood", "Neutral"))
		s.assigned_building = str(d.get("assigned", ""))
		# on_mission is restored by WorldMapManager when it re-links the
		# expedition squad, so a stale flag can't strand anyone.
		return s


var _roster: Array[Survivor] = []
## Workers tied up in tasks (clearing, future expeditions). Not saved —
## each task re-reserves its crew when its own save section loads.
var _reserved_workers: int = 0


func _ready() -> void:
	SaveManager.register_section("survivors", self)


func reset() -> void:
	_roster.clear()
	_reserved_workers = 0
	# The founding crew — they arrive with the player, so the population
	# cap (which comes from housing) doesn't apply to them.
	for i in DataManager.settings.starting_survivors:
		_roster.append(generate_random())


# ── Roster ───────────────────────────────────────────────────────────────

func count() -> int:
	return _roster.size()


func population_cap() -> int:
	return BuildingManager.total_effect("population_cap")


func all() -> Array[Survivor]:
	return _roster


## Add a survivor if there is room. Returns false when at capacity.
func add(survivor: Survivor) -> bool:
	if count() >= population_cap():
		EventBus.notify("No room — build more housing!", 1)
		return false
	_roster.append(survivor)
	EventBus.survivor_added.emit(survivor)
	EventBus.population_changed.emit(count(), population_cap())
	return true


func remove(survivor: Survivor) -> void:
	_roster.erase(survivor)
	EventBus.survivor_removed.emit(survivor)
	EventBus.population_changed.emit(count(), population_cap())


func get_by_uid(uid: String) -> Survivor:
	for s in _roster:
		if s.uid == uid:
			return s
	return null


## Survivors free to join a combat squad (not away on an expedition).
func available_for_combat() -> Array[Survivor]:
	var out: Array[Survivor] = []
	for s in _roster:
		if not s.on_mission:
			out.append(s)
	return out


# ── Worker pool (clearing, future expeditions/jobs) ──────────────────────

## Survivors not currently committed to a task.
func available_workers() -> int:
	var away := 0
	for s in _roster:
		if s.on_mission:
			away += 1
	return count() - _reserved_workers - away


## Commit workers to a task. Returns false if not enough are free.
func reserve_workers(amount: int) -> bool:
	if amount <= 0:
		return true
	if amount > available_workers():
		return false
	_reserved_workers += amount
	EventBus.workers_changed.emit(available_workers(), count())
	return true


## Return workers to the available pool when their task ends.
func release_workers(amount: int) -> void:
	_reserved_workers = maxi(0, _reserved_workers - amount)
	EventBus.workers_changed.emit(available_workers(), count())


## Create a random survivor from the data tables (does not add them).
func generate_random() -> Survivor:
	var table: Dictionary = DataManager.get_table("survivor_names")
	var s := Survivor.new()
	if table:
		var firsts: Array = table.get("first_names", ["Alex"])
		var lasts: Array = table.get("last_names", ["Doe"])
		var skills: Array = table.get("skills", [])
		s.survivor_name = "%s %s" % [firsts.pick_random(), lasts.pick_random()]
		if not skills.is_empty():
			s.skill = str(skills.pick_random().get("id", ""))
	else:
		s.survivor_name = "Survivor %d" % (count() + 1)
	var roles := DataManager.all_roles()
	if not roles.is_empty():
		s.role = roles.pick_random().id
	return s


# ── Save contract ────────────────────────────────────────────────────────

func get_save_data() -> Array:
	var out := []
	for s in _roster:
		out.append(s.to_dict())
	return out


func apply_save_data(data: Array) -> void:
	_roster.clear()
	_reserved_workers = 0  # running tasks re-reserve their own crews
	for entry: Dictionary in data:
		_roster.append(Survivor.from_dict(entry))
	EventBus.population_changed.emit(count(), population_cap())
