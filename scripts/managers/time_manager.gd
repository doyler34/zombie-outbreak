extends Node
## TimeManager — the game clock (autoload).
##
## Drives the day/night cycle and emits the heartbeat signals every other
## system schedules against:
##  - EventBus.game_tick      → ~1×/real second while playing (production,
##                              construction progress, AI, timers)
##  - EventBus.day_passed     → end of each in-game day (daily economy)
##  - EventBus.night_started / day_started → phase changes (visuals, threats)
##
## The clock only advances while GameManager is in the PLAYING state, so
## menus and pause are handled automatically. time_scale enables
## fast-forward / slow-motion without touching Engine.time_scale.

const TICK_INTERVAL := 1.0

var current_day: int = 1
var is_night: bool = false
## 0..1 progress through the current day cycle.
var day_fraction: float = 0.0
var time_scale: float = 1.0

var _tick_accumulator: float = 0.0
var _running: bool = false


func _ready() -> void:
	SaveManager.register_section("time", self)
	EventBus.game_state_changed.connect(_on_game_state_changed)


func _process(delta: float) -> void:
	if not _running:
		return
	var scaled := delta * time_scale
	var settings := DataManager.settings

	day_fraction += scaled / settings.seconds_per_day
	if day_fraction >= 1.0:
		day_fraction -= 1.0
		current_day += 1
		is_night = false
		EventBus.day_passed.emit(current_day)
		EventBus.day_started.emit(current_day)

	if not is_night and day_fraction >= settings.night_start_fraction:
		is_night = true
		EventBus.night_started.emit(current_day)

	_tick_accumulator += scaled
	if _tick_accumulator >= TICK_INTERVAL:
		_tick_accumulator -= TICK_INTERVAL
		EventBus.game_tick.emit()


func reset() -> void:
	current_day = 1
	is_night = false
	day_fraction = 0.0
	time_scale = 1.0
	_tick_accumulator = 0.0


# ── Save contract ────────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	return {
		"day": current_day,
		"fraction": day_fraction,
		"is_night": is_night,
	}


func apply_save_data(data: Dictionary) -> void:
	current_day = int(data.get("day", 1))
	day_fraction = float(data.get("fraction", 0.0))
	is_night = bool(data.get("is_night", false))


# ── Internal ─────────────────────────────────────────────────────────────

func _on_game_state_changed(new_state: int, _old_state: int) -> void:
	_running = new_state == GameManager.State.PLAYING
