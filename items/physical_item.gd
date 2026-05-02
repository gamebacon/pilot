extends RigidBody3D
class_name PhysicalItem

@export var item_data: ItemData

func interact(player: Node) -> void:
	player.pick_up(self)
