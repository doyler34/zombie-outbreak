extends Node
## GameManager — top-level game flow (autoload).
##
## A small state machine (MENU / LOADING / PLAYING / PAUSED) plus scene
## transitions. It is the only system that changes scenes, and the only
## one that decides when a session starts, loads or ends — every other
## manager just reacts to EventBus.game_state_changed.
##
## New-game / continue flow:
##   start_new_game()  → reset all session managers → enter world scene
##   continue_game()   → reset, then SaveManager.load_game() once the
##                       world has called notify_world_ready()

enum State { BOOT, MENU, LOADING, PLAYING, PAUSED }

const MAIN_MENU_SCENE := "res://scenes/main/main_menu.tscn"
const GAME_WORLD_SCENE := "res://scenes/world/game_world.tscn"

var state: State = State.BOOT

var _load_after_world_ready: bool = false


func _ready() -> void:
	# Autosave hook — safe even before a session starts (PLAYING check).
	EventBus.day_passed.connect(_on_day_passed)
	_set_state(State.MENU)


# ── Session flow ─────────────────────────────────────────────────────────

func start_new_game() -> void:
	_load_after_world_ready = false
	await _enter_world()


func continue_game() -> void:
	if not SaveManager.has_save():
		EventBus.notify("No save found.", 1)
		return
	_load_after_world_ready = true
	await _enter_world()


## Called by GameWorld once its nodes are in the tree, so loading can
## spawn buildings into a valid world.
func notify_world_ready() -> void:
	if _load_after_world_ready:
		_load_after_world_ready = false
		SaveManager.load_game()
	else:
		# Fresh map: scatter natural obstacles (saved games restore theirs).
		ObstacleManager.generate_initial_obstacles()
	EventBus.world_ready.emit()
	_set_state(State.PLAYING)


func return_to_menu(save_first: bool = true) -> void:
	if save_first and state == State.PLAYING:
		SaveManager.save_game()
	_set_state(State.LOADING)
	await change_scene(MAIN_MENU_SCENE)
	_set_state(State.MENU)


func toggle_pause() -> void:
	if state == State.PLAYING:
		_set_state(State.PAUSED)
	elif state == State.PAUSED:
		_set_state(State.PLAYING)


# ── Scene transitions ────────────────────────────────────────────────────

## Fade out, switch scene, fade back in.
func change_scene(path: String) -> void:
	await UIManager.fade_out()
	UIManager.close_all_screens()
	get_tree().change_scene_to_file(path)
	# Give the new scene one frame to run _ready before revealing it.
	await get_tree().process_frame
	await UIManager.fade_in()


# ── Internal ─────────────────────────────────────────────────────────────

func _enter_world() -> void:
	_set_state(State.LOADING)
	_reset_session()
	await change_scene(GAME_WORLD_SCENE)
	# The world scene calls notify_world_ready() from its _ready.


## Wipe all per-session state before starting or loading a game.
func _reset_session() -> void:
	BuildingManager.reset()
	WorldManager.reset()
	SurvivorManager.reset()
	TimeManager.reset()
	ResourceManager.reset()


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	EventBus.game_state_changed.emit(new_state, old)


func _on_day_passed(day: int) -> void:
	var interval := DataManager.settings.autosave_interval_days
	if state == State.PLAYING and interval > 0 and day % interval == 0:
		SaveManager.save_game()
		EventBus.notify("Autosaved.", 2)
