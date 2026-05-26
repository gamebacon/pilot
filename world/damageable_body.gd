extends StaticBody3D
class_name DamageableBody

## Base class for any StaticBody3D that can take damage.
## Subclasses set max_hp, bar_height, and optionally hit_sound before calling super()._ready().

var damageable:   Damageable   = null
var max_hp:       float        = 100.0
var bar_height:   float        = 1.5
var scale_target: Node3D       = null
var hit_sound:    AudioStream  = null

var _snd_hit: AudioStreamPlayer3D = null

func _ready() -> void:
	damageable = Damageable.new(max_hp, bar_height)
	damageable.scale_target = scale_target if scale_target else self
	add_child(damageable)
	damageable.died.connect(_on_destroyed)
	damageable.hp_changed.connect(_on_hp_changed)

	if hit_sound:
		_snd_hit            = AudioStreamPlayer3D.new()
		_snd_hit.stream     = hit_sound
		_snd_hit.max_distance = 20.0
		_snd_hit.unit_size  = 5.0
		_snd_hit.bus        = "SFX"
		add_child(_snd_hit)

## Called on a late-joining client to restore HP state without damage signals.
func sync_hp(current: float, maximum: float) -> void:
	if damageable:
		damageable.sync_hp(current, maximum)

func take_damage(amount: float) -> void:
	if not NetworkManager.is_active() or multiplayer.is_server():
		damageable.take_damage(amount)
	else:
		_rpc_request_damage.rpc_id(1, amount)

## Client → server damage request.  Server validates and applies; the resulting
## hp_changed signal then broadcasts the bar update to all peers.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_damage(amount: float) -> void:
	if not multiplayer.is_server(): return
	damageable.take_damage(amount)

# ── Virtual hooks — override in subclass to respond ──────────────────────────

func _on_destroyed() -> void:
	queue_free()

func _on_hp_changed(_current: float, _maximum: float) -> void:
	if _snd_hit:
		_snd_hit.pitch_scale = randf_range(0.9, 1.1)
		_snd_hit.play()
