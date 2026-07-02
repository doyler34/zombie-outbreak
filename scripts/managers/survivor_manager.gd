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
	var survivor_name: String = ""
	var skill: String = ""
	var health: int = 100
	var hunger: int = 100
	var mood: String = "Neutral"
	## Building id this survivor works at ("" = unassigned).
	var assigned_building: String = ""

	func to_dict() -> Dictionary:
		return {
			"name": survivor_name, "skill": skill, "health": health,
			"hunger": hunger, "mood": mood, "assigned": assigned_building,
		}

	static func from_dict(d: Dictionary) -> Survivor:
		var s := Survivor.new()
		s.survivor_name = str(d.get("name", "Unknown"))
		s.skill = str(d.get("skill", ""))
		s.health = int(d.get("health", 100))
		s.hunger = int(d.get("hunger", 100))
		s.mood = str(d.get("mood", "Neutral"))
		s.assigned_building = str(d.get("assigned", ""))
		return s


var _roster: Array[Survivor] = []


func _ready() -> void:
	SaveManager.register_section("survivors", self)


func reset() -> void:
	_roster.clear()


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
	return s


# ── Save contract ────────────────────────────────────────────────────────

func get_save_data() -> Array:
	var out := []
	for s in _roster:
		out.append(s.to_dict())
	return out


func apply_save_data(data: Array) -> void:
	_roster.clear()
	for entry: Dictionary in data:
		_roster.append(Survivor.from_dict(entry))
	EventBus.population_changed.emit(count(), population_cap())
