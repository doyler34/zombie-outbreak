extends Node
## CombatManager — squad missions against danger zones (autoload).
##
## Owns the mission lifecycle around the battle scene:
##   prepare_mission(zone) → squad select UI → start_mission(squad) →
##   BattleScene fights it out → resolve outcome into the settlement
##   (injuries, deaths, XP, rewards, rescues, zone removal).
##
## Mission composition and rewards are data: data/tables/missions.json
## maps an obstacle id ("zombie_nest") to zombie counts, reward ranges,
## risk label, XP and rescue chance. New danger zone types are a JSON
## entry + an obstacle .tres — no code.

const BATTLE_SCENE := preload("res://scenes/combat/battle_scene.tscn")

const SQUAD_MIN := 1
const SQUAD_MAX := 5

## The danger zone the player is currently staging a mission against.
var pending_zone: ObstacleEntity = null

var _battle: BattleScene = null
var _squad: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func reset() -> void:
	pending_zone = null
	_squad.clear()
	if _battle != null and is_instance_valid(_battle):
		_battle.queue_free()
	_battle = null


# ── Mission staging ──────────────────────────────────────────────────────

## Data for the mission briefing UI (risk, enemy estimate, loot preview).
func mission_info(zone: ObstacleEntity) -> Dictionary:
	var spec := _spec_for(zone)
	var count_min := 0
	var count_max := 0
	for zombie_id in spec.get("zombies", {}):
		var zombie_range: Array = spec.zombies[zombie_id]
		count_min += int(zombie_range[0])
		count_max += int(zombie_range[1])
	return {
		"risk": str(spec.get("risk", "Unknown")),
		"enemies_min": count_min,
		"enemies_max": count_max,
		"rewards": spec.get("rewards", {}),
	}


func prepare_mission(zone: ObstacleEntity) -> void:
	pending_zone = zone


## Launch the battle. Freezes base time via the BATTLE state.
func start_mission(squad: Array) -> void:
	if pending_zone == null or squad.is_empty() or _battle != null:
		return
	_squad = squad
	GameManager.enter_battle()

	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.finished.connect(_on_battle_finished)
	_battle.continue_pressed.connect(_on_battle_dismissed)
	_battle.start({"zombies": _roll_horde(_spec_for(pending_zone))}, squad)
	EventBus.mission_started.emit(pending_zone)


# ── Resolution ───────────────────────────────────────────────────────────

func _on_battle_finished(outcome: Dictionary) -> void:
	var result := {
		"outcome": str(outcome.result),
		"zombies_killed": int(outcome.zombies_killed),
		"dead": [], "injured": [], "rewards": {}, "xp_each": 0, "rescued": [],
	}
	var spec := _spec_for(pending_zone)

	# Injuries and deaths map back onto the roster (health is 0-100).
	for state: Dictionary in outcome.survivors:
		var survivor = state.survivor
		if not state.alive:
			result.dead.append(survivor.survivor_name)
			SurvivorManager.remove(survivor)
			continue
		survivor.health = maxi(int(state.hp_ratio * 100.0), 1)
		if survivor.health < 100:
			result.injured.append(survivor.survivor_name)

	if outcome.result == "victory":
		result.rewards = _roll_rewards(spec)
		ResourceManager.grant(result.rewards)

		# XP split across the whole squad, survivors and fallen alike.
		var xp_total := int(outcome.xp_earned) + int(spec.get("bonus_xp", 0))
		result.xp_each = xp_total / maxi(_squad.size(), 1)
		for survivor in _squad:
			if not result.dead.has(survivor.survivor_name):
				survivor.xp += result.xp_each

		# Sometimes someone is holed up inside the zone.
		if _rng.randf() < float(spec.get("rescue_chance", 0.0)):
			var rescued = SurvivorManager.generate_random()
			if SurvivorManager.add(rescued):
				result.rescued.append(rescued.survivor_name)

		# The zone is cleansed — build space freed permanently.
		if pending_zone != null and is_instance_valid(pending_zone):
			ObstacleManager.clear_zone(pending_zone)

	_battle.show_result(result)
	EventBus.mission_completed.emit(result)


func _on_battle_dismissed() -> void:
	_battle.queue_free()
	_battle = null
	pending_zone = null
	_squad = []
	GameManager.exit_battle()


# ── Internal ─────────────────────────────────────────────────────────────

func _spec_for(zone: ObstacleEntity) -> Dictionary:
	var table: Dictionary = DataManager.get_table("missions")
	if table == null or zone == null:
		return {}
	return table.get(zone.definition.id, {})


## Turn count ranges into a concrete list of zombie definitions.
func _roll_horde(spec: Dictionary) -> Array:
	var horde := []
	for zombie_id in spec.get("zombies", {}):
		var def := DataManager.get_zombie(zombie_id)
		if def == null:
			push_warning("[CombatManager] Mission references unknown zombie: %s" % zombie_id)
			continue
		var zombie_range: Array = spec.zombies[zombie_id]
		for i in _rng.randi_range(int(zombie_range[0]), int(zombie_range[1])):
			horde.append(def)
	return horde


## Roll reward ranges, then apply squad role bonuses (Scavenger loot,
## Engineer mission rewards) additively.
func _roll_rewards(spec: Dictionary) -> Dictionary:
	var bonus := 0.0
	for survivor in _squad:
		var role := DataManager.get_role(survivor.role)
		if role != null:
			bonus += role.loot_bonus + role.reward_bonus
	var rewards := {}
	for id in spec.get("rewards", {}):
		var reward_range: Array = spec.rewards[id]
		var amount := _rng.randi_range(int(reward_range[0]), int(reward_range[1]))
		rewards[id] = int(amount * (1.0 + bonus))
	return rewards
