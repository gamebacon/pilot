extends StaticBody3D

const ITEM_SCENE   := preload("res://items/physical_item.tscn")
const SND_CHOP     := preload("res://audio/sfx/item_collide.mp3")  # swap for a real axe thud

var _chop_snd: AudioStreamPlayer3D = null

## Total HP of this tree. Reduce to make trees easier to fell.
const RESOURCE_HP  := 30
## Wood logs dropped when felled.
const WOOD_DROPS   := 2

var _hp: float = RESOURCE_HP

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
	if not p or not p.inventory.has_id("stone"):
		return "Need a stone to chop"
	var key := InputHelper.action_label("attack")
	if _hp >= RESOURCE_HP:
		return key + "  Chop Tree"
	return key + "  Keep Chopping  (%d/%d)" % [int(RESOURCE_HP - _hp), RESOURCE_HP]

func interact(player: Node) -> void:
	var p := player as Player
	if not p or not p.inventory.has_id("stone"):
		return
	_chop_snd.pitch_scale = randf_range(0.85, 1.15)
	_chop_snd.play()
	# TODO: scale damage by held tool type.
	var dmg := _hit_damage(p)
	_hp -= dmg
	if _hp <= 0.0:
		_fell()

## Damage dealt per hit. Scales with tool in the future.
func _hit_damage(_player: Player) -> float:
	return 10.0

func _fell() -> void:
	var origin: Vector3 = (get_parent() as Node3D).global_position
	var wood_data := ItemRegistry.get_item("wood_log")
	for i in WOOD_DROPS:
		var log := ITEM_SCENE.instantiate() as PhysicalItem
		log.item_data = wood_data
		get_tree().current_scene.add_child(log)
		log.global_position = origin + Vector3(randf_range(-1.5, 1.5), 0.5, randf_range(-1.5, 1.5))
	get_parent().queue_free()
