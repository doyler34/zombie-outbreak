extends Node
## EventBus — the global signal hub (autoload).
##
## Systems never call each other's UI or gameplay code directly; they emit
## signals here and interested systems subscribe. This keeps managers
## decoupled: you can add a new listener (analytics, tutorial, audio cue)
## without touching the emitter.
##
## Convention: past tense = something happened ("building_placed"),
## "*_requested" = someone is asking a system to do something.

# ── Game flow ────────────────────────────────────────────────────────────
signal game_state_changed(new_state: int, old_state: int)
signal world_ready()

# ── Resources ────────────────────────────────────────────────────────────
signal resource_changed(id: String, amount: int, change: int)
signal resources_spent(cost: Dictionary)

# ── Buildings ────────────────────────────────────────────────────────────
signal building_placement_started(definition: BuildingDefinition)
signal building_placement_ended(confirmed: bool)
signal building_placed(entity: BuildingEntity)
signal building_removed(entity: BuildingEntity)
signal building_selected(entity: BuildingEntity)
signal building_deselected()
signal building_construction_finished(entity: BuildingEntity)
signal building_upgraded(entity: BuildingEntity, new_level: int)

# ── Survivors ────────────────────────────────────────────────────────────
signal survivor_added(survivor)
signal survivor_removed(survivor)
signal population_changed(count: int, cap: int)

# ── Time ─────────────────────────────────────────────────────────────────
signal game_tick()  ## Once per in-game "beat" (about 1 real second).
signal day_passed(day: int)
signal night_started(day: int)
signal day_started(day: int)

# ── UI ───────────────────────────────────────────────────────────────────
signal notification_requested(text: String, type: int)

# ── Persistence ──────────────────────────────────────────────────────────
signal save_completed(slot: int)
signal load_completed(slot: int)


## Convenience wrapper so call sites read nicely.
func notify(text: String, type: int = 0) -> void:
	notification_requested.emit(text, type)
