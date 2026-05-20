extends InventoryWindow
class_name ChestUI

const CHEST_ROWS := 3

var _chest: Node = null

func _window_title()  -> String: return "CHEST"
func _window_layout() -> Layout: return Layout.CENTERED

func _make_controller() -> InventoryController:
	return PlayerInventoryController.new()

func open_chest(chest_node: Node, player: Node) -> void:
	_chest = chest_node
	open(player)

func _build_content(vbox: VBoxContainer) -> void:
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
	vbox.add_child(grid)
	for r in CHEST_ROWS:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", UIStyle.SLOT_GAP)
		grid.add_child(hbox)
		for c in Inventory.COLS:
			_build_slot(hbox, r * Inventory.COLS + c)
	_build_player_section(vbox)

func _on_opened() -> void:
	if not _chest:
		return
	_inv        = _chest.inventory
	_player_inv = _player.inventory
	_controller.inv        = _inv
	_controller.player_inv = _player_inv
	if not _inv.changed.is_connected(_on_inv_changed):
		_inv.changed.connect(_on_inv_changed)
	if not _player_inv.changed.is_connected(_on_inv_changed):
		_player_inv.changed.connect(_on_inv_changed)
	_refresh()

func _on_closed() -> void:
	if _inv and _inv.changed.is_connected(_on_inv_changed):
		_inv.changed.disconnect(_on_inv_changed)
	if _player_inv and _player_inv.changed.is_connected(_on_inv_changed):
		_player_inv.changed.disconnect(_on_inv_changed)
	_chest = null

func _on_inv_changed() -> void:
	if visible:
		_refresh()
