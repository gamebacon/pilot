extends StaticBody3D
class_name ShopCheckout

func interact(player: Node) -> void:
	var inv: Inventory = player.get("inventory")
	if not inv or inv.is_empty():
		return

	var total := _total(inv)
	if total == 0:
		return

	if not GameState.spend_currency(total):
		push_warning("ShopCheckout: not enough money (need $%d, have $%d)" % [total, GameState.currency])
		return

	# Items stay with the player — they've been paid for.

func get_interact_hint(player: Node) -> String:
	var inv: Inventory = player.get("inventory")
	if not inv or inv.is_empty():
		return "%s  Checkout  (hands empty)" % InputHelper.action_label("interact")
	var total := _total(inv)
	return "%s  Pay  $%d" % [InputHelper.action_label("interact"), total]

func _total(inv: Inventory) -> int:
	var sum := 0
	for item: PhysicalItem in inv.items:
		if item.item_data:
			sum += item.item_data.price
	return sum
