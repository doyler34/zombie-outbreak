class_name Interactable
extends Node3D
## Reusable interaction component — attach to any world object to make
## it interactable by the Commander.
##
## The component knows nothing about WHAT the interaction does: it holds
## a prompt, a per-object range, and emits [signal interacted] when
## triggered. The owner (BuildingEntity, ObstacleEntity, SurvivorNPC,
## anything future) connects a handler, so behaviour lives with the
## object it belongs to — never in the player or the input layer.
##
## InteractionController finds candidates through the group and picks
## the nearest one in range; EventBus.interaction_performed mirrors every
## trigger globally for systems that just want to listen (tutorial,
## audio cues, quests).

const GROUP := "interactables"

## Fired when the interaction triggers. [param actor] is whoever
## interacted (the Commander for now).
signal interacted(actor: Node3D)

## Text shown on the interact button ("Open Gate", "Talk to Mei", ...).
## Owners may update it at any time (e.g. a gate flipping open/closed).
@export var prompt: String = "Interact"
## Max distance (m, on the ground plane) from which this object can be
## interacted with — configurable per object.
@export var interaction_range: float = 3.0
## Disable to make the object temporarily non-interactable.
@export var enabled: bool = true


## Convenience for code-built objects: create, configure, parent and
## wire an Interactable in one call. [param reach] is the interaction
## range; [param handler] is connected to [signal interacted].
static func attach(parent: Node3D, prompt_text: String, reach: float,
		handler: Callable) -> Interactable:
	var component := Interactable.new()
	component.prompt = prompt_text
	component.interaction_range = reach
	parent.add_child(component)
	if handler.is_valid():
		component.interacted.connect(handler)
	return component


func _ready() -> void:
	add_to_group(GROUP)


func can_target() -> bool:
	return enabled and is_inside_tree() and is_visible_in_tree()


## Ground-plane distance from [param world_pos] to this object.
func distance_to(world_pos: Vector3) -> float:
	var delta := global_position - world_pos
	delta.y = 0.0
	return delta.length()


func interact(actor: Node3D) -> void:
	if not can_target():
		return
	interacted.emit(actor)
	EventBus.interaction_performed.emit(self, actor)
