extends InventoryWindow
class_name ChestUI

const CHEST_ROWS: int = 4

var _chest: Node = null

func _window_title()  -> String: return "CHEST"
func _window_layout() -> Layout: return Layout.CENTERED

func _make_controller() -> InventoryController:
	return ChestInventoryController.new()

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

func _get_ctrl_cursor_pos() -> Vector2:
	var cur := _controller.cursor
	if cur >= 0 and cur < _slots.size() and _slots[cur] != null:
		return _slots[cur].global_position
	return get_viewport().get_mouse_position()

func _on_opened() -> void:
	if not _chest:
		return
	_controller.nav_rows = CHEST_ROWS + Inventory.ROWS + Inventory.HOTBAR_ROWS
	_controller.nav_cols = Inventory.COLS
	_controller.reset_cursor()
	_inv        = _chest.inventory
	_player_inv = _player.inventory
	var c := _controller as ChestInventoryController
	c.chest_net_id = _chest.inventory.container_net_id
	c.inv          = _inv
	c.player_inv   = _player_inv
	if not _inv.changed.is_connected(_on_inv_changed):
		_inv.changed.connect(_on_inv_changed)
	if not _player_inv.changed.is_connected(_on_inv_changed):
		_player_inv.changed.connect(_on_inv_changed)
	if NetworkManager.is_active():
		var world := get_tree().get_first_node_in_group("world")
		if world and not world.chest_take_denied.is_connected(c.on_take_denied):
			world.chest_take_denied.connect(c.on_take_denied)
	_refresh()

func _on_closed() -> void:
	if NetworkManager.is_active():
		var world := get_tree().get_first_node_in_group("world")
		if world:
			var c := _controller as ChestInventoryController
			if world.chest_take_denied.is_connected(c.on_take_denied):
				world.chest_take_denied.disconnect(c.on_take_denied)
	if _inv and _inv.changed.is_connected(_on_inv_changed):
		_inv.changed.disconnect(_on_inv_changed)
	if _player_inv and _player_inv.changed.is_connected(_on_inv_changed):
		_player_inv.changed.disconnect(_on_inv_changed)
	_chest = null

func _refresh() -> void:
	super._refresh()
	if not _ctrl_nav: return
	var cur := _controller.cursor
	for i: int in _slots.size():
		if _slots[i] != null:
			_slots[i].set_cursor(i == cur)
	var sv: Inventory = _controller.sinv(cur)
	if sv:
		var slot: Inventory.ItemStack = sv.get_slot(_controller.sidx(cur))
		if not slot.is_empty() and cur < _slots.size() and _slots[cur] != null:
			ItemTooltip.show_for(slot.get_data(), slot.net_ids, slot.get_durability(), _slots[cur])
		else:
			ItemTooltip.hide()
	else:
		ItemTooltip.hide()

func _on_inv_changed() -> void:
	if visible:
		_refresh()
