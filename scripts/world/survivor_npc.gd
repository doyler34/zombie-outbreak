class_name SurvivorNPC
extends Node3D
## A roster survivor standing in the base as a visible, talkable NPC.
##
## Presence only: the model comes from the survivor's role definition
## (same pipeline as combat units), an Interactable makes them talkable,
## and dialogue is a placeholder line until a real dialogue/jobs system
## lands. Spawned and positioned by SurvivorNpcs; carries no state worth
## saving.

const LINES: Array[String] = [
	"Good to see you out here, Commander.",
	"The walls held last night. Barely.",
	"Let me know when there's work to do.",
	"Quiet day. I don't trust quiet days.",
	"We're counting on you, Commander.",
]

var survivor  # SurvivorManager.Survivor


func setup(roster_survivor) -> void:
	survivor = roster_survivor

	var role_def := DataManager.get_role(survivor.role)
	if role_def == null and not DataManager.all_roles().is_empty():
		role_def = DataManager.all_roles()[0]
	if role_def != null:
		var model := ModelFactory.combatant_model(role_def)
		add_child(model)
		var anim := ModelFactory.find_animation_player(model)
		if anim != null and anim.has_animation("idle"):
			anim.play("idle")

	# Deterministic facing per survivor so they don't all stand at
	# attention in the same direction.
	rotation.y = float(hash(survivor.uid) % 628) / 100.0

	var first_name: String = survivor.survivor_name.get_slice(" ", 0)
	Interactable.attach(self, "Talk to %s" % first_name,
		DataManager.settings.interaction_reach, _on_interacted)


func _on_interacted(_actor: Node3D) -> void:
	var line: String = LINES[absi(hash(survivor.uid)) % LINES.size()]
	EventBus.notify("%s: \"%s\"" % [survivor.survivor_name, line], 0)
