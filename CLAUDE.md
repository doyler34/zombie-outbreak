# Zombie Outbreak — Project Context

Compact working memory so a session can start without re-reading chat history.
Deep design lives in `docs/ARCHITECTURE.md`; this file is the fast index +
hard-won gotchas + current asset wiring.

## What this is
Godot 4.4, mobile-first (Android), Clash-style **orthographic 3D** top-down
zombie survival game. Landscape 1280×720 base, `canvas_items`+`expand` stretch.
Framework-first: 18 autoload managers, everything data-driven via `.tres` in
`data/`. Adding content = drop a `.tres`, no code.

## Architecture in one breath
Autoload **managers own all state; scenes are disposable views**. Managers never
call each other directly for reactions — they emit on **EventBus** and others
subscribe. Order in `project.godot` is dependency order (EventBus, DataManager,
SaveManager first; GameManager last). The 18: EventBus, DataManager, SaveManager,
TimeManager, ResourceManager, WorldManager, SurvivorManager, InventoryManager,
CraftingManager, BuildingManager, BaseManager, ObstacleManager, CombatManager,
WorldMapManager, AudioManager, InputManager, UIManager, GameManager.

## Modular base building (LDoE/Rust-style, v1)
Player-built structures are **BuildingPiece** resources
(`data/building_pieces/*.tres`, POLY kit wooden set) placed in build mode
(HUD 🧱 BASE button, only inside the HQ zone; Commander freezes, camera
free). Grid model: CELL pieces (foundation/floor/roof) on world cells,
EDGE pieces (wall/doorway/window/door/gate/barricades) on cell borders
(x,z,axis 0=−Z/1=−X), storeys = 3m levels. Fills (door leafs,
door/window barricades) share the host edge slot on a layer keyed by
FILL_TOKENS (doorway, window_slot); they're authored INSIDE the kit's 3m
panel frame → anchor="authored" + mesh_offset(−2,0,−0.1) +
mesh_scale(4/3,1,1) lines them up with the stretched host panel.
**BaseManager** owns occupancy, socket-based validation
(piece.provides/requires: terrain, edge_support,
stack, roof_support, doorway, window_slot), snapping (`best_spot_for`),
placement,
save section "base_pieces". `PiecePlacement` = grid/fit math (models
auto-fit per fit_mode tile/contain/edge, fits cached);
`BasePieceEntity` = placed node; `BuildModeController` = ghost preview
(green/red, hover on PC, tap on touch, R/Enter/Esc);
`BuildModeMenu` = category tabs auto-built from data. Walls block
movement via WorldManager blocked-edges (`is_move_allowed`) — Commander
and NPCs check crossings, doorways/gates don't block.
`tools/debug_base_building.gd` smoke-tests the whole flow in CI
(BASEBUILD_OK).

World is 3D (Node3D + orthographic Camera3D pitch −55/yaw 45). Grid positions are
**Vector3 on XZ plane, Y=0**, cell_size in meters (4.0). Taps raycast camera→ground.
`ModelFactory` builds every visual: `.glb`/`.fbx` model when the def has one,
else a bright primitive placeholder.

## Data-driven content (all in `data/`)
- `settings/game_settings.tres` — every tunable number (camera, grid, time, etc).
- `buildings/` (8), `obstacles/` (8), `resources/` (5), `roles/` (5),
  `zombies/` (4), `locations/` (12) — one `.tres` each, discovered by folder scan.
- `tables/*.json` — missions, world_generation, survivor_names.

## Current asset wiring
**Buildings** (`model_path` → auto-fit to grid plot unless `model_scale` set):
- Capital(id `safe_house`) capital.glb, Wall wall.glb, Gate gate.glb — Tripo,
  embedded textures.
- Barracks, Farm, Medical Bay, Workshop, Watchtower → composite scenes in
  `scenes/buildings/*.tscn`, assembled from the **POLY Survival Workshop**
  modular kit (`assets/poly_survival_workshop/`): open-top interiors (floor +
  3m wall panels + signature props) that read well on the top-down camera.
  Kit gotchas: every gltf referenced a missing `New Palitra.jpg` — the
  palette atlas (`Polygon_Texture2.png`) now sits COPIED BESIDE the models
  in every gltf directory and URIs point at it same-dir. NEVER use `../`
  in gltf texture URIs: the editor/CI import resolves them (CI stays
  green) but the exported APK's remap lookup doesn't → textures silently
  null on device, models render gray. Same lesson as Kenney gotcha #6:
  texture beside the model, always; pack
  leftovers (Models_original FBX dupes, Unity Materials, foreign Prefabs/
  Scenes/Demo_Profiles/terrain, per-dir `extracted/`) are `.gdignore`d.
  Wall/floor pieces pivot at their min-X corner (panel runs +X, thickness
  +Z, floor extends −Z); props pivot centered at Y=0. Kenney City Kit glbs
  remain in assets, unused.

**Combat** (`data/roles`, `data/zombies`): each combatant has `model` +
`model_scale`. Shared animation libraries in `assets/animations/` (CC0
Quaternius): AL_Standard.fbx = base set (Idle/Walk/Jog/Sprint/Punch_Cross/
Death01...) on the UE rig, UAL2_Standard.glb = expansion (Zombie_Idle/
Walk_Fwd/Scratch, chopping/farming/Consume) on the same UE rig, and
AnimationLibrary_Godot_Standard.glb = the base set's Rigify edition (only
merges into Rigify rigs). Mannequins are gray, so
ModelFactory.combatant_model tints them with the definition color. Clip names
resolve per rig via ModelFactory.find_anim candidate lists; the two libraries
use DIFFERENT skeletons (UAL1 "DEF-hips", UAL2 "pelvis") and only merge into
matching rigs. Kenney mini-characters (32 anims) remain in assets as a fallback. Playable
cast now = Universal Base Characters (superhero male/female GLTF, UE rig,
assets/characters/universal_base) - UAL2 clips drive them; zombies are the
same models tinted per-type.
Role→weapon (attached to `DEF-hand.R` bone, auto-fit to `weapon_length` m):
Fighter machete, Scavenger knife (melee); Engineer handgun, Medic revolver,
Guard shotgun (guns). Medic still heals (weapon cosmetic). Weapon offsets were
tuned for the old Kenney rig — may need re-tuning on the mannequins.

## HARD-WON GOTCHAS (do not re-learn these)
1. **`const X = [ClassName, …]` is a parse error** — class_name refs aren't
   constant expressions. It silently kills the script AND every dependent script.
   Use `preload("res://…")` in consts. (This broke all combat once.)
2. **Typed const collections** (`const X: Array[float] = …`) have broken
   compilation here before — keep such consts untyped.
3. **FBX bakes a scale (~0.01) on the root node.** Never set `.scale` directly on
   an imported FBX root — wrap it in a holder Node3D and scale the holder, or the
   fit math cancels wrong (weapons went ~100× off-screen).
4. **Weapons/models inherit the character's model_scale** through the skeleton —
   auto-fit divides it back out (`ModelFactory.attach_weapon`).
5. **Viewport size**: `get_viewport().get_visible_rect().size` is PHYSICAL pixels;
   Control children live in LOGICAL coords. (Legacy 2D-UI lesson; world is 3D now.)
6. **Kenney GLBs reference an EXTERNAL `Textures/colormap.png`** (not embedded).
   It must sit beside the glb. Placed shared palette at
   `assets/buildings/Textures/colormap.png`; swap in the real City Kit colormap if
   colors look off.
7. **One-shot anims** (attack/die) must be forced non-looping and protected from
   locomotion anims interrupting them, or they show 1 frame / freeze.
8. **Godot's glTF importer STRIPS `_Loop`/`-loop`/`_Cycle` suffixes from clip
   names** (it uses them to set looping, then renames): "Idle_FoldArms_Loop"
   imports as "Idle_FoldArms". Never match clip names verbatim — use
   ModelFactory.find_anim (normalized keys). This caused days of silent T-pose.
9. **Animation-less .gltf characters import with NO AnimationPlayer**;
   ModelFactory.apply_shared_animations synthesizes one parented ON the
   Skeleton3D so merged bone tracks are self-relative (".:bone").
10. **CI is a usable Godot runtime**: tools/debug_animations.gd runs headless
   in the workflow, plays a clip and fails the build if bones don't move —
   extend it when debugging anything that needs real engine behaviour.

## Workflow (follow this)
- Branch: **`claude/ground-menu-alignment-lbkm58`**. User pushes assets to `main`;
  merge main in when they say they've added assets.
- **No Godot runtime in this sandbox.** Validate with: `gdparse $(find scripts -name '*.gd')`
  for syntax, and the Python xref checker in scratchpad for manager symbol/arity.
- **CI is the real test.** `.github/workflows/build-apk.yml` runs on `claude/**`
  pushes: headless Godot `tools/validate_scripts.gd` force-loads every
  script/scene/`.tres` (catches parse errors, bad refs, failed asset imports),
  then builds the APK. Always push and confirm the run is `success` before
  declaring done. Check via GitHub MCP `actions_list` (results can be large →
  slice the saved file).
- Commit style: clear subject + body; end with
  `Co-Authored-By: Claude <noreply@anthropic.com>` and the Claude-Session trailer.
- Data-only asset changes: still push + CI, because a newly-referenced model/texture
  gets its FIRST import validation there.

## Persistent problems history (all fixed)
Ground texture, bottom-menu alignment, invisible building, landscape orientation,
combat parse-error, invisible attack anim, giant/missing weapons. All resolved and
CI-green. If a "feature doesn't show on device," first suspect: stale APK (old run)
or a silent parse/import error — check the latest CI run's validate step.

## Unused assets available (not yet wired)
80+ Kenney city models (skyscrapers, fences, paths, driveways, trees), 6 farm crop
FBX, extra weapons (ak47, smg, sniper, fire_axe, hammer, grenade, ammo). Ask before
assuming which to use.
