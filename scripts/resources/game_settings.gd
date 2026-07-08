class_name GameSettings
extends Resource
## Central tuning file for the whole game.
##
## Every "magic number" that designers may want to change lives here, in
## data/settings/game_settings.tres — never hardcoded in scripts.
## Loaded once by DataManager at boot and available everywhere via
## DataManager.settings.

@export_group("World Grid")
## Size of one grid cell, in world meters (3D units on the XZ plane).
@export var cell_size: float = 4.0
## World dimensions, in cells.
@export var world_size: Vector2i = Vector2i(48, 48)

@export_group("Time")
## Real-time seconds for one full in-game day (day + night).
@export var seconds_per_day: float = 120.0
## Fraction of the day cycle at which night begins (0..1).
@export var night_start_fraction: float = 0.65
## Autosave every N in-game days. 0 disables autosave.
@export var autosave_interval_days: int = 1

@export_group("Camera")
## Orthographic size (vertical world extent). Smaller = closer/chunkier.
@export var camera_default_size: float = 35.0
@export var camera_min_size: float = 18.0
@export var camera_max_size: float = 60.0
## Clash-style angle: pitch down, 45° diagonal yaw.
@export var camera_pitch_degrees: float = -55.0
@export var camera_yaw_degrees: float = 45.0
## Smoothing factor for camera movement (higher = snappier).
@export var camera_smoothing: float = 8.0
## Mouse wheel zoom step multiplier.
@export var camera_zoom_step: float = 1.1

@export_group("Input")
## Max finger travel (px) for a press to still count as a tap.
@export var tap_max_distance: float = 24.0
## Max press duration (seconds) for a tap.
@export var tap_max_duration: float = 0.35
## Press duration (seconds) after which a long-press fires.
@export var long_press_duration: float = 0.6

@export_group("Virtual Joystick")
## Radius (px) of the on-screen movement joystick's base circle.
@export var joystick_radius: float = 90.0
## Knob deflections below this fraction of the radius are ignored.
@export var joystick_dead_zone: float = 0.2

@export_group("Interaction")
## Extra reach (m) beyond an object's footprint radius from which the
## Commander can interact with it. Individual objects can still override
## their Interactable's range entirely.
@export var interaction_reach: float = 2.6

@export_group("Inventory")
## Backpack capacity (slots).
@export var inventory_slots: int = 20
## Quick-use hotbar capacity (slots).
@export var hotbar_slots: int = 5
## Items granted on a new game: {item_id: count}.
@export var starting_items: Dictionary = {}

@export_group("Population")
## Survivors the player starts a new game with (the founding crew —
## exempt from the housing cap).
@export var starting_survivors: int = 3

@export_group("Saves")
## Save format version — bump when the save layout changes and add a
## migration step in SaveManager._migrate().
@export var save_version: int = 1
@export var default_save_slot: int = 0
