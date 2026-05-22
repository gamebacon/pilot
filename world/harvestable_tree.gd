extends StaticBody3D

const SND_CHOP := preload("res://audio/sfx/item_collide.mp3")

const RESOURCE_HP := 30
const WOOD_DROPS  := 2

var _hp: float = RESOURCE_HP
var _chop_snd: AudioStreamPlayer3D

func _ready() -> void:
	add_to_group("harvestable")
	_chop_snd = AudioStreamPlayer3D.new()
	_chop_snd.stream       = SND_CHOP
	_chop_snd.max_distance = 18.0
	_chop_snd.unit_size    = 4.0
	_chop_snd.bus          = "SFX"
	add_child(_chop_snd)

func get_interact_hint(player: Node) -> String:
	var p := player as Player
	if not p: return ""
	var key := InputHelper.action_label("attack")
	if not _has_axe(p):
		return "Need an axe to chop"
	if _hp >= RESOURCE_HP:
		return key + "  Chop Tree"
	return key + "  Keep Chopping  (%d%%)" % int((1.0 - _hp / float(RESOURCE_HP)) * 100.0)

func interact(player: Node) -> void:
	var p := player as Player
	if not p: return
	var slot := p.inventory.active_slot_data()
	var tool_data := slot.get_data() as ToolItemData
	if not tool_data or not ("tree" in tool_data.harvest_tags):
		return

	_chop_snd.pitch_scale = randf_range(0.85, 1.15)
	_chop_snd.play()

	_hp -= tool_data.harvest_damage
	if p.inventory.use_active_durability(1):
		p.inventory.remove_active_one()

	if _hp <= 0.0:
		_fell()

func _fell() -> void:
	var origin: Vector3 = (get_parent() as Node3D).global_position
	var world := get_tree().get_first_node_in_group("world")
	for i in WOOD_DROPS:
		var pos := origin + Vector3(randf_range(-1.5, 1.5), 0.5, randf_range(-1.5, 1.5))
		if world:
			world.request_spawn_item("wood_log", pos)
	get_parent().queue_free()

func _has_axe(p: Player) -> bool:
	var tool_data := p.inventory.active_slot_data().get_data() as ToolItemData
	return tool_data != null and "tree" in tool_data.harvest_tags
