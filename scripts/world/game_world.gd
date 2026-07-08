class_name GameWorld
extends Node3D
## The playable 3D world: ground, sun, buildings, placement, camera, HUD.
##
## Keeps almost no state of its own — it wires the scene's nodes to the
## global managers (register containers, size the ground to the world
## rect, route taps to selection) and reports readiness to GameManager,
## which then applies a pending save load if the player chose Continue.
##
## The HUD and day/night tint stay on CanvasLayers — they render above
## the 3D viewport unchanged.

const GROUND_SHADER := preload("res://assets/shaders/ground_tiles.gdshader")

@onready var ground: MeshInstance3D = $Ground
@onready var sun: DirectionalLight3D = $Sun
@onready var buildings: Node3D = $Buildings
@onready var obstacles: Node3D = $Obstacles
@onready var placer: BuildingPlacer = $BuildingPlacer
@onready var camera_rig: CameraController = $CameraRig
@onready var commander: Commander = $Commander
@onready var joystick: VirtualJoystick = $HUDLayer/VirtualJoystick
@onready var day_night_overlay: ColorRect = $DayNightLayer/DayNightOverlay


func _ready() -> void:
	BuildingManager.register_container(buildings)
	ObstacleManager.register_container(obstacles)

	# Angled sun for big readable shadows.
	sun.rotation_degrees = Vector3(-50, -35, 0)

	_setup_ground()

	InputManager.tapped.connect(_on_world_tapped)
	EventBus.game_tick.connect(_update_day_night)

	# The camera tracks the Commander; a manual pan pauses the follow and
	# the Commander moving again resumes it.
	commander.joystick = joystick
	commander.movement_started.connect(camera_rig.resume_follow)
	camera_rig.follow(commander)
	camera_rig.jump_to(commander.global_position)
	GameManager.notify_world_ready()


## A single plane covering the world rect, with the tile checker shader
## aligned to the gameplay grid.
func _setup_ground() -> void:
	var world := WorldManager.world_rect()
	var plane := PlaneMesh.new()
	plane.size = world.size
	ground.mesh = plane
	ground.position = Vector3(world.get_center().x, 0, world.get_center().y)
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	material.set_shader_parameter("cell_size", WorldManager.cell_size())
	ground.material_override = material


## Taps select buildings or obstacles — unless the placer is using them.
func _on_world_tapped(_screen_pos: Vector2, world_pos: Vector3) -> void:
	if placer.is_active():
		return
	var cell := WorldManager.world_to_cell(world_pos)
	var occupant := WorldManager.occupant_at(cell)
	if occupant is ObstacleEntity:
		BuildingManager.deselect()
		ObstacleManager.select(occupant)
	else:
		ObstacleManager.deselect()
		BuildingManager.select_at(cell)


## Dim the sun and tint the screen as night approaches (simple ambience;
## a real lighting pass can replace this without touching TimeManager).
func _update_day_night() -> void:
	var fraction: float = TimeManager.day_fraction
	var night_start: float = DataManager.settings.night_start_fraction
	var night := 0.0
	if fraction >= night_start:
		night = (fraction - night_start) / (1.0 - night_start)
	day_night_overlay.color = Color(0.02, 0.03, 0.10, lerpf(0.0, 0.4, night))
	sun.light_energy = lerpf(1.2, 0.35, night)
