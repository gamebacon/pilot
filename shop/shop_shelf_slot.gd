extends StaticBody3D
class_name ShopShelfSlot

@export var item_data: ItemData

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var label: Label3D               = $PriceTag/Label3D
@onready var spawn_marker: Marker3D       = $SpawnMarker

func _ready() -> void:
	if item_data:
		apply_display()

func apply_display() -> void:
	var raw     := item_data.size
	var longest := maxf(raw.x, maxf(raw.y, raw.z))
	var scale   := clampf(0.28 / longest, 0.3, 3.0)
	var display_size := raw * scale

	var box := BoxMesh.new()
	box.size = display_size
	mesh_instance.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = item_data.color
	mesh_instance.material_override = mat

	# Sit the item on the shelf surface.
	# Slot origin is at the shelf top (y=0 local), so we lift by half the item height.
	var y_offset := display_size.y * 0.5
	mesh_instance.position = Vector3(0, y_offset, 0)

	var shape := BoxShape3D.new()
	shape.size = display_size + Vector3(0.05, 0.05, 0.05)
	$CollisionShape3D.shape  = shape
	$CollisionShape3D.position = Vector3(0, y_offset, 0)

	label.text = _label_text()

func _label_text() -> String:
	var mass_str: String
	if item_data.mass >= 1.0:
		mass_str = "%.1f kg" % item_data.mass
	else:
		mass_str = "%d g" % roundi(item_data.mass * 1000.0)
	return "%s\n$%d  %s" % [item_data.display_name.to_upper(), item_data.price, mass_str]

func interact(_player: Node) -> void:
	if not item_data:
		return
	if not GameState.spend_currency(item_data.price):
		return
	var item_scene: PackedScene = preload("res://items/physical_item.tscn")
	var item := item_scene.instantiate() as PhysicalItem
	item.item_data = item_data
	get_tree().current_scene.add_child(item)
	item.global_position = spawn_marker.global_position

func get_interact_hint(_player: Node) -> String:
	if not item_data:
		return ""
	if GameState.currency < item_data.price:
		return "Not enough money  ($%d)" % item_data.price
	return "%s  Buy  %s  $%d" % [
		InputHelper.action_label("interact"),
		item_data.display_name,
		item_data.price,
	]
