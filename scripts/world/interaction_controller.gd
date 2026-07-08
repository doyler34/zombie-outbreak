class_name InteractionController
extends Node
## Finds what the Commander can interact with and triggers it on input.
##
## Every REFRESH_INTERVAL it scans the "interactables" group for the
## nearest component whose own range covers the actor, and emits
## [signal target_changed] when the answer (or its prompt text) changes
## — the HUD's InteractButton listens to show/hide itself. Triggering
## comes from the interact input action (desktop E key) or the button;
## either way this node only calls Interactable.interact() and lets the
## object's own handler do the work.

## How often the target is re-evaluated. Scanning a few hundred nodes at
## ~7 Hz is far cheaper than per-frame and imperceptible to the player.
const REFRESH_INTERVAL := 0.15

## Emitted with the new best target, or null when nothing is in range.
signal target_changed(interactable: Interactable)

## The character interactions are measured from (the Commander).
var actor: Node3D

var _current: Interactable = null
var _last_prompt: String = ""
var _accum := 0.0


func _process(delta: float) -> void:
	_accum += delta
	if _accum >= REFRESH_INTERVAL:
		_accum = 0.0
		_refresh_target()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if interact():
			get_viewport().set_input_as_handled()


## Trigger the current target. Returns false when there is none.
func interact() -> bool:
	if actor == null or _current == null or not is_instance_valid(_current):
		return false
	if _input_blocked():
		return false
	_current.interact(actor)
	# The interaction may have changed the prompt (gate open/close) or
	# removed the object — refresh immediately instead of waiting a tick.
	_refresh_target()
	return true


# ── Internal ─────────────────────────────────────────────────────────────

func _refresh_target() -> void:
	if not is_instance_valid(_current):
		_current = null
	var best: Interactable = null
	if actor != null and not _input_blocked():
		var pos := actor.global_position
		var best_distance := INF
		for node in get_tree().get_nodes_in_group(Interactable.GROUP):
			var candidate := node as Interactable
			if candidate == null or not candidate.can_target():
				continue
			var distance := candidate.distance_to(pos)
			if distance <= candidate.interaction_range and distance < best_distance:
				best_distance = distance
				best = candidate
	if best != _current or (best != null and best.prompt != _last_prompt):
		_current = best
		_last_prompt = best.prompt if best != null else ""
		target_changed.emit(_current)


## No interacting under a modal screen or mid building placement.
func _input_blocked() -> bool:
	if UIManager.has_open_screen():
		return true
	var placer := get_tree().get_first_node_in_group("building_placer")
	return placer != null and placer.is_active()
