extends Node

# Detects which zone the player is in and drives AudioManager accordingly.
# Zone is determined by flat (XZ) distance to each building's world position.
#
# To add audio, drop looping .ogg files at these paths:
#   res://audio/ambient/outdoor_ambient.ogg
#   res://audio/ambient/shop_ambient.ogg
#   res://audio/ambient/factory_ambient.ogg
#   res://audio/music/outdoor_music.ogg
#   res://audio/music/shop_music.ogg
#   res://audio/music/factory_music.ogg
# Missing files are silently skipped (audio stops for that zone).

enum Zone { OUTDOOR, SHOP, FACTORY }

const SHOP_POS    := Vector2(-16.0, -85.0)
const FACTORY_POS := Vector2(  0.0, -175.0)
const SHOP_RADIUS    := 12.0
const FACTORY_RADIUS := 20.0

const AMBIENT_PATHS := {
	Zone.OUTDOOR: "res://audio/ambient/outdoor_ambient.mp3",
	Zone.SHOP:    "res://audio/ambient/shop_ambient.mp3",
	Zone.FACTORY: "res://audio/ambient/factory_ambient.mp3",
}
const MUSIC_PATHS := {
	Zone.OUTDOOR: "res://audio/music/outdoor_music.mp3",
	Zone.SHOP:    "res://audio/music/shop_music.ogg",
	Zone.FACTORY: "res://audio/music/factory_music.ogg",
}

var _zone   := Zone.OUTDOOR
var _player: Node3D = null

func _ready() -> void:
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_zone = _detect(_player.global_position)
		_apply(_zone)

func _process(_delta: float) -> void:
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
		return
	var z := _detect(_player.global_position)
	if z != _zone:
		_zone = z
		_apply(z)

func _detect(pos: Vector3) -> Zone:
	var flat := Vector2(pos.x, pos.z)
	if flat.distance_to(FACTORY_POS) <= FACTORY_RADIUS:
		return Zone.FACTORY
	if flat.distance_to(SHOP_POS) <= SHOP_RADIUS:
		return Zone.SHOP
	return Zone.OUTDOOR

func _apply(zone: Zone) -> void:
	_switch_stream("ambient", AMBIENT_PATHS.get(zone, ""))
	_switch_stream("music",   MUSIC_PATHS.get(zone, ""))

func _switch_stream(type: String, path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		if type == "ambient": AudioManager.stop_ambient(true)
		else:                 AudioManager.stop_music(true)
		return
	var stream: AudioStream = load(path)
	if type == "ambient": AudioManager.play_ambient(stream)
	else:                 AudioManager.play_music(stream)
