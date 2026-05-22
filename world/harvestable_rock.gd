extends StaticBody3D
class_name HarvestableDeposit

## Generic ore deposit. Set ore_data in the Inspector or via code before adding
## to the scene tree — _ready() builds the mesh and collision from it automatically.

const SND_MINE := preload("res://audio/sfx/item_collide.mp3")

@export var ore_data: OreData

var _hp: float = 0.0
var _mine_snd: AudioStreamPlayer3D = null

func _ready() -> void:
	add_to_group("harvestable")
	if ore_data:
		_hp = float(ore_data.resource_hp)
		_build_visual()
	_mine_snd = AudioStreamPlayer3D.new()
	_mine_snd.stream       = SND_MINE
	_mine_snd.max_distance = 18.0
	_mine_snd.unit_size    = 4.0
	_mine_snd.bus          = "SFX"
	add_child(_mine_snd)

func _build_visual() -> void:
	var size := ore_data.ore_size

	var col    := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = min(size.x, size.z) * 0.48
	col.shape     = sphere
	col.position  = Vector3(0.0, size.y * 0.46, 0.0)
	add_child(col)

	var mi   := MeshInstance3D.new()
	mi.mesh   = MeshBuilder.boulder(size)

	var mat          := StandardMaterial3D.new()
	mat.albedo_color  = ore_data.ore_color
	mat.roughness     = 0.88
	mat.metallic      = clampf(float(ore_data.rarity) * 0.07, 0.0, 0.45)

	if ore_data.rarity >= OreData.Rarity.RARE:
		mat.emission_enabled           = true
		mat.emission                   = ore_data.ore_color
		mat.emission_energy_multiplier = 0.18 * float(ore_data.rarity - 1)

	mi.material_override = mat
	add_child(mi)

# ── Interaction ───────────────────────────────────────────────────────────────

func get_interact_hint(player: Node) -> String:
	if not ore_data: return ""
	var p := player as Player
	if not p: return ""
	var level := _pickaxe_level(p)
	var key   := InputHelper.action_label("attack")
	if level < 0:
		return "Need a pickaxe to mine"
	if level < ore_data.required_tool_level:
		return "Need a %s to mine this" % ore_data.required_pickaxe_name()
	var pct := int((1.0 - _hp / float(ore_data.resource_hp)) * 100.0)
	var tag := "[%s]  %s" % [ore_data.rarity_label(), ore_data.display_name]
	if pct == 0:
		return "%s  Mine  %s" % [key, tag]
	return "%s  Keep Mining  %s  (%d%%)" % [key, tag, pct]

func interact(player: Node) -> void:
	if not ore_data: return
	var p := player as Player
	if not p: return
	var slot      := p.inventory.active_slot_data()
	var tool_data := slot.get_data() as ToolItemData
	if not tool_data or _pickaxe_level(p) < ore_data.required_tool_level:
		return

	_mine_snd.pitch_scale = randf_range(0.85, 1.15)
	_mine_snd.play()

	_hp -= tool_data.harvest_damage
	if p.inventory.use_active_durability(1):
		p.inventory.remove_active_one()

	if _hp <= 0.0:
		_exhaust()

func _exhaust() -> void:
	if ore_data:
		var count := randi_range(ore_data.drop_count_min, ore_data.drop_count_max)
		var world := get_tree().get_first_node_in_group("world")
		if world:
			for i in count:
				var pos := global_position + Vector3(randf_range(-1.0, 1.0), 0.6, randf_range(-1.0, 1.0))
				world.request_spawn_item(ore_data.drop_item_id, pos)
	queue_free()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _pickaxe_level(p: Player) -> int:
	var tool_data := p.inventory.active_slot_data().get_data() as ToolItemData
	if not tool_data or tool_data.tool_type != "pickaxe":
		return -1
	return tool_data.tool_level
