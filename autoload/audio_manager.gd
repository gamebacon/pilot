extends Node

# --- Players ---
var music_player: AudioStreamPlayer
var ambient_player: AudioStreamPlayer

# Pool of SFX players for overlapping sounds
var sfx_pool: Array[AudioStreamPlayer] = []
const SFX_POOL_SIZE = 8

# --- Volume (0.0 to 1.0) ---
var music_volume := 1.0
var sfx_volume := 1.0
var ambient_volume := 1.0

func _ready():
	# Music player
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	add_child(music_player)

	# Ambient player
	ambient_player = AudioStreamPlayer.new()
	ambient_player.bus = "Ambient"
	add_child(ambient_player)

	# SFX pool
	for i in SFX_POOL_SIZE:
		var p = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		sfx_pool.append(p)

# --- Music ---
func play_music(stream: AudioStream, fade: bool = true):
	if music_player.playing and fade:
		# Simple crossfade via tween
		var tween = create_tween()
		tween.tween_property(music_player, "volume_db", -40, 1.0)
		await tween.finished
	music_player.stream = stream
	music_player.volume_db = linear_to_db(music_volume)
	music_player.play()

func stop_music():
	music_player.stop()

# --- SFX ---
func play_sfx(stream: AudioStream, pitch: float = 1.0):
	var player = _get_free_sfx_player()
	if player:
		player.stream = stream
		player.volume_db = linear_to_db(sfx_volume)
		player.pitch_scale = pitch
		player.play()

func _get_free_sfx_player() -> AudioStreamPlayer:
	for p in sfx_pool:
		if not p.playing:
			return p
	return sfx_pool[0]  # Steal oldest if all busy

# --- Ambient ---
func play_ambient(stream: AudioStream):
	ambient_player.stream = stream
	ambient_player.volume_db = linear_to_db(ambient_volume)
	ambient_player.play()

func stop_ambient():
	ambient_player.stop()

# --- Volume Control ---
func set_music_volume(value: float):
	music_volume = clamp(value, 0.0, 1.0)
	music_player.volume_db = linear_to_db(music_volume)

func set_sfx_volume(value: float):
	sfx_volume = clamp(value, 0.0, 1.0)

func set_ambient_volume(value: float):
	ambient_volume = clamp(value, 0.0, 1.0)
	ambient_player.volume_db = linear_to_db(ambient_volume)
