extends StaticBody3D
class_name HarvestableDeposit

## Generic ore deposit. Set ore_data in the Inspector or via code before adding
## to the scene tree — _ready() builds the mesh and collision from it automatically.
## OreRegistry holds all available types; WorldGenerator spawns them weighted.

const ITEM_SCENE := preload("res://items/physical_item.tscn")
const SND_MINE   := preload("res://audio/sfx/item_collide.mp3")

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
	var s := ore_data.ore_size

	# Collision — convex sphere approximation at half-height
	var col    := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius  = min(s.x, s.z) * 0.48
	col.shape      = sphere
	col.position   = Vector3(0.0, s.y * 0.46, 0.0)
	add_child(col)

	# Visual — low-poly boulder mesh, raised to sit on the ground
	var mi       := MeshInstance3D.new()
	mi.mesh       = MeshBuilder.boulder(s)
	mi.position   = Vector3(0.0, 0.0, 0.0)

	var m          := StandardMaterial3D.new()
	m.albedo_color  = ore_data.ore_color
	m.roughness     = 0.88
	m.metallic      = clampf(float(ore_data.rarity) * 0.07, 0.0, 0.45)

	# Rare+ ores glow — emissive intensity scales with rarity tier
	if ore_data.rarity >= OreData.Rarity.RARE:
		m.emission_enabled           = true
		m.emission                   = ore_data.ore_color
		m.emission_energy_multiplier = 0.18 * float(ore_data.rarity - 1)

	mi.material_override = m
	add_child(mi)

# ── Interaction ───────────────────────────────────────────────────────────────

func get_interact_hint(player: Node) -> String:
	if not ore_data:
		return ""
	var p := player as Player
	if not p:
		return ""
	var level := _pickaxe_level(p.inventory.active())
	var key   := InputHelper.action_label("attack")
	if level < 0:
		return "Need a pickaxe to mine"
	if level < ore_data.required_tool_level:
		return "Need a %s to mine this" % ore_data.required_pickaxe_name()
	var pct := int((1.0 - _hp / float(ore_data.resource_hp)) * 100.0)
	var tag  := "[%s]  %s" % [ore_data.rarity_label(), ore_data.display_name]
	if pct == 0:
		return "%s  Mine  %s" % [key, tag]
	return "%s  Keep Mining  %s  (%d%%)" % [key, tag, pct]

func interact(player: Node) -> void:
	if not ore_data:
		return
	var p := player as Player
	if not p:
		return
	var active := p.inventory.active()
	if _pickaxe_level(active) < ore_data.required_tool_level:
		return

	_mine_snd.pitch_scale = randf_range(0.85, 1.15)
	_mine_snd.play()

	var tool_data := active.item_data as ToolItemData
	_hp -= tool_data.harvest_damage

	if active.use_durability(1):
		p.inventory.remove(active)
		active.queue_free()
		p._reposition_carried()

	if _hp <= 0.0:
		_exhaust()

func _exhaust() -> void:
	var drop_data := ItemRegistry.get_item(ore_data.drop_item_id)
	if drop_data:
		var count := randi_range(ore_data.drop_count_min, ore_data.drop_count_max)
		for i in count:
			var item := ITEM_SCENE.instantiate() as PhysicalItem
			item.item_data = drop_data
			get_tree().current_scene.add_child(item)
			item.global_position = global_position + Vector3(
				randf_range(-1.0, 1.0), 0.6, randf_range(-1.0, 1.0))
	queue_free()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _pickaxe_level(item: PhysicalItem) -> int:
	if not item or not (item.item_data is ToolItemData):
		return -1
	var td := item.item_data as ToolItemData
	if td.tool_type != "pickaxe":
		return -1
	return td.tool_level
