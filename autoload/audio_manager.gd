extends Node

var music_player:   AudioStreamPlayer
var ambient_player: AudioStreamPlayer
var sfx_pool: Array[AudioStreamPlayer] = []
const SFX_POOL_SIZE = 8

var music_volume   := 0.1
var sfx_volume     := 1.0
var ambient_volume := 0.1

func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	music_player.finished.connect(_on_music_finished)
	add_child(music_player)

	ambient_player = AudioStreamPlayer.new()
	ambient_player.bus = "Ambient"
	ambient_player.finished.connect(_on_ambient_finished)
	add_child(ambient_player)

	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		sfx_pool.append(p)

# Loop handlers — restart track when it ends (works even without import loop flag)
func _on_music_finished() -> void:
	if music_player.stream:
		music_player.play()

func _on_ambient_finished() -> void:
	if ambient_player.stream:
		ambient_player.play()

# ── Music ─────────────────────────────────────────────────────────────────────

func play_music(stream: AudioStream, fade: bool = true) -> void:
	if music_player.playing and fade:
		var tween := create_tween()
		tween.tween_property(music_player, "volume_db", -80.0, 1.5)
		await tween.finished
	music_player.stream    = stream
	music_player.volume_db = linear_to_db(music_volume)
	music_player.play()

func stop_music(fade: bool = false) -> void:
	if fade and music_player.playing:
		var tween := create_tween()
		tween.tween_property(music_player, "volume_db", -80.0, 1.5)
		await tween.finished
	music_player.stream = null
	music_player.stop()

# ── SFX ───────────────────────────────────────────────────────────────────────

func play_sfx(stream: AudioStream, pitch: float = 1.0) -> void:
	var p := _get_free_sfx_player()
	if p:
		p.stream    = stream
		p.volume_db = linear_to_db(sfx_volume)
		p.pitch_scale = pitch
		p.play()

func _get_free_sfx_player() -> AudioStreamPlayer:
	for p in sfx_pool:
		if not p.playing:
			return p
	return sfx_pool[0]

# ── Ambient ───────────────────────────────────────────────────────────────────

func play_ambient(stream: AudioStream, fade: bool = true) -> void:
	if ambient_player.playing and fade:
		var tween := create_tween()
		tween.tween_property(ambient_player, "volume_db", -80.0, 1.5)
		await tween.finished
	ambient_player.stream    = stream
	ambient_player.volume_db = linear_to_db(ambient_volume)
	ambient_player.play()

func stop_ambient(fade: bool = false) -> void:
	if fade and ambient_player.playing:
		var tween := create_tween()
		tween.tween_property(ambient_player, "volume_db", -80.0, 1.5)
		await tween.finished
	ambient_player.stream = null
	ambient_player.stop()

# ── Volume control ────────────────────────────────────────────────────────────

func set_music_volume(value: float) -> void:
	music_volume           = clamp(value, 0.0, 1.0)
	music_player.volume_db = linear_to_db(music_volume)

func set_sfx_volume(value: float) -> void:
	sfx_volume = clamp(value, 0.0, 1.0)
	for p in sfx_pool:
		if not p.playing:
			p.volume_db = linear_to_db(sfx_volume)

func set_ambient_volume(value: float) -> void:
	ambient_volume           = clamp(value, 0.0, 1.0)
	ambient_player.volume_db = linear_to_db(ambient_volume)
