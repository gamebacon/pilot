extends Harvestable
class_name HarvestableTree

const SND_CHOP := preload("res://audio/sfx/item_collide.mp3")

const RESOURCE_HP: float = 30.0
const WOOD_DROPS:  int   = 2

func _ready() -> void:
	super()
	required_tool_type = "axe"
	_hp     = RESOURCE_HP
	_max_hp = RESOURCE_HP
	_hit_snd = AudioStreamPlayer3D.new()
	_hit_snd.stream       = SND_CHOP
	_hit_snd.max_distance = 18.0
	_hit_snd.unit_size    = 4.0
	_hit_snd.bus          = "SFX"
	add_child(_hit_snd)

# Tree is a child of a visual parent node — free the whole tree, not just the collider.
func _get_remove_target() -> Node:
	return get_parent()

func _on_depleted() -> void:
	var origin: Vector3 = (get_parent() as Node3D).global_position
	var world: Node = get_tree().get_first_node_in_group("world")
	for i in WOOD_DROPS:
		var pos: Vector3 = origin + Vector3(randf_range(-1.5, 1.5), 0.5, randf_range(-1.5, 1.5))
		if world:
			world.request_spawn_item("wood_log", pos)

func get_interact_hint(player: Node) -> String:
	var p := player as Player
	if not p: return ""
	var key := InputHelper.action_label("attack")
	if not _get_tool(p):
		return "Need an axe"
	if _hp >= RESOURCE_HP:
		return key + "  Tree"
	return key + "  %d%%" % int((1.0 - _hp / RESOURCE_HP) * 100.0)

func interact(player: Node) -> void:
	var p := player as Player
	if not p: return
	var tool_data: ToolItemData = _get_tool(p)
	if not tool_data: return

	_hit_snd.pitch_scale = randf_range(0.85, 1.15)
	_hit_snd.play()
	if p.inventory.use_active_durability(1):
		p.inventory.remove_active_one()

	if NetworkManager.is_active() and not multiplayer.is_server():
		_rpc_request_hit.rpc_id(1, tool_data.harvest_damage)
	else:
		_apply_hit(tool_data.harvest_damage)

func _get_tool(p: Player) -> ToolItemData:
	var tool_data: ToolItemData = p.inventory.active_slot_data().get_data() as ToolItemData
	if not tool_data or tool_data.tool_type != required_tool_type:
		return null
	return tool_data
