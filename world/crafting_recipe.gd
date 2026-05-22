class_name CraftingRecipe

## Defines one craftable recipe.
## Add a new static _xxx() method and include it in all() to register it.

var display_name: String  = ""
var result_id:    String  = ""     # ItemData id of what you receive
var result_count: int     = 1      # how many you receive per craft
var ingredients:  Dictionary = {}  # {item_id: count}

## Which crafting tab this recipe appears under: "materials", "tools", "weapons"
var tab: String = "materials"

# ── Registry ──────────────────────────────────────────────────────────────────

static func all() -> Array[CraftingRecipe]:
	return [
		# Materials
		_wooden_plank(),
		_chest(),
		# Building — twig tier
		_foundation_twig(),
		_wall_twig(),
		_tower_twig(),
		# Tools
		_axe_wooden(),
		_axe_stone(),
		_axe_iron(),
		_pickaxe_wooden(),
		_pickaxe_stone(),
		_pickaxe_iron(),
		# Weapons
		_sword_wooden(),
		_sword_stone(),
		_sword_iron(),
	]

static func by_tab(filter_tab: String) -> Array[CraftingRecipe]:
	var result: Array[CraftingRecipe] = []
	for r in all():
		if r.tab == filter_tab:
			result.append(r)
	return result

# ── Materials ─────────────────────────────────────────────────────────────────

static func _wooden_plank() -> CraftingRecipe:
	var r            := CraftingRecipe.new()
	r.display_name   = "Wooden Plank"
	r.result_id      = "wooden_plank"
	r.result_count   = 2
	r.ingredients    = {"wood_log": 1}
	r.tab            = "materials"
	return r

static func _foundation_twig() -> CraftingRecipe:
	var r          := CraftingRecipe.new()
	r.display_name  = "Foundation"
	r.result_id     = "foundation"
	r.result_count  = 1
	r.ingredients   = {"wood_log": 2}
	r.tab           = "materials"
	return r

static func _wall_twig() -> CraftingRecipe:
	var r          := CraftingRecipe.new()
	r.display_name  = "Wall"
	r.result_id     = "wall"
	r.result_count  = 1
	r.ingredients   = {"wood_log": 1}
	r.tab           = "materials"
	return r

static func _tower_twig() -> CraftingRecipe:
	var r          := CraftingRecipe.new()
	r.display_name  = "Tower"
	r.result_id     = "tower"
	r.result_count  = 1
	r.ingredients   = {"wood_log": 4}
	r.tab           = "materials"
	return r

static func _chest() -> CraftingRecipe:
	var r          := CraftingRecipe.new()
	r.display_name  = "Chest"
	r.result_id     = "chest"
	r.result_count  = 1
	r.ingredients   = {"wooden_plank": 8}
	r.tab           = "materials"
	return r

# ── Tools ─────────────────────────────────────────────────────────────────────

static func _axe_wooden() -> CraftingRecipe:
	var r            := CraftingRecipe.new()
	r.display_name   = "Wooden Axe"
	r.result_id      = "axe_wooden"
	r.result_count   = 1
	r.ingredients    = {"wooden_plank": 2, "wood_log": 1}
	r.tab            = "tools"
	return r

static func _axe_stone() -> CraftingRecipe:
	var r            := CraftingRecipe.new()
	r.display_name   = "Stone Axe"
	r.result_id      = "axe_stone"
	r.result_count   = 1
	r.ingredients    = {"stone": 2, "wooden_plank": 1}
	r.tab            = "tools"
	return r

static func _pickaxe_wooden() -> CraftingRecipe:
	var r            := CraftingRecipe.new()
	r.display_name   = "Wooden Pickaxe"
	r.result_id      = "pickaxe_wooden"
	r.result_count   = 1
	r.ingredients    = {"wooden_plank": 2, "wood_log": 1}
	r.tab            = "tools"
	return r

static func _pickaxe_stone() -> CraftingRecipe:
	var r            := CraftingRecipe.new()
	r.display_name   = "Stone Pickaxe"
	r.result_id      = "pickaxe_stone"
	r.result_count   = 1
	r.ingredients    = {"stone": 3, "wooden_plank": 1}
	r.tab            = "tools"
	return r

static func _axe_iron() -> CraftingRecipe:
	var r            := CraftingRecipe.new()
	r.display_name   = "Iron Axe"
	r.result_id      = "axe_iron"
	r.result_count   = 1
	r.ingredients    = {"iron_ore": 2, "wooden_plank": 1}
	r.tab            = "tools"
	return r

static func _pickaxe_iron() -> CraftingRecipe:
	var r            := CraftingRecipe.new()
	r.display_name   = "Iron Pickaxe"
	r.result_id      = "pickaxe_iron"
	r.result_count   = 1
	r.ingredients    = {"iron_ore": 3, "wooden_plank": 1}
	r.tab            = "tools"
	return r

# ── Weapons ───────────────────────────────────────────────────────────────────

static func _sword_wooden() -> CraftingRecipe:
	var r            := CraftingRecipe.new()
	r.display_name   = "Wooden Sword"
	r.result_id      = "sword_wooden"
	r.result_count   = 1
	r.ingredients    = {"wooden_plank": 2, "wood_log": 1}
	r.tab            = "weapons"
	return r

static func _sword_stone() -> CraftingRecipe:
	var r            := CraftingRecipe.new()
	r.display_name   = "Stone Sword"
	r.result_id      = "sword_stone"
	r.result_count   = 1
	r.ingredients    = {"stone": 2, "wooden_plank": 1}
	r.tab            = "weapons"
	return r

static func _sword_iron() -> CraftingRecipe:
	var r            := CraftingRecipe.new()
	r.display_name   = "Iron Sword"
	r.result_id      = "sword_iron"
	r.result_count   = 1
	r.ingredients    = {"iron_ore": 2, "wooden_plank": 1}
	r.tab            = "weapons"
	return r
