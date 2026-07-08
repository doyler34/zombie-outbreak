class_name Commander
extends Node3D
## The player's directly-controlled character — walks around the base.
##
## Input comes from the on-screen MovementJoystick (mobile) or the
## move_* keyboard actions (WASD / arrows, desktop), both expressed in
## screen space and converted to camera-relative ground motion so "up"
## always means "up on screen". Movement respects the same grid the
## builder uses — cells occupied by buildings or blocking obstacles are
## walls (WorldManager.is_cell_walkable), checked per axis so the
## Commander slides along edges instead of sticking to them.
##
## Stats and the character model come from a CombatantDefinition
## (data/characters/commander.tres), same as combat units; the Kenney rig
## provides the "idle" / "walk" clips this script plays. No combat, no
## inventory — this is only locomotion.

const DEFINITION := preload("res://data/characters/commander.tres")

## Resolved per-model via ModelFactory.find_anim, so both the Kenney
## naming ("idle"/"walk") and the shared library names work.
var _anim_idle := ""
var _anim_walk := ""
## How far ahead of the Commander a cell is probed before entering it —
## keeps the model's feet from clipping into walls before stopping.
const WALL_PROBE := 0.35
## How many rings of cells to search when relocating to a free spot.
const RELOCATE_RADIUS := 8

## Fired when the player starts moving after standing still — the camera
## uses it to resume following after a manual pan.
signal movement_started()

## Assigned by GameWorld; polled every frame for touch input.
var joystick: MovementJoystick

var _definition: CombatantDefinition = DEFINITION
var _anim_player: AnimationPlayer
var _was_moving := false


func _ready() -> void:
	add_to_group("commander")
	var model := ModelFactory.combatant_model(_definition)
	add_child(model)
	_anim_player = ModelFactory.find_animation_player(model)
	_anim_idle = ModelFactory.find_anim(_anim_player, ModelFactory.IDLE_CANDIDATES)
	_anim_walk = ModelFactory.find_anim(_anim_player, ModelFactory.WALK_CANDIDATES)
	_play_anim(_anim_idle)

	# Buildings can appear on top of the spawn point (loading a save,
	# the starting base, player placement) — step aside when they do.
	EventBus.load_completed.connect(func(_slot: int): _ensure_walkable())
	EventBus.building_placed.connect(func(_entity): _ensure_walkable())


func _physics_process(delta: float) -> void:
	var input := _gather_input()
	var moving := input.length_squared() > 0.0001
	if moving:
		var direction := _camera_relative(input)
		_step(direction, input.length(), delta)
		_face(direction)
		_play_anim(_anim_walk)
		if not _was_moving:
			movement_started.emit()
	else:
		_play_anim(_anim_idle)
	_was_moving = moving


# ── Input ────────────────────────────────────────────────────────────────

## Screen-space movement vector (x right, y down), length 0..1.
## Joystick wins when deflected; keyboard is the desktop fallback.
func _gather_input() -> Vector2:
	if UIManager.has_open_screen():
		return Vector2.ZERO
	if joystick != null and joystick.direction != Vector2.ZERO:
		return joystick.direction
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


## Convert screen-space input into a ground-plane direction relative to
## the active camera (same flattening the camera's own pan uses).
func _camera_relative(input: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3(input.x, 0, input.y).normalized()
	var basis := camera.global_transform.basis
	var right := Vector3(basis.x.x, 0, basis.x.z).normalized()
	var forward := Vector3(-basis.z.x, 0, -basis.z.z).normalized()
	# Screen up is -y.
	return (right * input.x - forward * input.y).normalized()


# ── Movement ─────────────────────────────────────────────────────────────

## Advance along [param direction], checking each axis against the grid
## separately so a blocked axis doesn't kill the whole motion (slide).
func _step(direction: Vector3, strength: float, delta: float) -> void:
	var motion := direction * _definition.move_speed * clampf(strength, 0.0, 1.0) * delta
	var next := position
	if not is_zero_approx(motion.x):
		var probe := next + Vector3(motion.x + signf(motion.x) * WALL_PROBE, 0, 0)
		if _is_walkable(probe):
			next.x += motion.x
	if not is_zero_approx(motion.z):
		var probe := next + Vector3(0, 0, motion.z + signf(motion.z) * WALL_PROBE)
		if _is_walkable(probe):
			next.z += motion.z
	position = next


func _is_walkable(world_pos: Vector3) -> bool:
	return WorldManager.is_cell_walkable(WorldManager.world_to_cell(world_pos))


func _face(direction: Vector3) -> void:
	if direction.length_squared() < 0.0001:
		return
	# Kenney mini-characters model forward as +Z; look_at aims −Z at the
	# target, so aim at the point behind to face the travel direction.
	look_at(global_position - direction, Vector3.UP)


## If the current cell became blocked (building dropped on it), hop to
## the nearest walkable cell so the Commander is never stuck inside.
func _ensure_walkable() -> void:
	var cell := WorldManager.world_to_cell(position)
	if WorldManager.is_cell_walkable(cell):
		return
	for radius in range(1, RELOCATE_RADIUS + 1):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue  # only the ring's edge; inner cells already tried
				var candidate := cell + Vector2i(x, y)
				if WorldManager.is_cell_walkable(candidate):
					position = WorldManager.area_center(candidate, Vector2i.ONE)
					return


# ── Animation ────────────────────────────────────────────────────────────

func _play_anim(anim_name: String) -> void:
	if _anim_player == null or anim_name == "" or not _anim_player.has_animation(anim_name):
		return
	if _anim_player.current_animation == anim_name:
		return
	_anim_player.play(anim_name)
