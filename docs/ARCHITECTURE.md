# Zombie Outbreak — Framework Architecture

A mobile-first, top-down strategy framework for Godot 4.4. This document
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
  audio/           music + sfx streams
  shaders/         .gdshader files
  textures/        buildings/, terrain/, ui art
data/              ALL game content and tuning (no code)
  settings/        game_settings.tres — every tunable number
  buildings/       one BuildingDefinition .tres per building
  obstacles/       one ObstacleDefinition .tres per obstacle type
  resources/       one ResourceDefinition .tres per resource
  tables/          loose JSON data (name pools, zombies, world generation)
docs/              this file
scenes/
  main/            main_menu.tscn (entry scene)
  world/           game_world.tscn (the playable map)
  buildings/       building_entity.tscn
  ui/              modal screens (build menu, pause menu)
scripts/
  managers/        the 12 autoload singletons
  resources/       custom Resource classes (definition schemas)
  world/           world-scene behaviour (camera, placer, entities)
  ui/              UI framework + screens
```

Save files are written to `user://saves/` at runtime (never inside the
project), and user preferences to `user://settings.cfg`.

---

## The 13 Managers (autoload order matters)

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

### 8. BuildingManager (`building_manager.gd`)
Owns every placed `BuildingEntity`: placement validation + payment,
upgrades, removal, selection, daily production, passive effect totals
(`total_effect("defense")`), and building save data. The world scene
registers a container node on load; the manager spawns entities into it.

### 9. ObstacleManager (`obstacle_manager.gd`)
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

### 10. AudioManager (`audio_manager.gd`)
Creates Music/SFX buses at runtime, a round-robin SFX player pool (safe
to spam on mobile), music crossfade, and volume persistence separate
from game saves.

### 11. InputManager (`input_manager.gd`)
Translates raw touch/mouse events into gestures: `tapped`,
`long_pressed`, `drag_updated`, `zoom_requested`. Uses
`_unhandled_input`, so any UI Control that accepts an event
automatically blocks world input — no "is pointer over UI" checks
anywhere. **Why:** gameplay code written against gestures works
identically on Android touch and desktop mouse, and a replay/AI system
can emit the same signals.

### 12. UIManager (`ui_manager.gd`)
Persistent CanvasLayers that survive scene changes: a modal screen stack
(`push_screen`/`pop_screen`), toast notifications, and the fade
transition overlay. Screens extend `UIScreen` for consistent open/close
behaviour.

### 13. GameManager (`game_manager.gd`)
Top-level state machine (MENU/LOADING/PLAYING/PAUSED) and the only
system that changes scenes. New-game/continue flow: reset all session
managers → load world scene → world calls `notify_world_ready()` →
pending save is applied → state becomes PLAYING. Also owns autosave.

---

## World Scene (`scenes/world/game_world.tscn`)

Disposable view over manager state:

- **Ground** — a repeated-texture `Sprite2D` sized to the world rect in
  world space (pans correctly with the camera, unlike a screen-space
  shader).
- **Buildings** — y-sorted container; BuildingManager spawns entities here.
- **BuildingPlacer** — ghost preview: tap to position, green/red validity
  tint, grid overlay while placing, confirm/cancel via HUD. Position
  first, commit second — no accidental purchases on mobile.
- **CameraController** — RTS camera: drag pan, pinch/wheel zoom toward
  the gesture point, clamped to world bounds, smoothed. Consumes
  InputManager gestures only; zero platform-specific code.
- **DayNightLayer / HUDLayer** — CanvasLayers; ambience tint sits above
  the world (layer 50) but below the HUD (80) and UIManager (90+).

`BuildingEntity` is presentation + per-instance state (level,
construction countdown). Rules live in managers/definitions, so entities
stay small as building types multiply.

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
