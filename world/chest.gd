extends DamageableBody

@onready var inventory: Inventory = $Inventory

var net_id:    int  = 0
var _chest_ui: Node = null

const SND_HIT := preload("res://audio/sfx/item_collide.mp3")

func _ready() -> void:
	max_hp     = 80.0
	bar_height = 1.3
	hit_sound  = SND_HIT
	super()
	add_to_group("chests")
	if net_id != 0:
		inventory.container_net_id = net_id

func get_interact_hint(_player: Node) -> String:
	return InputHelper.action_label("interact") + "  Open Chest"

func interact(player: Node) -> void:
	if not _chest_ui or not is_instance_valid(_chest_ui):
		_chest_ui = load("res://ui/chest_ui.gd").new()
		get_tree().current_scene.add_child(_chest_ui)
	_chest_ui.open_chest(self, player)

func _on_hp_changed(current: float, maximum: float) -> void:
	super(current, maximum)
	if NetworkManager.is_active():
		_rpc_hp_sync.rpc(current, maximum)

@rpc("authority", "call_remote", "unreliable")
func _rpc_hp_sync(current: float, maximum: float) -> void:
	damageable.show_hit(current, maximum)

func _on_destroyed() -> void:
	_scatter_loot()
	if NetworkManager.is_active():
		_rpc_destroy.rpc()
	else:
		queue_free()

func _scatter_loot() -> void:
	var world: Node = get_tree().get_first_node_in_group("world")
	if not world: return
	for i: int in inventory.total_slots:
		var slot: Inventory.ItemStack = inventory.get_slot(i)
		if slot.is_empty(): continue
		for _j: int in slot.quantity:
			var offset := Vector3(randf_range(-1.2, 1.2), 0.5, randf_range(-1.2, 1.2))
			world.request_spawn_item(slot.item_id, global_position + offset)

@rpc("authority", "call_local", "reliable")
func _rpc_destroy() -> void:
	queue_free()
