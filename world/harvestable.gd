extends StaticBody3D
class_name Harvestable

## Base class for all harvestable world resources (trees, ore deposits, etc.).
## Subclasses implement _on_depleted() to spawn drops and override
## _get_remove_target() if the node to free is not self.

var required_tool_type: String = ""

var _hp:          float = 0.0
var _max_hp:      float = 0.0
var _is_depleted: bool  = false
var _hit_snd:     AudioStreamPlayer3D = null

func _ready() -> void:
	add_to_group("harvestable")

func get_interact_hint(_player: Node) -> String:
	return ""

func interact(_player: Node) -> void:
	pass

# ── Server-side damage ────────────────────────────────────────────────────────

func _apply_hit(damage: float) -> void:
	_hp -= damage
	if _hp <= 0.0 and not _is_depleted:
		_is_depleted = true
		_on_depleted()
		_do_remove()

@rpc("any_peer", "reliable")
func _rpc_request_hit(damage: float) -> void:
	if not multiplayer.is_server(): return
	_apply_hit(damage)

# ── Removal — server broadcasts to all peers ──────────────────────────────────

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
