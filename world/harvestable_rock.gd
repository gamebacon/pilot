extends Harvestable
class_name HarvestableDeposit

## Generic ore deposit. Set ore_data in the Inspector or via code before adding
## to the scene tree — _ready() builds the mesh and collision from it automatically.

const SND_MINE := preload("res://audio/sfx/item_collide.mp3")

@export var ore_data: OreData

func _ready() -> void:
	super()
	required_tool_type = "pickaxe"
	if ore_data:
		_hp     = float(ore_data.resource_hp)
		_max_hp = float(ore_data.resource_hp)
		_build_visual()
	_hit_snd = AudioStreamPlayer3D.new()
	_hit_snd.stream       = SND_MINE
	_hit_snd.max_distance = 18.0
	_hit_snd.unit_size    = 4.0
	_hit_snd.bus          = "SFX"
	add_child(_hit_snd)

func _build_visual() -> void:
	var size := ore_data.ore_size

	var col    := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = min(size.x, size.z) * 0.48
	col.shape     = sphere
	col.position  = Vector3(0.0, size.y * 0.46, 0.0)
	add_child(col)

	var mi  := MeshInstance3D.new()
	mi.mesh  = MeshBuilder.boulder(size)

	var mat         := StandardMaterial3D.new()
	mat.albedo_color = ore_data.ore_color
	mat.roughness    = 0.88
	mat.metallic     = 0.15
	mi.material_override = mat
	add_child(mi)

# ── Interaction ───────────────────────────────────────────────────────────────

func get_interact_hint(player: Node) -> String:
	if not ore_data: return ""
	var p := player as Player
	if not p: return ""
	var level := _get_tool_level(p)
	var key   := InputHelper.action_label("attack")
	if level < 0:
		return "Need a %s" % required_tool_type
	if level < ore_data.required_tool_level:
		return "Need a stronger tool"
	if _hp >= _max_hp:
		return "%s  %s" % [key, ore_data.display_name]
	return "%s  %d%%" % [key, int((1.0 - _hp / _max_hp) * 100.0)]

func interact(player: Node) -> void:
	if not ore_data: return
	var p := player as Player
	if not p: return
	var slot:      Inventory.ItemStack = p.inventory.active_slot_data()
	var tool_data: ToolItemData        = slot.get_data() as ToolItemData
	if not tool_data or _get_tool_level(p) < ore_data.required_tool_level:
		return

	_hit_snd.pitch_scale = randf_range(0.85, 1.15)
	_hit_snd.play()
	if p.inventory.use_active_durability(1):
		p.inventory.remove_active_one()

	if NetworkManager.is_active() and not multiplayer.is_server():
		_rpc_request_hit.rpc_id(1, tool_data.harvest_damage)
	else:
		_apply_hit(tool_data.harvest_damage)

# ── Drop spawning on depletion ────────────────────────────────────────────────

func _on_depleted() -> void:
	if not ore_data: return
	var count: int  = randi_range(ore_data.drop_count_min, ore_data.drop_count_max)
	var world: Node = get_tree().get_first_node_in_group("world")
	if world:
		for i in count:
			var pos: Vector3 = global_position + Vector3(randf_range(-1.0, 1.0), 0.6, randf_range(-1.0, 1.0))
			world.request_spawn_item(ore_data.drop_item_id, pos)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_tool_level(p: Player) -> int:
	var tool_data: ToolItemData = p.inventory.active_slot_data().get_data() as ToolItemData
	if not tool_data or tool_data.tool_type != required_tool_type:
		return -1
	return tool_data.tool_level
