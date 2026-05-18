extends StaticBody3D

const ITEM_SCENE   := preload("res://items/physical_item.tscn")
const SND_CHOP     := preload("res://audio/sfx/item_collide.mp3")

const RESOURCE_HP  := 30
const WOOD_DROPS   := 2

var _hp: float = RESOURCE_HP
var _chop_snd: AudioStreamPlayer3D

func _ready() -> void:
	add_to_group("harvestable")
	_chop_snd = AudioStreamPlayer3D.new()
	_chop_snd.stream          = SND_CHOP
	_chop_snd.max_distance    = 18.0
	_chop_snd.unit_size       = 4.0
	_chop_snd.bus             = "SFX"
	add_child(_chop_snd)

func get_interact_hint(player: Node) -> String:
	var p := player as Player
	if not p:
		return ""
	var active := p.inventory.active()
	var has_axe := active and active.item_data is ToolItemData \
		and "tree" in (active.item_data as ToolItemData).harvest_tags
	var key := InputHelper.action_label("attack")
	if not has_axe:
		return "Need an axe to chop"
	if _hp >= RESOURCE_HP:
		return key + "  Chop Tree"
	return key + "  Keep Chopping  (%d/%d)" % [int(RESOURCE_HP - _hp), RESOURCE_HP]

func interact(player: Node) -> void:
	var p := player as Player
	if not p:
		return
	var active := p.inventory.active()
	if not (active and active.item_data is ToolItemData \
			and "tree" in (active.item_data as ToolItemData).harvest_tags):
		return

	_chop_snd.pitch_scale = randf_range(0.85, 1.15)
	_chop_snd.play()

	var tool_data := active.item_data as ToolItemData
	_hp -= tool_data.harvest_damage

	if active.use_durability(1):
		p.inventory.remove(active)
		active.queue_free()
		p._reposition_carried()

	if _hp <= 0.0:
		_fell()

func _fell() -> void:
	var origin: Vector3 = (get_parent() as Node3D).global_position
	var wood_data := ItemRegistry.get_item("wood_log")
	for i in WOOD_DROPS:
		var log := ITEM_SCENE.instantiate() as PhysicalItem
		log.item_data = wood_data
		get_tree().current_scene.add_child(log)
		log.global_position = origin + Vector3(randf_range(-1.5, 1.5), 0.5, randf_range(-1.5, 1.5))
	get_parent().queue_free()
