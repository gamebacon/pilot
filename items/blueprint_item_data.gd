class_name BlueprintItemData
extends ItemData
# Use this class for blueprint items instead of plain ItemData.
# All blueprint items share the same rolled-scroll look so they stack identically
# and you only need to set id, display_name, price, description, and blueprint_data.

func _init() -> void:
	is_blueprint = true
	category     = GameConstants.CAT_BLUEPRINTS
	size         = Vector3(0.60, 0.05, 0.15)   # rolled scroll
	color        = Color(0.87, 0.78, 0.55, 1.0) # parchment
	mass         = 0.2
	carry_stack  = 1
