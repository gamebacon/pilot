extends DamageableBody
class_name Harvestable

## Base class for all harvestable world resources (trees, ore deposits, etc.).
## Set max_hp and bar_height before calling super()._ready().
## Override _on_depleted() and _get_remove_target() for drop and removal behaviour.

var required_tool_type: String    = ""
var _is_depleted:       bool      = false
var _hit_snd: AudioStreamPlayer3D = null

func _ready() -> void:
	add_to_group("harvestable")
	super()

# ── Server-side damage ────────────────────────────────────────────────────────

func _apply_hit(damage: float) -> void:
	damageable.take_damage(damage)

@rpc("any_peer", "reliable")
func _rpc_request_hit(damage: float) -> void:
	if not multiplayer.is_server(): return
	_apply_hit(damage)

# ── Multiplayer bar sync ──────────────────────────────────────────────────────

func _on_hp_changed(current: float, maximum: float) -> void:
	if NetworkManager.is_active():
		_rpc_hp_update.rpc(current, maximum)

@rpc("authority", "call_remote", "unreliable")
func _rpc_hp_update(current: float, maximum: float) -> void:
	damageable.show_hit(current, maximum)

# ── Destruction ───────────────────────────────────────────────────────────────

func _on_destroyed() -> void:
	if _is_depleted: return
	_is_depleted = true
	_on_depleted()
	_do_remove()

func _do_remove() -> void:
	if NetworkManager.is_active():
		_rpc_remove.rpc()
	else:
		_get_remove_target().queue_free()

@rpc("authority", "call_local", "reliable")
func _rpc_remove() -> void:
	_get_remove_target().queue_free()

# ── Overridable hooks ─────────────────────────────────────────────────────────

func _on_depleted() -> void:
	pass

func _get_remove_target() -> Node:
	return self

func get_interact_hint(_player: Node) -> String:
	return ""

func interact(_player: Node) -> void:
	pass
