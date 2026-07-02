class_name GameWorld
extends Node2D
## The playable world scene: ground, buildings, placement, camera, HUD.
##
## Keeps almost no state of its own — it wires the scene's nodes to the
## global managers (register the building container, size the ground,
## route taps to selection) and reports readiness to GameManager, which
## then applies a pending save load if the player chose Continue.

@onready var ground: Sprite2D = $Ground
@onready var buildings: Node2D = $Buildings
@onready var placer: BuildingPlacer = $BuildingPlacer
@onready var camera: CameraController = $Camera
@onready var day_night_overlay: ColorRect = $DayNightLayer/DayNightOverlay


func _ready() -> void:
	BuildingManager.register_container(buildings)

	# Tile the ground texture across the whole world rect (world-space,
	# so it pans correctly with the camera — unlike a screen-space shader).
	var world := WorldManager.world_rect()
	ground.region_enabled = true
	ground.region_rect = Rect2(Vector2.ZERO, world.size)
	ground.position = world.get_center()
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	InputManager.tapped.connect(_on_world_tapped)
	EventBus.game_tick.connect(_update_day_night)

	camera.jump_to(Vector2.ZERO)
	GameManager.notify_world_ready()


## Taps select/deselect buildings — unless the placer is using them.
func _on_world_tapped(_screen_pos: Vector2, world_pos: Vector2) -> void:
	if placer.is_active():
		return
	BuildingManager.select_at(WorldManager.world_to_cell(world_pos))


## Darken the world as night approaches (simple ambience; a lighting
## system can replace this without touching TimeManager).
func _update_day_night() -> void:
	var fraction: float = TimeManager.day_fraction
	var night_start: float = DataManager.settings.night_start_fraction
	var alpha := 0.0
	if fraction >= night_start:
		alpha = lerpf(0.0, 0.45, (fraction - night_start) / (1.0 - night_start))
	day_night_overlay.color = Color(0.02, 0.03, 0.10, alpha)
