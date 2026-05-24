class_name OreRegistry

## Static registry of all ore deposit types.
## Used by HarvestableDeposit for hints and by WorldGenerator for weighted spawning.

const _ALL: Array = [
	preload("res://world/ores/coal_deposit.tres"),
	preload("res://world/ores/copper_deposit.tres"),
	preload("res://world/ores/iron_deposit.tres"),
	preload("res://world/ores/quartz_deposit.tres"),
	preload("res://world/ores/gold_deposit.tres"),
	preload("res://world/ores/amber_deposit.tres"),
	preload("res://world/ores/diamond_deposit.tres"),
	preload("res://world/ores/obsidian_deposit.tres"),
]

static func all() -> Array[OreData]:
	var result: Array[OreData] = []
	result.assign(_ALL)
	return result

## Weighted random pick — rarer ores are naturally less likely.
static func get_random_weighted(rng: RandomNumberGenerator) -> OreData:
	var total := 0.0
	for o: OreData in _ALL:
		total += o.spawn_weight
	var roll := rng.randf() * total
	var acc  := 0.0
	for o: OreData in _ALL:
		acc += o.spawn_weight
		if roll <= acc:
			return o
	return _ALL.back()

