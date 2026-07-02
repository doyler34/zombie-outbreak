class_name GameSettings
extends Resource
## Central tuning file for the whole game.
##
## Every "magic number" that designers may want to change lives here, in
## data/settings/game_settings.tres — never hardcoded in scripts.
## Loaded once by DataManager at boot and available everywhere via
## DataManager.settings.

@export_group("World Grid")
## Size of one grid cell, in world pixels.
@export var cell_size: int = 96
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
@export var camera_min_zoom: float = 0.5
@export var camera_max_zoom: float = 2.5
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

@export_group("Saves")
## Save format version — bump when the save layout changes and add a
## migration step in SaveManager._migrate().
@export var save_version: int = 1
@export var default_save_slot: int = 0
