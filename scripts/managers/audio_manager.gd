extends Node
## AudioManager — music, SFX and volume settings (autoload).
##
## Creates its own "Music" and "SFX" buses at runtime so the project
## needs no bus layout file. SFX play through a small round-robin pool of
## players (safe to spam on mobile); music changes crossfade.
##
## Volumes persist to user://settings.cfg independently of game saves.

const SFX_POOL_SIZE := 8
const SETTINGS_FILE := "user://settings.cfg"
const CROSSFADE_TIME := 1.0

var _music_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _next_sfx: int = 0


func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)

	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)

	_load_volume_settings()


# ── Playback ─────────────────────────────────────────────────────────────

func play_music(stream: AudioStream, fade: bool = true) -> void:
	if _music_player.stream == stream and _music_player.playing:
		return
	if fade and _music_player.playing:
		var tween := create_tween()
		tween.tween_property(_music_player, "volume_db", -40.0, CROSSFADE_TIME)
		await tween.finished
	_music_player.stream = stream
	_music_player.volume_db = 0.0
	_music_player.play()


func stop_music() -> void:
	_music_player.stop()


func play_sfx(stream: AudioStream, pitch_variation: float = 0.0) -> void:
	if stream == null:
		return
	var p := _sfx_pool[_next_sfx]
	_next_sfx = (_next_sfx + 1) % SFX_POOL_SIZE
	p.stream = stream
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()


# ── Volume settings ──────────────────────────────────────────────────────

func set_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))
		_save_volume_settings()


func get_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	return db_to_linear(AudioServer.get_bus_volume_db(idx)) if idx >= 0 else 1.0


# ── Internal ─────────────────────────────────────────────────────────────

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


func _save_volume_settings() -> void:
	var cfg := ConfigFile.new()
	for bus in ["Master", "Music", "SFX"]:
		cfg.set_value("audio", bus, get_volume(bus))
	cfg.save(SETTINGS_FILE)


func _load_volume_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) != OK:
		return
	for bus in ["Master", "Music", "SFX"]:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx,
				linear_to_db(clampf(float(cfg.get_value("audio", bus, 1.0)), 0.0001, 1.0)))
