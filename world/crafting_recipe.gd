class_name CraftingRecipe

## Defines one craftable recipe.
## Add a new static _xxx() method and include it in all() to register it.

var display_name: String  = ""
var result_id:    String  = ""     # ItemData id of what you receive
var result_count: int     = 1      # how many you receive per craft
var ingredients:  Dictionary = {}  # {item_id: count}

# ── Registry ──────────────────────────────────────────────────────────────────

static func all() -> Array[CraftingRecipe]:
	return [
		_wooden_plank(),
		_wooden_wall(),
	]

# ── Recipes ───────────────────────────────────────────────────────────────────

static func _wooden_plank() -> CraftingRecipe:
	var r            := CraftingRecipe.new()
	r.display_name   = "Wooden Plank"
	r.result_id      = "wooden_plank"
	r.result_count   = 2
	r.ingredients    = {"wood_log": 1}
	return r

static func _wooden_wall() -> CraftingRecipe:
	var r            := CraftingRecipe.new()
	r.display_name   = "Wooden Wall"
	r.result_id      = "wooden_wall"
	r.result_count   = 1
	r.ingredients    = {"wooden_plank": 3}
	return r
