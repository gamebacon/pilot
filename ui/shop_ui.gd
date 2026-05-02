extends CanvasLayer
class_name ShopUI

@onready var panel: Panel = $Panel
@onready var item_list: VBoxContainer = $Panel/VBox/Scroll/ItemList
@onready var currency_label: Label = $Panel/VBox/CurrencyLabel
@onready var close_button: Button = $Panel/VBox/CloseButton

var _current_shop: Node = null

func _ready() -> void:
	add_to_group("shop_ui")
	panel.hide()
	close_button.pressed.connect(_on_close)
	GameState.currency_changed.connect(_update_currency)

func open(stock: Array[ItemData], shop: Node) -> void:
	_current_shop = shop
	_populate(stock)
	_update_currency(GameState.currency)
	panel.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_close() -> void:
	panel.hide()
	_current_shop = null
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _populate(stock: Array[ItemData]) -> void:
	for child in item_list.get_children():
		child.queue_free()

	for item in stock:
		var row := HBoxContainer.new()

		var name_label := Label.new()
		name_label.text = "%s — $%d" % [item.display_name, item.price]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var buy_btn := Button.new()
		buy_btn.text = "Buy"
		buy_btn.pressed.connect(_buy_item.bind(item))
		row.add_child(buy_btn)

		item_list.add_child(row)

func _buy_item(item: ItemData) -> void:
	if not GameState.spend_currency(item.price):
		push_warning("Not enough money for %s ($%d)" % [item.display_name, item.price])
		return
	if _current_shop and _current_shop.has_method("spawn_item"):
		_current_shop.spawn_item(item)

func _update_currency(amount: int) -> void:
	currency_label.text = "Balance: $%d" % amount

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and panel.visible:
		_on_close()
