# Zombie Outbreak: Colony Survival

Mobile-first, top-down strategy game set 8 years into a zombie
apocalypse. Rebuild a ruined settlement, rescue survivors, gather
resources and hold the line.

**Status:** expandable framework — core architecture, no gameplay
breadth yet. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the
full system guide.

## Tech

- Godot 4.4, GL Compatibility renderer (Android-first)
- Landscape 1280×720 base, `canvas_items` + `expand` stretch
- Touch + mouse input, one unified gesture layer

## Quick start

Open the project in Godot 4.4+, press Play. `New Game` drops you into
the world: drag to pan, pinch/scroll to zoom, `BUILD` to place
structures, tap a building to select/upgrade it. Saves autosave daily to
`user://saves/`.

## Adding content (no code required)

| Content   | How                                                        |
|-----------|------------------------------------------------------------|
| Building  | Add a `BuildingDefinition` .tres in `data/buildings/`      |
| Resource  | Add a `ResourceDefinition` .tres in `data/resources/`      |
| Tuning    | Edit `data/settings/game_settings.tres`                    |
| Data table| Drop a .json in `data/tables/`, read via `DataManager.get_table()` |

## Layout

- `scripts/managers/` — the 12 autoload systems (EventBus, Data, Save,
  Time, Resource, World, Survivor, Building, Audio, Input, UI, Game)
- `scripts/world/` — camera, building entities, ghost placement
- `scripts/ui/` — UI framework (UIStyle, UIScreen) + screens
- `data/` — all content and tuning
- `scenes/` — main menu, game world, building entity, UI screens
