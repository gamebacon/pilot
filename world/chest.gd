extends StaticBody3D

@onready var inventory: Inventory = $Inventory

var net_id: int = 0
var _chest_ui: Node = null

func _ready() -> void:
	add_to_group("chests")
	# net_id is set by the build system before add_child, so propagate it now.
	if net_id != 0:
		inventory.container_net_id = net_id

func get_interact_hint(_player: Node) -> String:
	return InputHelper.action_label("interact") + "  Open Chest"

func interact(player: Node) -> void:
	if not _chest_ui or not is_instance_valid(_chest_ui):
		_chest_ui = load("res://ui/chest_ui.gd").new()
		get_tree().current_scene.add_child(_chest_ui)
	_chest_ui.open_chest(self, player)
