class_name SurvivorNPC
extends Node3D
## A roster survivor living in the base as a visible, talkable NPC.
##
## Behaviour (all local, no pathfinding yet):
##  - No Capital built → the group follows the Commander around, each
##    survivor holding their own spot in a loose ring behind them.
##  - Capital built → they roam it: amble to a random walkable cell near
##    the building, stand around a while, wander on.
## Movement respects the same per-axis walkability the Commander uses,
## so NPCs slide along buildings instead of walking through them.
##
## The model comes from the survivor's role definition (same pipeline as
## combat units — the shared animation library applies automatically to
## rigs that match it), an Interactable makes them talkable, and
## dialogue is a placeholder line until a real dialogue/jobs system
## lands. Spawned by SurvivorNpcs; carries no state worth saving.

const LINES: Array[String] = [
	"Good to see you out here, Commander.",
	"The walls held last night. Barely.",
	"Let me know when there's work to do.",
	"Quiet day. I don't trust quiet days.",
	"We're counting on you, Commander.",
]

## The building whose presence flips FOLLOW → ROAM (the Capital).
const HOME_BUILDING_ID := "safe_house"
## How close (m) a follower stands to their ring spot before stopping.
const ARRIVE_DISTANCE := 0.5
## Followers lag this far behind the Commander (ring radius range, m).
const FOLLOW_RING_MIN := 2.2
const FOLLOW_RING_MAX := 4.0
## Roaming picks cells within this many cells of the Capital.
const ROAM_RADIUS := 5
## How long (s) an NPC loiters at a roam spot before wandering on.
const ROAM_WAIT_MIN := 2.5
const ROAM_WAIT_MAX := 7.0
## Fraction of the role's combat move speed used for ambling around.
const WALK_SPEED_FACTOR := 0.75
## Same wall-probe trick as the Commander — stop before clipping walls.
const WALL_PROBE := 0.3

var survivor  # SurvivorManager.Survivor

var _anim_player: AnimationPlayer
var _anim_idle := ""
var _anim_walk := ""
var _move_speed := 3.0
## This survivor's personal spot in the follow ring (offset from the
## Commander), derived from their uid so the group doesn't stack up.
var _follow_offset := Vector3.ZERO
var _roam_target := Vector3.ZERO
var _roam_wait := 0.0
var _has_roam_target := false


func setup(roster_survivor) -> void:
	survivor = roster_survivor

	var role_def := DataManager.get_role(survivor.role)
	if role_def == null and not DataManager.all_roles().is_empty():
		role_def = DataManager.all_roles()[0]
	if role_def != null:
		var model := ModelFactory.combatant_model(role_def)
		add_child(model)
		_anim_player = ModelFactory.find_animation_player(model)
		_anim_idle = ModelFactory.find_anim(_anim_player, ModelFactory.IDLE_CANDIDATES)
		_anim_walk = ModelFactory.find_anim(_anim_player, ModelFactory.WALK_CANDIDATES)
		_move_speed = maxf(role_def.move_speed * WALK_SPEED_FACTOR, 1.0)
		_play_anim(_anim_idle)

	var h := absi(hash(survivor.uid))
	rotation.y = float(h % 628) / 100.0
	var ring_angle := float((h >> 4) % 628) / 100.0
	var ring_radius := FOLLOW_RING_MIN \
		+ float((h >> 12) % 100) / 100.0 * (FOLLOW_RING_MAX - FOLLOW_RING_MIN)
	_follow_offset = Vector3(cos(ring_angle), 0, sin(ring_angle)) * ring_radius

	var first_name: String = survivor.survivor_name.get_slice(" ", 0)
	Interactable.attach(self, "Talk to %s" % first_name,
		DataManager.settings.interaction_reach, _on_interacted)


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		_play_anim(_anim_idle)
		return

	var home: BuildingEntity = BuildingManager.first_of(HOME_BUILDING_ID)
	if home == null:
		_follow_commander(delta)
	else:
		_roam_around(home, delta)


# ── Behaviour states ─────────────────────────────────────────────────────

## Trail the Commander, holding a personal spot in a ring around them.
func _follow_commander(delta: float) -> void:
	var commander := get_tree().get_first_node_in_group("commander") as Node3D
	if commander == null:
		_play_anim(_anim_idle)
		return
	_seek(commander.global_position + _follow_offset, delta)


## Idle around the Capital: walk to a random nearby cell, loiter, repeat.
func _roam_around(home: BuildingEntity, delta: float) -> void:
	if _roam_wait > 0.0:
		_roam_wait -= delta
		_play_anim(_anim_idle)
		return
	if not _has_roam_target:
		_pick_roam_target(home)
	var arrived := not _seek(_roam_target, delta)
	if arrived:
		_has_roam_target = false
		_roam_wait = randf_range(ROAM_WAIT_MIN, ROAM_WAIT_MAX)


func _pick_roam_target(home: BuildingEntity) -> void:
	var anchor := WorldManager.world_to_cell(home.global_position)
	for _attempt in 12:
		var cell := anchor + Vector2i(
			randi_range(-ROAM_RADIUS, ROAM_RADIUS),
			randi_range(-ROAM_RADIUS, ROAM_RADIUS))
		if WorldManager.is_cell_walkable(cell):
			_roam_target = WorldManager.area_center(cell, Vector2i.ONE)
			_has_roam_target = true
			return
	# Boxed in — stay put and try again after the next loiter.
	_roam_target = global_position
	_has_roam_target = true


# ── Movement ─────────────────────────────────────────────────────────────

## Walk toward [param target], per-axis walkability like the Commander.
## Returns true while still travelling, false once arrived (or stuck).
func _seek(target: Vector3, delta: float) -> bool:
	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length() <= ARRIVE_DISTANCE:
		_play_anim(_anim_idle)
		return false

	var direction := to_target.normalized()
	var motion := direction * _move_speed * delta
	var next := position
	var moved := false
	if not is_zero_approx(motion.x):
		var probe := next + Vector3(motion.x + signf(motion.x) * WALL_PROBE, 0, 0)
		if _is_walkable(probe):
			next.x += motion.x
			moved = true
	if not is_zero_approx(motion.z):
		var probe := next + Vector3(0, 0, motion.z + signf(motion.z) * WALL_PROBE)
		if _is_walkable(probe):
			next.z += motion.z
			moved = true
	next.y = WorldManager.ground_height(next)
	position = next

	if not moved:
		# Wall in the way and nothing to slide along — treat as arrived
		# so roamers pick a fresh target instead of pushing forever.
		_play_anim(_anim_idle)
		return false

	_face(direction)
	_play_anim(_anim_walk)
	return true


func _is_walkable(world_pos: Vector3) -> bool:
	return WorldManager.is_cell_walkable(WorldManager.world_to_cell(world_pos))


func _face(direction: Vector3) -> void:
	if direction.length_squared() < 0.0001:
		return
	# Kenney rigs model forward as +Z; aim the back of the head at the
	# travel direction (same trick as the Commander).
	look_at(global_position - direction, Vector3.UP)


# ── Animation / interaction ──────────────────────────────────────────────

func _play_anim(anim_name: String) -> void:
	if _anim_player == null or anim_name == "" or not _anim_player.has_animation(anim_name):
		return
	if _anim_player.current_animation == anim_name:
		return
	_anim_player.play(anim_name)


func _on_interacted(_actor: Node3D) -> void:
	var line: String = LINES[absi(hash(survivor.uid)) % LINES.size()]
	EventBus.notify("%s: \"%s\"" % [survivor.survivor_name, line], 0)
