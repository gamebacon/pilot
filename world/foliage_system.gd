extends Node3D

# ─────────────────────────────────────────────────────────────────────────────
# Foliage System
#
# All spawnable types live in TYPES as plain Dictionaries — nothing about
# individual species is hard-coded in the placement engine. To add a new type,
# append a dict; the loop picks it up automatically.
#
# Dict keys
#   builder        String   method name on this script: (pos, p, rng) -> Node3D
#   count          int      target spawn count across the whole map
#   min_dist       float    minimum separation from any already-placed object (m)
#   h_min / h_max  float    normalised height [0..1] band where this type appears
#   w_bog          float    spawn weight in terrain biome: bog
#   w_forest       float    spawn weight in terrain biome: forest
#   w_rocky        float    spawn weight in terrain biome: rocky
#   zones          Array[float]  spawn weight per forest zone (see _zone_idx):
#                    [0] Spruce forest   [1] Conifer mix   [2] Birch grove
#                    [3] Pine upland     [4] Open / cleared
#   p              Dictionary  forwarded verbatim to the builder
# ─────────────────────────────────────────────────────────────────────────────
const HarvestableTree = preload("res://world/harvestable_tree.gd")
const ITEM_SCENE      = preload("res://items/physical_item.tscn")

const LOG_SPAWN_CHANCE := 0.10

const TYPES: Array = [
	# zones: [spruce-forest, conifer-mix, birch-grove, pine-upland, open/cleared]
	# density: true = apply density-noise modulation (good for grass/flowers/shrubs)
	#          false = skip it (trees space themselves via min_dist already)

	# ── Spruce — dominates its zone, rare elsewhere ───────────────────────────
	{ "builder": "_build_spruce",    "count": 200, "min_dist": 4.8, "density": false,
	  "h_min": 0.0,  "h_max": 0.85, "w_bog": 0.15, "w_forest": 0.90, "w_rocky": 0.35,
	  "zones": [0.95, 0.65, 0.12, 0.06, 0.04],
	  "p": { "s_min": 0.9, "s_max": 1.7,
	         "col_f": Color(0.07, 0.12, 0.06), "col_t": Color(0.13, 0.09, 0.05) } },
	# ── Pine — dominates upland, mixes into conifer zone ─────────────────────
	{ "builder": "_build_pine",      "count": 110, "min_dist": 3.8, "density": false,
	  "h_min": 0.12, "h_max": 1.0,  "w_bog": 0.05, "w_forest": 0.45, "w_rocky": 0.82,
	  "zones": [0.08, 0.65, 0.10, 0.96, 0.05],
	  "p": { "s_min": 0.8, "s_max": 1.3,
	         "col_f": Color(0.06, 0.10, 0.05), "col_t": Color(0.11, 0.07, 0.04) } },
	# ── Birch — grove zones and bog edges ─────────────────────────────────────
	{ "builder": "_build_birch",     "count": 80, "min_dist": 3.2, "density": false,
	  "h_min": 0.0,  "h_max": 0.60, "w_bog": 0.55, "w_forest": 0.60, "w_rocky": 0.05,
	  "zones": [0.06, 0.28, 0.94, 0.16, 0.22],
	  "p": { "s_min": 0.8, "s_max": 1.4,
	         "col_c": Color(0.20, 0.27, 0.09), "col_t": Color(0.68, 0.66, 0.60) } },
	# ── Dead tree — open clearings and bog ────────────────────────────────────
	{ "builder": "_build_dead_tree", "count": 30, "min_dist": 4.0, "density": false,
	  "h_min": 0.0,  "h_max": 1.0,  "w_bog": 0.65, "w_forest": 0.08, "w_rocky": 0.42,
	  "zones": [0.04, 0.06, 0.10, 0.14, 0.80],
	  "p": { "s_min": 0.7, "s_max": 1.3, "col_t": Color(0.18, 0.15, 0.11) } },
	# ── Forest understory bush — follows conifers ─────────────────────────────
	{ "builder": "_build_bush",      "count": 280, "min_dist": 1.8, "density": true,
	  "h_min": 0.0,  "h_max": 0.72, "w_bog": 0.25, "w_forest": 0.88, "w_rocky": 0.12,
	  "zones": [0.82, 0.84, 0.62, 0.20, 0.25],
	  "p": { "s_min": 0.35, "s_max": 0.90,
	         "cols": [Color(0.09, 0.15, 0.06), Color(0.11, 0.17, 0.07), Color(0.08, 0.12, 0.05)] } },
	# ── Autumn/bog shrub — open and bog zones ─────────────────────────────────
	{ "builder": "_build_bush",      "count": 120, "min_dist": 1.6, "density": true,
	  "h_min": 0.0,  "h_max": 0.50, "w_bog": 0.72, "w_forest": 0.22, "w_rocky": 0.05,
	  "zones": [0.10, 0.14, 0.40, 0.10, 0.85],
	  "p": { "s_min": 0.25, "s_max": 0.65,
	         "cols": [Color(0.38, 0.20, 0.06), Color(0.45, 0.16, 0.05), Color(0.30, 0.25, 0.06)] } },
	# ── Stumps — inside conifer zones ────────────────────────────────────────
	{ "builder": "_build_stump",     "count": 60, "min_dist": 2.0, "density": false,
	  "h_min": 0.0,  "h_max": 0.80, "w_bog": 0.35, "w_forest": 0.65, "w_rocky": 0.20,
	  "zones": [0.62, 0.72, 0.40, 0.22, 0.18],
	  "p": { "s_min": 0.5, "s_max": 1.1, "col_t": Color(0.16, 0.11, 0.07) } },
	# ── Boulders — pine upland and open ──────────────────────────────────────
	{ "builder": "_build_boulder",   "count": 80, "min_dist": 1.8, "density": false,
	  "h_min": 0.0,  "h_max": 1.0,  "w_bog": 0.18, "w_forest": 0.28, "w_rocky": 0.92,
	  "zones": [0.22, 0.28, 0.16, 0.82, 0.52],
	  "p": { "s_min": 0.4, "s_max": 1.7, "cluster": 3, "col": Color(0.25, 0.23, 0.20) } },
	# ── Grass — dense in open/birch, sparse under conifers ───────────────────
	{ "builder": "_build_grass",     "count": 1400, "min_dist": 0.55, "density": true,
	  "h_min": 0.0,  "h_max": 0.78, "w_bog": 0.92, "w_forest": 0.72, "w_rocky": 0.20,
	  "zones": [0.38, 0.50, 0.82, 0.28, 0.98],
	  "p": { "cols": [Color(0.10, 0.17, 0.06), Color(0.12, 0.19, 0.07), Color(0.09, 0.15, 0.05),
	                   Color(0.11, 0.18, 0.05), Color(0.08, 0.14, 0.07)] } },
	# ── Meadow flowers — open and birch zones ────────────────────────────────
	{ "builder": "_build_flower",    "count": 240, "min_dist": 0.8, "density": true,
	  "h_min": 0.0,  "h_max": 0.58, "w_bog": 0.82, "w_forest": 0.40, "w_rocky": 0.08,
	  "zones": [0.12, 0.16, 0.52, 0.08, 0.94],
	  "p": { "cols": [Color(0.88, 0.18, 0.18), Color(0.92, 0.78, 0.12), Color(0.90, 0.78, 0.82),
	                   Color(0.58, 0.18, 0.72), Color(0.95, 0.50, 0.10)],
	         "s_min": 0.14, "s_max": 0.42 } },
	# ── Alpine flowers — pine upland only ────────────────────────────────────
	{ "builder": "_build_flower",    "count": 90, "min_dist": 1.2, "density": true,
	  "h_min": 0.52, "h_max": 1.0,  "w_bog": 0.05, "w_forest": 0.15, "w_rocky": 0.72,
	  "zones": [0.05, 0.08, 0.05, 0.72, 0.28],
	  "p": { "cols": [Color(0.78, 0.86, 0.98), Color(0.65, 0.76, 0.94), Color(0.88, 0.88, 0.95)],
	         "s_min": 0.10, "s_max": 0.28 } },
]

# Material caches — shared within this session to keep draw-call count low.
var _mat_cache:     Dictionary = {}
var _dbl_mat_cache: Dictionary = {}   # double-sided (grass blades)

# Forest-zone noise — large scale (~250 m patches), decides which species dominates.
var _forest_noise  := FastNoiseLite.new()
# Density noise — medium scale, punches clearings and thickens dense areas.
var _density_noise := FastNoiseLite.new()

# Grass batch — filled during placement, flushed into a MultiMeshInstance3D at the end.
# Storing data here rather than building individual nodes keeps grass at 1 draw call total.
var _pending_grass: Array = []   # Array[Dictionary{pos, col, s, rot}]

# ─── Entry ────────────────────────────────────────────────────────────────────

# Called by WorldGenerator after terrain + roads are built.
#
#   rng        — seeded RNG passed in from the generator (keeps world deterministic)
#   biome_noise — same noise used for terrain colour, so biome matches visuals
#   height_fn  — Callable (wx, wz) -> float   samples terrain height
#   valid_fn   — Callable (wx, wz, placed, min_dist) -> bool   checks placement
#   ox / oz    — terrain origin (world X, world Z)
#   tw / td    — terrain width / depth
#   h_amp      — HEIGHT_AMP constant (maps raw height → normalised 0..1)
func populate(
		rng:         RandomNumberGenerator,
		biome_noise: FastNoiseLite,
		height_fn:   Callable,
		valid_fn:    Callable,
		ox: float, oz: float,
		tw: float, td: float,
		h_amp: float,
		seed_val: int) -> void:

	# Large-scale forest-type zones — low frequency creates big cohesive patches.
	_forest_noise.seed           = seed_val + 307
	_forest_noise.noise_type     = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest_noise.frequency      = 0.0035
	_forest_noise.fractal_octaves = 2

	# Medium-scale density — punches clearings and thickens dense cores.
	_density_noise.seed           = seed_val + 503
	_density_noise.noise_type     = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_density_noise.frequency      = 0.010
	_density_noise.fractal_octaves = 3

	var placed := PackedVector2Array()
	for def: Dictionary in TYPES:
		_place_type(def, rng, biome_noise, height_fn, valid_fn, ox, oz, tw, td, h_amp, placed)
	_flush_grass_multimesh()

# ─── Placement engine ─────────────────────────────────────────────────────────

func _place_type(
		def:         Dictionary,
		rng:         RandomNumberGenerator,
		biome_noise: FastNoiseLite,
		height_fn:   Callable,
		valid_fn:    Callable,
		ox: float, oz: float, tw: float, td: float,
		h_amp: float,
		placed: PackedVector2Array) -> void:

	var target: int  = def["count"]
	var min_d: float = def["min_dist"]
	var h_lo: float  = def["h_min"]
	var h_hi: float  = def["h_max"]
	var w_bog: float = def["w_bog"]
	var w_for: float = def["w_forest"]
	var w_roc: float = def["w_rocky"]

	var spawned := 0
	var tries   := 0

	while spawned < target and tries < target * 30:
		tries += 1
		var wx := rng.randf_range(ox + 8.0, ox + tw - 8.0)
		var wz := rng.randf_range(oz - td + 8.0, oz - 8.0)

		# Height band filter
		var h      := height_fn.call(wx, wz) as float
		var h_norm := h / h_amp
		if h_norm < h_lo or h_norm > h_hi:
			continue

		# Terrain biome weight (bog / forest / rocky)
		var biome  := (biome_noise.get_noise_2d(wx, wz) + 1.0) * 0.5
		var biome_w: float
		if biome < 0.42:
			biome_w = lerpf(w_bog, w_for, biome / 0.42)
		else:
			biome_w = lerpf(w_for, w_roc, (biome - 0.42) / 0.58)

		# Forest-zone weight — which species cluster dominates this patch
		var ft      := (_forest_noise.get_noise_2d(wx, wz) + 1.0) * 0.5
		var zone_w  := (def["zones"] as Array)[_zone_idx(ft)] as float

		# Density modulation — only applied to ground-cover types (grass, flowers, shrubs).
		# Trees skip this; their min_dist already handles spacing naturally.
		var final_w := biome_w * zone_w
		if def.get("density", false):
			var density := (_density_noise.get_noise_2d(wx, wz) + 1.0) * 0.5
			final_w *= lerpf(0.25, 1.0, density)   # clearings drop to 25 % of normal

		if rng.randf() > final_w:
			continue

		# Terrain-bounds, building, road, and spacing check
		if not (valid_fn.call(wx, wz, placed, min_d) as bool):
			continue

		var node := call(def["builder"], Vector3(wx, h, wz), def["p"], rng) as Node3D
		if node:
			add_child(node)
		# Always track position so spacing is respected even for batched types (grass).
		placed.append(Vector2(wx, wz))
		spawned += 1

# ─── Zone classification ──────────────────────────────────────────────────────

# Maps a 0..1 forest-noise value to one of 5 zone indices.
# Zones are defined by their noise thresholds; adjust to resize each zone.
func _zone_idx(ft: float) -> int:
	if ft < 0.22: return 0   # spruce forest   (22 % of land)
	if ft < 0.42: return 1   # conifer mix      (20 %)
	if ft < 0.62: return 2   # birch grove      (20 %)
	if ft < 0.78: return 3   # pine upland      (16 %)
	return 4                  # open / cleared   (22 %)

# ─── Builders ─────────────────────────────────────────────────────────────────
# Each follows the signature: (pos: Vector3, p: Dictionary, rng: RNG) -> Node3D

func _build_spruce(pos: Vector3, p: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rng.randf_range(0.0, TAU)
	var s := rng.randf_range(p["s_min"] as float, p["s_max"] as float)
	var mat_f := _mat(p["col_f"] as Color)
	var mat_t := _mat(p["col_t"] as Color)

	var tm := CylinderMesh.new()
	tm.top_radius = 0.08 * s;  tm.bottom_radius = 0.20 * s
	tm.height = 2.2 * s;       tm.radial_segments = 6
	var tmi := MeshInstance3D.new()
	tmi.mesh = tm;  tmi.position = Vector3(0, 1.1 * s, 0)
	tmi.set_surface_override_material(0, mat_t)
	root.add_child(tmi)

	# [bottom_radius, height, y_centre]
	for ld: Array in [[2.6, 2.2, 2.4], [2.0, 2.0, 3.8], [1.4, 1.8, 5.1], [0.8, 1.5, 6.1], [0.3, 1.1, 6.9]]:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0;  cm.bottom_radius = (ld[0] as float) * s
		cm.height = (ld[1] as float) * s;  cm.radial_segments = 7
		var cmi := MeshInstance3D.new()
		cmi.mesh = cm;  cmi.position = Vector3(0, (ld[2] as float) * s, 0)
		cmi.set_surface_override_material(0, mat_f)
		root.add_child(cmi)
	_add_harvest_trunk(root, 0.18 * s, 2.2 * s, 1.1 * s)
	_maybe_spawn_log(root, rng)
	return root


func _build_pine(pos: Vector3, p: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rng.randf_range(0.0, TAU)
	var s := rng.randf_range(p["s_min"] as float, p["s_max"] as float)
	var mat_f := _mat(p["col_f"] as Color)
	var mat_t := _mat(p["col_t"] as Color)

	# Taller, narrower trunk than spruce
	var tm := CylinderMesh.new()
	tm.top_radius = 0.06 * s;  tm.bottom_radius = 0.14 * s
	tm.height = 3.5 * s;       tm.radial_segments = 5
	var tmi := MeshInstance3D.new()
	tmi.mesh = tm;  tmi.position = Vector3(0, 1.75 * s, 0)
	tmi.set_surface_override_material(0, mat_t)
	root.add_child(tmi)

	# Fewer, more elongated cone layers
	for ld: Array in [[1.6, 2.8, 3.4], [1.0, 2.4, 5.4], [0.5, 2.0, 7.2], [0.2, 1.4, 8.6]]:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0;  cm.bottom_radius = (ld[0] as float) * s
		cm.height = (ld[1] as float) * s;  cm.radial_segments = 6
		var cmi := MeshInstance3D.new()
		cmi.mesh = cm;  cmi.position = Vector3(0, (ld[2] as float) * s, 0)
		cmi.set_surface_override_material(0, mat_f)
		root.add_child(cmi)
	_add_harvest_trunk(root, 0.12 * s, 3.5 * s, 1.75 * s)
	_maybe_spawn_log(root, rng)
	return root


func _build_birch(pos: Vector3, p: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rng.randf_range(0.0, TAU)
	var s := rng.randf_range(p["s_min"] as float, p["s_max"] as float)

	# Slim pale trunk
	var tm := CylinderMesh.new()
	tm.top_radius = 0.07 * s;  tm.bottom_radius = 0.13 * s
	tm.height = 5.5 * s;       tm.radial_segments = 7
	var tmi := MeshInstance3D.new()
	tmi.mesh = tm;  tmi.position = Vector3(0, 2.75 * s, 0)
	tmi.set_surface_override_material(0, _mat(p["col_t"] as Color))
	root.add_child(tmi)

	# Loose overlapping sphere canopy
	for _i in rng.randi_range(3, 5):
		var sr  := rng.randf_range(1.0, 1.8) * s
		var sm  := SphereMesh.new()
		sm.radius = sr;  sm.height = sr * 2.0
		sm.radial_segments = 8;  sm.rings = 4
		var smi := MeshInstance3D.new()
		smi.mesh = sm
		smi.position = Vector3(
			rng.randf_range(-0.5, 0.5) * s,
			(5.5 + rng.randf_range(-0.5, 0.8)) * s,
			rng.randf_range(-0.5, 0.5) * s)
		smi.set_surface_override_material(0, _mat(p["col_c"] as Color))
		root.add_child(smi)
	_add_harvest_trunk(root, 0.12 * s, 5.5 * s, 2.75 * s)
	_maybe_spawn_log(root, rng)
	return root


func _build_dead_tree(pos: Vector3, p: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rng.randf_range(0.0, TAU)
	var s   := rng.randf_range(p["s_min"] as float, p["s_max"] as float)
	var mat := _mat(p["col_t"] as Color)

	var tm := CylinderMesh.new()
	tm.top_radius = 0.05 * s;  tm.bottom_radius = 0.18 * s
	tm.height = 4.5 * s;       tm.radial_segments = 6
	var tmi := MeshInstance3D.new()
	tmi.mesh = tm;  tmi.position = Vector3(0, 2.25 * s, 0)
	tmi.set_surface_override_material(0, mat)
	root.add_child(tmi)

	# Angled branch stubs radiating from upper trunk
	for _i in rng.randi_range(2, 4):
		var bm := CylinderMesh.new()
		bm.top_radius = 0.02;  bm.bottom_radius = 0.055
		bm.height = rng.randf_range(0.8, 1.8) * s
		bm.radial_segments = 4
		var bmi := MeshInstance3D.new()
		bmi.mesh = bm
		bmi.position = Vector3(0, rng.randf_range(2.0, 4.0) * s, 0)
		bmi.rotation = Vector3(rng.randf_range(0.6, 1.1), rng.randf_range(0.0, TAU), 0.0)
		bmi.set_surface_override_material(0, mat)
		root.add_child(bmi)
	return root


func _build_bush(pos: Vector3, p: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rng.randf_range(0.0, TAU)
	var s    := rng.randf_range(p["s_min"] as float, p["s_max"] as float)
	var cols := p["cols"] as Array

	for _i in rng.randi_range(2, 5):
		var col := cols[rng.randi() % cols.size()] as Color
		var r   := rng.randf_range(0.35, 0.70) * s
		var sm  := SphereMesh.new()
		sm.radius = r;  sm.height = r * 1.6
		sm.radial_segments = 7;  sm.rings = 4
		var smi := MeshInstance3D.new()
		smi.mesh = sm
		smi.position = Vector3(
			rng.randf_range(-0.4, 0.4) * s, r * 0.9,
			rng.randf_range(-0.4, 0.4) * s)
		smi.set_surface_override_material(0, _mat(col))
		root.add_child(smi)
	return root


func _build_stump(pos: Vector3, p: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var s  := rng.randf_range(p["s_min"] as float, p["s_max"] as float)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.20 * s;  cm.bottom_radius = 0.26 * s
	cm.height = 0.45 * s;      cm.radial_segments = 7
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.position   = pos + Vector3(0, 0.225 * s, 0)
	mi.rotation.y = rng.randf_range(0.0, TAU)
	mi.set_surface_override_material(0, _mat(p["col_t"] as Color))
	return mi


func _build_boulder(pos: Vector3, p: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rng.randf_range(0.0, TAU)
	var col  := p["col"] as Color
	var smin := p["s_min"] as float
	var smax := p["s_max"] as float
	var mat  := _mat(col)

	for k in rng.randi_range(1, p["cluster"] as int):
		var sx := rng.randf_range(smin, smax)
		var sy := sx * rng.randf_range(0.28, 0.52)
		var sz := rng.randf_range(smin, smax)
		var sm := SphereMesh.new()
		sm.radius = 0.5;  sm.height = 1.0
		sm.radial_segments = 7;  sm.rings = 4
		var mi := MeshInstance3D.new()
		mi.mesh  = sm
		mi.scale = Vector3(sx, sy, sz)
		mi.position = Vector3(
			rng.randf_range(-0.5, 0.5) * float(k), sy * 0.5,
			rng.randf_range(-0.5, 0.5) * float(k))
		mi.rotation.y = rng.randf_range(0.0, TAU)
		mi.set_surface_override_material(0, mat)
		root.add_child(mi)
	return root


func _build_grass(pos: Vector3, p: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	# Grass is batched — append data now, build the MultiMesh in _flush_grass_multimesh().
	var cols := p["cols"] as Array
	_pending_grass.append({
		"pos": pos,
		"col": cols[rng.randi() % cols.size()] as Color,
		"s":   rng.randf_range(0.6, 1.3),
		"rot": rng.randf_range(0.0, TAU),
	})
	return null   # placement engine still tracks position via the always-append logic

func _make_grass_tuft_mesh() -> ArrayMesh:
	# One shared template tuft: 6 blades at 60° intervals with varied spread/height/lean.
	# Per-instance transform (rotation + scale) ensures no two tufts look identical.
	var blades := [
		# [facing_angle,      spread,  height, half_width, lean_fwd]
		[0.0,                 0.00,    0.55,   0.055,  0.06],
		[PI / 3.0,            0.20,    0.62,   0.050,  0.08],
		[PI * 2.0 / 3.0,      0.24,    0.48,   0.045, -0.07],
		[PI,                  0.18,    0.58,   0.055,  0.05],
		[PI * 4.0 / 3.0,      0.22,    0.42,   0.040, -0.06],
		[PI * 5.0 / 3.0,      0.15,    0.65,   0.050,  0.09],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bd: Array in blades:
		var ang:  float = bd[0]
		var spr:  float = bd[1]
		var bh:   float = bd[2]
		var hw:   float = bd[3]
		var lean: float = bd[4]
		var fwd   := Vector3(cos(ang), 0.0, sin(ang))
		var right := Vector3(-sin(ang), 0.0, cos(ang))
		var base  := fwd * spr
		var v0    := base - right * hw
		var v1    := base + right * hw
		var v2    := base + fwd * lean + Vector3(0, bh, 0) + right * hw * 0.2
		var v3    := base + fwd * lean + Vector3(0, bh, 0) - right * hw * 0.2
		var nrm   := (v1 - v0).cross(v3 - v0).normalized()
		st.set_normal(nrm)
		st.add_vertex(v0); st.add_vertex(v1); st.add_vertex(v3)
		st.add_vertex(v1); st.add_vertex(v2); st.add_vertex(v3)
		st.set_normal(-nrm)
		st.add_vertex(v3); st.add_vertex(v1); st.add_vertex(v0)
		st.add_vertex(v3); st.add_vertex(v2); st.add_vertex(v1)
	return st.commit()

func _flush_grass_multimesh() -> void:
	if _pending_grass.is_empty():
		return

	var blade_mesh := _make_grass_tuft_mesh()

	var mat := StandardMaterial3D.new()
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Per-instance color from MultiMesh multiplies albedo — both flags required.
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	blade_mesh.surface_set_material(0, mat)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors       = true
	mm.instance_count   = _pending_grass.size()
	mm.mesh             = blade_mesh

	for i in _pending_grass.size():
		var g:   Dictionary = _pending_grass[i]
		var s:   float      = g["s"]
		var basis := Basis.from_euler(Vector3(0.0, g["rot"] as float, 0.0)).scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(basis, g["pos"] as Vector3))
		mm.set_instance_color(i, g["col"] as Color)

	var mmi       := MultiMeshInstance3D.new()
	mmi.name      = "GrassMultiMesh"
	mmi.multimesh = mm
	add_child(mmi)
	_pending_grass.clear()


func _build_flower(pos: Vector3, p: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rng.randf_range(0.0, TAU)
	var cols := p["cols"] as Array
	var col  := cols[rng.randi() % cols.size()] as Color
	var s    := rng.randf_range(p["s_min"] as float, p["s_max"] as float)

	# Stem
	var sm := CylinderMesh.new()
	sm.top_radius = 0.010;  sm.bottom_radius = 0.014
	sm.height = s;           sm.radial_segments = 4
	var smi := MeshInstance3D.new()
	smi.mesh = sm;  smi.position = Vector3(0, s * 0.5, 0)
	smi.set_surface_override_material(0, _mat(Color(0.12, 0.20, 0.07)))
	root.add_child(smi)

	# Flower head — slightly flattened sphere
	var hr := s * 0.32
	var hm := SphereMesh.new()
	hm.radius = hr;  hm.height = hr * 0.85
	hm.radial_segments = 8;  hm.rings = 4
	var hmi := MeshInstance3D.new()
	hmi.mesh = hm;  hmi.position = Vector3(0, s + hr * 0.35, 0)
	hmi.set_surface_override_material(0, _mat(col))
	root.add_child(hmi)
	return root

# ─── Harvestable trunk ────────────────────────────────────────────────────────

func _add_harvest_trunk(root: Node3D, radius: float, height: float, cy: float) -> void:
	var body  := StaticBody3D.new()
	body.set_script(HarvestableTree)
	var col   := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius    = radius
	shape.height    = height
	col.shape       = shape
	col.position    = Vector3(0.0, cy, 0.0)
	body.add_child(col)
	root.add_child(body)

# ─── Log litter ──────────────────────────────────────────────────────────────

func _maybe_spawn_log(root: Node3D, rng: RandomNumberGenerator) -> void:
	if rng.randf() >= LOG_SPAWN_CHANCE:
		return
	var log := ITEM_SCENE.instantiate() as PhysicalItem
	log.item_data = ItemRegistry.get_item("wood_log")
	log.net_id    = get_tree().get_first_node_in_group("world").assign_world_gen_id()
	log.position   = Vector3(rng.randf_range(-1.2, 1.2), 0.4, rng.randf_range(-1.2, 1.2))
	log.rotation.y = rng.randf_range(0.0, TAU)
	root.add_child(log)

# ─── Material helpers ─────────────────────────────────────────────────────────

func _mat(col: Color) -> StandardMaterial3D:
	var key := col.to_html(false)
	if not _mat_cache.has(key):
		var m          := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness    = 0.92
		m.metallic     = 0.0
		_mat_cache[key] = m
	return _mat_cache[key]

func _dbl_mat(col: Color) -> StandardMaterial3D:
	var key := col.to_html(false)
	if not _dbl_mat_cache.has(key):
		var m          := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness    = 0.95
		m.cull_mode    = BaseMaterial3D.CULL_DISABLED
		_dbl_mat_cache[key] = m
	return _dbl_mat_cache[key]
