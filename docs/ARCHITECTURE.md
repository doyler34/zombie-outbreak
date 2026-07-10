# Zombie Outbreak — Framework Architecture

A mobile-first, top-down strategy framework for Godot 4.7. This document
explains every major system, the reasoning behind its design, and how to
extend it.

Design inspiration:
- **godot-open-rts** — strict separation between global systems and the
  match/world scene, an input→gesture abstraction layer so gameplay code
  never reads raw events, and selection/command flow through signals.
- **Kenney Starter Kit City Builder** — data-driven structure catalog,
  ghost-preview grid placement with validity feedback, and a simple
  versioned save of placed structures.

Neither project was copied; their ideas were adapted for a 2D,
touch-first, commercial-scale codebase.

---

## The One-Paragraph Mental Model

**Autoload managers own all state. Scenes are disposable views.**
The world scene (`game_world.tscn`) can be freed and reloaded at any time
— every fact about the session (resources, buildings, survivors, clock)
lives in the managers and is reconstructed into whatever scene registers
itself. Managers never call each other's internals directly when a
reaction is expected; they emit signals on the `EventBus` and interested
systems subscribe. This is what makes the framework expandable: new
systems plug in by listening, not by editing existing code.

---

## Folder Layout

```
assets/            art, audio, shaders (no logic)
  animations/      shared animation library (Quaternius, CC0)
  audio/           music + sfx streams
  shaders/         .gdshader files
  textures/        buildings/, terrain/, ui art
data/              ALL game content and tuning (no code)
  settings/        game_settings.tres — every tunable number
  buildings/       one BuildingDefinition .tres per building
  characters/      commander.tres — the playable Commander's stats/model
  items/           one ItemDefinition .tres per inventory item
  recipes/         one RecipeDefinition .tres per crafting recipe
  obstacles/       one ObstacleDefinition .tres per obstacle type
  resources/       one ResourceDefinition .tres per resource
  roles/           one SurvivorRoleDefinition .tres per combat role
  zombies/         one ZombieDefinition .tres per enemy type
  locations/       one LocationDefinition .tres per world-map location
  tables/          loose JSON data (name pools, missions, world generation)
docs/              this file
scenes/
  main/            main_menu.tscn (entry scene)
  world/           game_world.tscn (the playable map)
  buildings/       building_entity.tscn
  ui/              modal screens (build menu, pause menu)
scripts/
  managers/        the 17 autoload singletons
  resources/       custom Resource classes (definition schemas)
  world/           world-scene behaviour (camera, placer, entities)
  ui/              UI framework + screens
```

Save files are written to `user://saves/` at runtime (never inside the
project), and user preferences to `user://settings.cfg`.

---

## The 17 Managers (autoload order matters)

Registration order in `project.godot` is dependency order: EventBus and
DataManager first because everything reads them; SaveManager before any
manager that registers a save section; GameManager last because it
orchestrates all the others.

### 1. EventBus (`event_bus.gd`)
Global signal hub. Systems emit facts ("building_placed") and requests
("notification_requested"); listeners subscribe. **Why:** decoupling.
The tutorial, analytics, audio cues and quests can all react to
`building_placed` without BuildingManager knowing they exist.

### 2. DataManager (`data_manager.gd`)
Loads `GameSettings` plus every definition `.tres` by scanning
`data/buildings/` and `data/resources/`, and every JSON table in
`data/tables/`. **Why scanning:** adding a building or resource is a
pure content operation — drop in a file, no registration code. This is
the backbone of the data-driven design.

### 3. SaveManager (`save_manager.gd`)
Versioned JSON persistence. Systems register a named section with an
object implementing `get_save_data()` / `apply_save_data()`. Contains a
`_migrate()` hook for upgrading old saves. **Why:** SaveManager knows
nothing about game content, so adding a persistent system is one
`register_section()` call — and save-format changes are handled in
exactly one place.

### 4. TimeManager (`time_manager.gd`)
The game clock: day counter, day/night phase, and two heartbeat signals —
`game_tick` (~1 s, drives construction/production/AI) and `day_passed`
(daily economy). Only runs in the PLAYING state, so pause and menus are
automatic. **Why signals instead of Timers everywhere:** one clock means
fast-forward, pause and offline-progress calculations have a single
authority.

### 5. ResourceManager (`resource_manager.gd`)
The player stockpile, keyed by `ResourceDefinition.id`. All mutation goes
through `add()` / `spend()` / `grant()` so caps are enforced and
`resource_changed` fires exactly once per change. `spend()` is atomic
across multi-resource costs. **Why:** a single choke point for economy
changes is what makes balancing, cheat detection and analytics possible
later.

### 6. WorldManager (`world_manager.gd`)
Grid math (world px ↔ cell) and cell occupancy, centered on the origin.
Deliberately knows nothing about *what* occupies a cell — buildings
today; props, blockers and territory expansion later use the same API.

### 7. SurvivorManager (`survivor_manager.gd`)
The survivor roster framework: random generation from data tables,
population cap derived from building effects, persistence. Survivors are
pure data (`RefCounted`) until a future system gives them world presence.

### 8. InventoryManager (`inventory_manager.gd`)
The Commander's backpack + quick-use hotbar. Fixed slot arrays of
`{"id", "count"}` stacks; all rules (stacking limits, hotbar type
restrictions, merge/swap moves, select-to-equip, use-to-consume) live
here so the hotbar and inventory screen are dumb views redrawn on
`inventory_changed` / `hotbar_changed`. Items are ItemDefinition .tres
files in `data/items/` — future gathering, looting, combat and crafting
plug in through `add_item()` / `remove_item()` / `equipped_weapon()`.

### 9. CraftingManager (`crafting_manager.gd`)
Turns inventory items into other items via RecipeDefinitions
(`data/recipes/`). Pure rules — missing()/can_craft()/craft() count
ingredients across backpack + hotbar and route results through
InventoryManager, so stacking and capacity rules apply unchanged. The
crafting screen is a dumb view; future crafting stations just filter
recipes by RecipeDefinition.station.

### 10. BuildingManager (`building_manager.gd`)
Owns every placed `BuildingEntity`: placement validation + payment,
upgrades, removal, selection, daily production, passive effect totals
(`total_effect("defense")`), and building save data. The world scene
registers a container node on load; the manager spawns entities into it.

### 11. ObstacleManager (`obstacle_manager.gd`)
Natural obstacles (trees, rocks, debris, ...) and the clearing loop:
procedural scatter on new maps from `data/tables/world_generation.json`,
timed clearing tasks that cost resources, optionally use workers (each
assigned worker speeds the task; workers are reserved until it ends),
grant rewards, and permanently free build space. Future hooks are wired
in, not bolted on: `required_tech` gates clearing until a research
system answers `is_tech_unlocked()`; the `infested` tag emits
`obstacle_infestation_triggered` for a combat system to intercept;
`finish_clearing_now()` is the premium speed-up entry point;
`regrow_days` respawns vegetation via `day_passed`. Blocking is
per-definition (`blocks_building` / `blocks_movement`), resolved by
WorldManager's `is_area_buildable` / `is_cell_walkable` through a
duck-typed occupant contract — so decorative, walkable and solid
obstacles all use the same code path.

### 12. CombatManager (`combat_manager.gd`)
Squad missions against "infested" danger zones. Flow: tap a zone → the
HUD shows risk/enemy estimate → squad select screen → BattleScene
overlay (a CanvasLayer above the frozen world — no scene change; a
full-screen SubViewport renders a 3D arena with an angled orthographic
camera, and the UI draws on top) where survivor and zombie character
models fight automatically — walk/attack/die animations from the
imported .glb rig, billboard health bars, floating damage numbers,
while the player uses abilities → the outcome is resolved back into the
settlement: injuries
(roster health), deaths, XP, rolled rewards with role bonuses
(Scavenger loot, Engineer rewards), rescue chances, and zone removal.
Mission composition lives in `data/tables/missions.json`; combat stats
in `data/roles/` and `data/zombies/` (both extend CombatantDefinition,
so units share one code path). The ability bar is a list of
CombatAbility subclasses — new abilities are one small class each.

### 13. WorldMapManager (`world_map_manager.gd`)
The Last-Day-on-Earth-style world layer. Fixed LocationDefinitions form
a territory graph via their `requires` lists; states are LOCKED →
AVAILABLE → CLEARED (or CONTROLLED for locations with
`unlocks_territory`, which expand player territory and unlock their
dependents). Expeditions run on game ticks: send squad (members flagged
on_mission and excluded from other squads/worker pools) → travel out →
CombatManager auto-battle (no abilities) → rewards + territory update →
travel home. One expedition at a time for the prototype; the state is
already shaped as data so multiple simultaneous squads is a small
change. Locations carry future hooks: `resource_bonus` for controlled
income, and the state enum supports event/story locations.

### 14. AudioManager (`audio_manager.gd`)
Creates Music/SFX buses at runtime, a round-robin SFX player pool (safe
to spam on mobile), music crossfade, and volume persistence separate
from game saves.

### 15. InputManager (`input_manager.gd`)
Translates raw touch/mouse events into gestures: `tapped`,
`long_pressed`, `drag_updated`, `zoom_requested`. Uses
`_unhandled_input`, so any UI Control that accepts an event
automatically blocks world input — no "is pointer over UI" checks
anywhere. **Why:** gameplay code written against gestures works
identically on Android touch and desktop mouse, and a replay/AI system
can emit the same signals.

### 16. UIManager (`ui_manager.gd`)
Persistent CanvasLayers that survive scene changes: a modal screen stack
(`push_screen`/`pop_screen`), toast notifications, and the fade
transition overlay. Screens extend `UIScreen` for consistent open/close
behaviour.

### 17. GameManager (`game_manager.gd`)
Top-level state machine (MENU/LOADING/PLAYING/PAUSED) and the only
system that changes scenes. New-game/continue flow: reset all session
managers → load world scene → world calls `notify_world_ready()` →
pending save is applied → state becomes PLAYING. Also owns autosave.

---

## World Scene (`scenes/world/game_world.tscn`) — orthographic 3D

Clash-style presentation: a Node3D world under an orthogonal Camera3D
pitched −55° with a 45° diagonal yaw, and a shadow-casting sun.
Disposable view over manager state:

- **Ground** — one plane sized to the world rect with a world-space
  two-tone tile shader aligned to the gameplay grid (bright and
  readable, no photo textures).
- **ModelFactory** — builds every entity visual: definitions with a
  `model` (.glb PackedScene) get the real asset auto-fitted to their
  footprint and grounded; everything else gets a chunky primitive
  placeholder (house, tree, rock, pile, nest...) so content is playable
  before art exists.
- **BuildingPlacer** — translucent ghost model + green/red footprint
  quad, tap to position, rotate/confirm/cancel via HUD.
- **Commander** — the player's directly-controlled character (hybrid
  builder/survival gameplay). Steered by the on-screen MovementJoystick
  or WASD/arrows, camera-relative on the ground plane; movement respects
  `WorldManager.is_cell_walkable` per axis so it slides along building
  edges. Model + stats come from `data/characters/commander.tres`
  (a CombatantDefinition). Locomotion only for now — no combat or
  inventory.
- **CameraController** — a rig on the ground plane: follows the
  Commander through its smoothing; drag pans along camera-relative XZ
  axes and pauses the follow (it resumes when the Commander moves),
  pinch/wheel changes orthographic size, clamped to world bounds.
- **MovementJoystick** (HUDLayer) — fixed bottom-left touch joystick,
  drawn with `_draw`. As a Control it consumes its own touches, so
  steering never pans the camera. The Commander polls its `direction`.
- **Interaction framework** — `Interactable` is a component: attach it
  to any world object (a one-liner via `Interactable.attach`) with a
  prompt and a per-object range, connect its `interacted` signal, and
  the object is interactable — behaviour lives with the owner, never in
  the player. `InteractionController` picks the nearest in-range
  component around the Commander; the HUD's `InteractButton`
  (bottom-right, desktop E key) shows the prompt and triggers it.
  Buildings open their management panel (gates toggle open/closed and
  become walkable), obstacles show placeholder messages, and
  `SurvivorNpcs` spawns a talkable `SurvivorNPC` per roster survivor.
  NPCs are alive: they trail the Commander in a loose ring until the
  Capital is built, then roam walkable cells around it, using the same
  per-axis wall sliding as the Commander. Every trigger also echoes
  globally as `EventBus.interaction_performed` for future
  tutorial/quest listeners. Character animation names are resolved per
  model (`ModelFactory.find_anim`), and the CC0 Quaternius animation
  libraries in `assets/animations/` (UAL1 on the Rigify rig, UAL2 on
  the UE-mannequin rig, incl. zombie/farming/chopping clips) auto-merge
  into any character whose skeleton matches — Kenney minis keep their
  built-in clips.
- **Elevation** — `Heightfield` is deterministic authored noise:
  gentle rolling hills that flatten across the HQ clearing (from the
  region layout). `WorldDecorator` builds the terrain mesh from it and
  registers it on `WorldManager`, whose `ground_height()` /
  `cell_to_world()` / `area_center()` ground EVERYTHING — characters,
  props, pickups, camera focus and tap raycasts all stand on the same
  surface the renderer draws. Amplitude is a GameSettings knob
  (0 = flat); a future terrain backend swaps the sampling source only.
- **Handcrafted region** — `RegionMap` loads
  `data/tables/region_layout.json`: authored zone circles (HQ clearing,
  dense forest, rocky ridge, campsite, resource field, town entrance,
  reserved expansion space), painted roads/footpaths and the HQ
  concrete pad. `WorldDecorator` rasterizes that layout into a splat
  map the ground shader blends (grass base + dirt/mud, gravel, cracked
  asphalt, concrete — all procedural detail, no ground textures), and
  plants instanced foliage (MultiMesh grass/flowers, one draw call per
  type) with per-zone density weights, kept off pavement.
  `ObstacleManager`'s scatter is zone-aware too — trees fill forests,
  rocks the ridge, crates the campsite. `QualityProfile` scales foliage
  counts, draw distance and sun shadows down on Android. The layout is
  renderer-agnostic: a future terrain backend (e.g. Terrain3D) replaces
  only the painting/mesh, not the design data or queries.
- **Gathering + ground items** — gatherable data lives on
  ObstacleDefinition (`gather_item/stock/yield/time/tool/verb/anim`):
  interacting with a tree/rock/scrap pile/crate runs auto-repeating
  timed cycles that feed the Commander's backpack, prefer the ideal
  tool (any equipped tool unlocks tool-gated nodes; the named one is
  30% faster), play the node's action clip on the Commander
  (`play_action`), stop when they walk away, and deplete the node into
  the regrowth queue. `GroundItems` scatters loose pickups on new maps
  (world_generation.json "ground_items"), respawns dropped slots at the
  Commander's feet, and each `GroundItem` is a bobbing icon with a
  "Pick up" Interactable that routes through `InventoryManager`
  (partial pickups stay on the ground; full backpack toasts).
- **Hotbar + inventory** — `Hotbar` (HUDLayer, bottom-center, keys 1–5)
  and the modal `InventoryScreen` (HUD bag button / I key) are both dumb
  grids of the shared `ItemSlotButton` over InventoryManager state.
  The screen uses tap-to-select → tap-to-place moves (touch-friendly;
  no drag precision needed), with Use / To Hotbar / Drop actions in a
  details pane. All rules live in the manager, never in these views.
- **InputManager taps** raycast through the 3D camera onto the ground
  plane, so all grid logic stays in cell space.
- **DayNightLayer / HUDLayer** — CanvasLayers render above the 3D
  viewport unchanged; night also dims the sun.

`BuildingEntity` / `ObstacleEntity` are presentation + per-instance
state (level, timers). Rules live in managers/definitions, so entities
stay small as content multiplies.

## UI Framework

- `UIStyle` — the entire look (colors, panel/button styles) in one file;
  re-skinning is a one-file change until a full Theme resource lands.
- `UIScreen` — base class for modals: dim backdrop, centered panel,
  open/close animation, standard header via `build_frame(title)`.
- `HUD` — generated from data: the resource bar is built from whatever
  ResourceDefinitions exist. Lives in the world scene, not UIManager,
  because it is gameplay UI.

## Data-Driven Content

Adding a building = one `.tres` file in `data/buildings/` (stats, cost,
production, effects, footprint, texture). It appears in the build menu,
places, constructs, produces, upgrades and saves with **zero code
changes**. Same for resources (`data/resources/`) — the HUD counter,
cost displays and stockpile all follow. Tuning values (grid size, day
length, camera limits, tap thresholds) live in
`data/settings/game_settings.tres`.

Locked content is already supported: `unlocked_from_start = false`
hides a building from the build menu — the hook for the future
research/tech system.

## Save Format

```json
{
  "version": 1,
  "timestamp": 1770000000,
  "sections": {
    "time": {"day": 4, "fraction": 0.3, "is_night": false},
    "resources": {"wood": 320, "stone": 410},
    "buildings": [{"id": "farm", "cx": 2, "cy": -1, "rot": 1, "level": 2, "state": 1, "remaining": 0}],
    "survivors": [{"name": "Mei Chen", "skill": "farming", "health": 100}],
    "inventory": {
      "slots": [{"id": "wood", "count": 32}, {}],
      "hotbar": [{"id": "bat", "count": 1}],
      "active": 0
    },
    "obstacles": {
      "entities": [{"id": "tree", "cx": 8, "cy": 3, "state": 1, "remaining": 12, "workers": 2, "health": 80}],
      "regrow": [{"id": "bush", "cx": -4, "cy": 7, "days": 3}]
    }
  }
}
```

---

## Suggested Next Milestone

**"Living Settlement"** — make the framework feel alive before adding
breadth:

1. **Survivor presence & jobs** — survivors as visible agents; assign to
   buildings; production scales with workers (SurvivorManager already
   stores `assigned_building`).
2. **Threat framework** — night zombie pressure using
   `data/tables/zombies.json`, `total_effect("defense")` and
   `night_started`; combat math only, no pathfinding yet.
3. **Research/unlock system** — a `ResearchDefinition` resource flipping
   building unlock flags; the build menu already filters on them.
4. **First-run tutorial** — a `TutorialManager` autoload that only
   listens to EventBus signals and highlights UI; zero changes to
   existing systems will be needed, which is the real test of this
   architecture.

After that: missions/expeditions (territory expansion), audio pass, and
art replacement for the placeholder building sprites.
