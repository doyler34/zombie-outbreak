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

# ── Base building (modular pieces) ───────────────────────────────────────
signal build_mode_changed(active: bool)
## The build menu chose a piece to place (null clears the preview).
signal piece_selected(piece: BuildingPiece)
signal piece_placed(entity: BasePieceEntity)
signal piece_removed(entity: BasePieceEntity)

# ── Obstacles / clearing ─────────────────────────────────────────────────
signal obstacle_selected(entity: ObstacleEntity)
signal obstacle_deselected()
signal obstacle_clear_started(entity: ObstacleEntity, workers: int)
signal obstacle_cleared(entity: ObstacleEntity, rewards: Dictionary)
## Fired when clearing starts on an "infested" obstacle — the hook for
## the future combat system.
signal obstacle_infestation_triggered(entity: ObstacleEntity)

# ── Interaction ──────────────────────────────────────────────────────────
## Something in the world was interacted with. The Interactable's own
## `interacted` signal drives the behaviour; this global echo is for
## listeners that don't own the object (tutorial, audio, quests).
signal interaction_performed(interactable: Interactable, actor: Node3D)

# ── Inventory / hotbar ───────────────────────────────────────────────────
## Backpack slots changed (add/remove/move/drop). UI redraws from
## InventoryManager state; the payload stays empty on purpose.
signal inventory_changed()
## Hotbar slots changed (assign/use/drop).
signal hotbar_changed()
## A different hotbar slot became active (-1 / null = hands empty).
signal hotbar_selection_changed(index: int, item: ItemDefinition)
## A consumable/gear item was activated (audio, tutorial, quests...).
signal item_used(item: ItemDefinition)
## The Commander gathered from a resource node (tree, rock, crate...).
signal resource_gathered(node: Node3D, item_id: String, amount: int)
## A slot was thrown away — GroundItems turns it into a world pickup.
signal item_dropped(item_id: String, count: int)
## A recipe was successfully crafted (tutorial, quests, audio...).
signal item_crafted(recipe: RecipeDefinition, result: ItemDefinition)

# ── Combat / missions ────────────────────────────────────────────────────
signal mission_started(zone: ObstacleEntity)
## result: {"outcome", "zombies_killed", "dead", "injured", "rewards",
## "xp_each", "rescued"} — see CombatManager.
signal mission_completed(result: Dictionary)

# ── World map / territory ────────────────────────────────────────────────
## phase: "travel_out" / "combat" / "return" / "" (expedition over).
signal expedition_updated(location_id: String, phase: String)
signal expedition_finished(location_id: String, result: Dictionary)
signal location_state_changed(location_id: String, state: int)

# ── Survivors ────────────────────────────────────────────────────────────
signal workers_changed(available: int, total: int)
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
