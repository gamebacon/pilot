extends Node3D

# ── Terrain ───────────────────────────────────────────────────────────────────
const T_ORIGIN_X := -160.0
const T_ORIGIN_Z :=   60.0
const T_WIDTH    := 320.0
const T_DEPTH    := 330.0
const GRID_W     := 128
const GRID_D     := 132
const VERT_W     := GRID_W + 1
const VERT_D     := GRID_D + 1
const CELL_W     := T_WIDTH / GRID_W   # 2.5 m
const CELL_D     := T_DEPTH / GRID_D   # 2.5 m
const HEIGHT_AMP := 7.5

# ── Buildings (XZ) — randomised per seed ─────────────────────────────────────
# Home stays close to spawn; HardwareStore mid-map; Factory far south.
const BLDG_FLAT_R := {
	"Home": 12.0, "HardwareStore": 15.0, "Factory": 24.0, "GroceryStore": 12.0,
}
var _bldg_xz: Dictionary = {}  # filled in _randomise_layout()

# ── Roads ─────────────────────────────────────────────────────────────────────
const ROAD_HALF_W := 4.0
const ROAD_BLEND  := 5.0
const SEG_SAMPLES := 140
var _road_segs: Array = []  # derived from building positions

# ── State ─────────────────────────────────────────────────────────────────────
var _rng   := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _heights: PackedFloat32Array          # [i + j*VERT_W], j=0 → z=T_ORIGIN_Z
var _all_road_pts := PackedVector2Array() # flattened for fast iteration
var _road_segs_pts: Array = []            # per-segment, used for road mesh

var _mat_snow:  StandardMaterial3D
var _mat_road:  StandardMaterial3D
var _mat_pine:  StandardMaterial3D
var _mat_trunk: StandardMaterial3D
var _mat_stump: StandardMaterial3D
var _mat_rock:  StandardMaterial3D

# ── Entry ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	randomize()
	var seed_val := randi()
	_rng.seed   = seed_val
	_noise.seed = seed_val
	_noise.noise_type             = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency              = 0.0038
	_noise.fractal_octaves        = 5
	_noise.fractal_lacunarity     = 2.1
	_noise.fractal_gain           = 0.45
	_noise.domain_warp_enabled    = true
	_noise.domain_warp_amplitude  = 28.0
	_noise.domain_warp_frequency  = 0.003

	_init_mats()
	_setup_environment()
	_randomise_layout()
	_sample_road_pts()
	_build_heightmap()
	_build_terrain()
	_place_buildings()
	_build_roads()
	_spawn_resources()

# ── Environment / sky ─────────────────────────────────────────────────────────
func _setup_environment() -> void:
	var we  := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if not we:
		return

	var sky_mat := PhysicalSkyMaterial.new()
	sky_mat.rayleigh_coefficient = 2.0
	sky_mat.rayleigh_color       = Color(0.24, 0.39, 0.58)
	sky_mat.mie_coefficient      = 0.004
	sky_mat.mie_eccentricity     = 0.82
	sky_mat.mie_color            = Color(0.72, 0.77, 0.84)
	sky_mat.turbidity            = 4.0
	sky_mat.sun_disk_scale       = 8.0
	sky_mat.ground_color         = Color(0.78, 0.80, 0.84)
	sky_mat.energy_multiplier    = 1.0

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := we.environment
	env.background_mode      = Environment.BG_SKY
	env.sky                  = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.glow_enabled         = false
	env.fog_enabled          = false
	env.tonemap_mode         = Environment.TONE_MAPPER_LINEAR

	if sun:
		sun.light_color    = Color(0.98, 0.93, 0.82)
		sun.light_energy   = 1.4
		sun.shadow_enabled = true
		sun.sky_mode       = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY

# ── Materials ─────────────────────────────────────────────────────────────────
func _init_mats() -> void:
	_mat_snow  = _mkmat(Color(0.82, 0.84, 0.87))
	_mat_road  = _mkmat(Color(0.18, 0.18, 0.20))
	_mat_pine  = _mkmat(Color(0.16, 0.26, 0.18))
	_mat_trunk = _mkmat(Color(0.22, 0.16, 0.10))
	_mat_stump = _mkmat(Color(0.28, 0.20, 0.13))
	_mat_rock  = _mkmat(Color(0.44, 0.42, 0.40))

static func _mkmat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m

# ── Layout randomisation ──────────────────────────────────────────────────────
func _randomise_layout() -> void:
	# XZ zones keep the narrative order: Home near spawn, Store mid, Factory far.
	_bldg_xz["Home"]          = Vector2(_rng.randf_range(-18,  18), _rng.randf_range(-6,  -22))
	_bldg_xz["GroceryStore"]  = Vector2(_rng.randf_range(-35, -12), _rng.randf_range(-38, -55))
	_bldg_xz["HardwareStore"] = Vector2(_rng.randf_range(-28,  28), _rng.randf_range(-65, -105))
	_bldg_xz["Factory"]       = Vector2(_rng.randf_range(-18,  18), _rng.randf_range(-150, -195))

	var home:    Vector2 = _bldg_xz["Home"]
	var grocery: Vector2 = _bldg_xz["GroceryStore"]
	var store:   Vector2 = _bldg_xz["HardwareStore"]
	var factory: Vector2 = _bldg_xz["Factory"]
	var spawn   := Vector2(0.0, 5.0)

	# Main spine: spawn → store → factory, with random lateral bows.
	# Branch roads lead to Home and GroceryStore off the spine.
	_road_segs = [
		_curved_seg(spawn,   store,   _rng.randf_range(-20, 20), _rng.randf_range(-20, 20)),
		_curved_seg(store,   factory, _rng.randf_range(-20, 20), _rng.randf_range(-20, 20)),
		_curved_seg(spawn,   home,    _rng.randf_range(-8,   8), _rng.randf_range(-8,   8)),
		_curved_seg(spawn,   grocery, _rng.randf_range(-10, 10), _rng.randf_range(-10, 10)),
	]

# Build a cubic bezier segment between a and b with two random lateral offsets.
func _curved_seg(a: Vector2, b: Vector2, bow1: float, bow2: float) -> Array:
	var perp := (b - a).normalized().rotated(PI * 0.5)
	return [
		a,
		a + (b - a) * 0.33 + perp * bow1,
		a + (b - a) * 0.66 + perp * bow2,
		b,
	]

# ── Road sampling ─────────────────────────────────────────────────────────────
func _sample_road_pts() -> void:
	for seg in _road_segs:
		var pts := PackedVector2Array()
		pts.resize(SEG_SAMPLES + 1)
		for k in SEG_SAMPLES + 1:
			var t := float(k) / SEG_SAMPLES
			pts[k] = _bez4(seg[0], seg[1], seg[2], seg[3], t)
		_road_segs_pts.append(pts)
		for pt in pts:
			_all_road_pts.append(pt)

static func _bez4(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u*u*u*p0 + 3.0*u*u*t*p1 + 3.0*u*t*t*p2 + t*t*t*p3

# ── Heightmap ─────────────────────────────────────────────────────────────────
func _build_heightmap() -> void:
	_heights = PackedFloat32Array()
	_heights.resize(VERT_W * VERT_D)

	var road_hw_sq    := ROAD_HALF_W * ROAD_HALF_W
	var road_blend_sq := (ROAD_HALF_W + ROAD_BLEND) * (ROAD_HALF_W + ROAD_BLEND)

	for j in VERT_D:
		for i in VERT_W:
			var wx := T_ORIGIN_X + i * CELL_W
			var wz := T_ORIGIN_Z - j * CELL_D
			var h  := (_noise.get_noise_2d(wx, wz) + 1.0) * 0.5 * HEIGHT_AMP

			# Flatten building zones
			var pos2 := Vector2(wx, wz)
			for key: String in _bldg_xz:
				var bpos: Vector2 = _bldg_xz[key]
				var r: float = BLDG_FLAT_R[key]
				var d := pos2.distance_to(bpos)
				if d < r:
					h = 0.0
				elif d < r + 4.0:
					h *= (d - r) / 4.0

			# Flatten road corridors (squared distance for speed)
			var min_rd_sq := INF
			for pt: Vector2 in _all_road_pts:
				var dx := wx - pt.x
				var dz := wz - pt.y
				var dsq := dx * dx + dz * dz
				if dsq < min_rd_sq:
					min_rd_sq = dsq
				if min_rd_sq <= road_hw_sq:
					break

			if min_rd_sq <= road_hw_sq:
				h = 0.0
			elif min_rd_sq <= road_blend_sq:
				h *= (sqrt(min_rd_sq) - ROAD_HALF_W) / ROAD_BLEND

			_heights[i + j * VERT_W] = h

# ── Terrain mesh + collision ──────────────────────────────────────────────────
func _build_terrain() -> void:
	# Visual mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for j in VERT_D:
		for i in VERT_W:
			st.set_uv(Vector2(float(i) / GRID_W * 24.0, float(j) / GRID_D * 24.0))
			st.add_vertex(Vector3(
				T_ORIGIN_X + i * CELL_W,
				_heights[i + j * VERT_W],
				T_ORIGIN_Z - j * CELL_D
			))

	for j in GRID_D:
		for i in GRID_W:
			var v00 := i +       j * VERT_W
			var v10 := (i + 1) + j * VERT_W
			var v01 := i +       (j + 1) * VERT_W
			var v11 := (i + 1) + (j + 1) * VERT_W
			st.add_index(v00); st.add_index(v01); st.add_index(v10)
			st.add_index(v10); st.add_index(v01); st.add_index(v11)

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = st.commit()
	mi.set_surface_override_material(0, _mat_snow)
	add_child(mi)

	# Collision — HeightMapShape3D. Shape j=0 → world Z negative, so flip Z index.
	var shape_data := PackedFloat32Array()
	shape_data.resize(VERT_W * VERT_D)
	for j in VERT_D:
		for i in VERT_W:
			shape_data[i + j * VERT_W] = _heights[i + (GRID_D - j) * VERT_W]

	var hm := HeightMapShape3D.new()
	hm.map_width = VERT_W
	hm.map_depth = VERT_D
	hm.map_data  = shape_data

	var cs   := CollisionShape3D.new()
	cs.shape  = hm
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.add_child(cs)
	body.position = Vector3(T_ORIGIN_X + T_WIDTH * 0.5, 0.0, T_ORIGIN_Z - T_DEPTH * 0.5)
	body.scale    = Vector3(CELL_W, 1.0, CELL_D)
	add_child(body)

# ── Sample height at any world XZ ─────────────────────────────────────────────
func _sample_height(wx: float, wz: float) -> float:
	var fi := (wx - T_ORIGIN_X) / CELL_W
	var fj := (T_ORIGIN_Z - wz) / CELL_D
	var i0 := clampi(int(fi), 0, GRID_W - 1)
	var j0 := clampi(int(fj), 0, GRID_D - 1)
	var i1 := mini(i0 + 1, GRID_W)
	var j1 := mini(j0 + 1, GRID_D)
	var tx  := fi - i0
	var tz  := fj - j0
	var h00 := _heights[i0 + j0 * VERT_W]
	var h10 := _heights[i1 + j0 * VERT_W]
	var h01 := _heights[i0 + j1 * VERT_W]
	var h11 := _heights[i1 + j1 * VERT_W]
	return lerp(lerp(h00, h10, tx), lerp(h01, h11, tx), tz)

# ── Place buildings at terrain height ─────────────────────────────────────────
func _place_buildings() -> void:
	for bname: String in _bldg_xz:
		var bxz: Vector2 = _bldg_xz[bname]
		var h := _sample_height(bxz.x, bxz.y)
		var node := get_parent().get_node_or_null(bname)
		if node:
			node.position = Vector3(bxz.x, h, bxz.y)
		else:
			push_warning("WorldGenerator: node '%s' not found — check name matches world.tscn" % bname)

# ── Road meshes ───────────────────────────────────────────────────────────────
func _build_roads() -> void:
	var root := Node3D.new()
	root.name = "Roads"
	add_child(root)
	for seg_pts: PackedVector2Array in _road_segs_pts:
		_build_road_strip(root, seg_pts)

func _build_road_strip(parent: Node3D, pts: PackedVector2Array) -> void:
	var n := pts.size()
	var lverts := PackedVector3Array()
	var rverts := PackedVector3Array()
	lverts.resize(n)
	rverts.resize(n)

	for k in n:
		var ctr := pts[k]
		var tang: Vector2
		if k < n - 1:
			tang = (pts[k + 1] - ctr).normalized()
		else:
			tang = (ctr - pts[k - 1]).normalized()
		var perp := Vector2(-tang.y, tang.x)
		var lx := ctr.x + perp.x * ROAD_HALF_W
		var lz := ctr.y + perp.y * ROAD_HALF_W
		var rx := ctr.x - perp.x * ROAD_HALF_W
		var rz := ctr.y - perp.y * ROAD_HALF_W
		lverts[k] = Vector3(lx, _sample_height(lx, lz) + 0.08, lz)
		rverts[k] = Vector3(rx, _sample_height(rx, rz) + 0.08, rz)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in n - 1:
		var l0 := lverts[k];     var r0 := rverts[k]
		var l1 := lverts[k + 1]; var r1 := rverts[k + 1]
		st.add_vertex(l0); st.add_vertex(r0); st.add_vertex(l1)
		st.add_vertex(l1); st.add_vertex(r0); st.add_vertex(r1)
	st.generate_normals()

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.set_surface_override_material(0, _mat_road)
	parent.add_child(mi)

# ── Resource spawning ─────────────────────────────────────────────────────────
func _spawn_resources() -> void:
	var root := Node3D.new()
	root.name = "Resources"
	add_child(root)
	var placed := PackedVector2Array()
	_spawn_trees(root, placed, 110)
	_spawn_stumps(root, placed, 38)
	_spawn_rocks(root, placed, 60)

func _valid_pos(wx: float, wz: float, placed: PackedVector2Array, min_dist: float) -> bool:
	var pos2 := Vector2(wx, wz)
	# Stay inside terrain with margin
	if wx < T_ORIGIN_X + 8 or wx > T_ORIGIN_X + T_WIDTH - 8:
		return false
	if wz > T_ORIGIN_Z - 8 or wz < T_ORIGIN_Z - T_DEPTH + 8:
		return false
	# Building exclusion
	for key: String in _bldg_xz:
		var bpos: Vector2 = _bldg_xz[key]
		var r: float = BLDG_FLAT_R[key]
		if pos2.distance_to(bpos) < r + 6.0:
			return false
	# Road exclusion
	for pt: Vector2 in _all_road_pts:
		var dx := wx - pt.x; var dz := wz - pt.y
		if dx * dx + dz * dz < (ROAD_HALF_W + 3.0) * (ROAD_HALF_W + 3.0):
			return false
	# Spacing from existing objects
	var md_sq := min_dist * min_dist
	for p: Vector2 in placed:
		var dx := wx - p.x; var dz := wz - p.y
		if dx * dx + dz * dz < md_sq:
			return false
	return true

func _spawn_trees(parent: Node3D, placed: PackedVector2Array, count: int) -> void:
	var attempts := 0
	var spawned  := 0
	while spawned < count and attempts < count * 25:
		attempts += 1
		var wx := _rng.randf_range(T_ORIGIN_X + 8, T_ORIGIN_X + T_WIDTH - 8)
		var wz := _rng.randf_range(T_ORIGIN_Z - T_DEPTH + 8, T_ORIGIN_Z - 8)
		if not _valid_pos(wx, wz, placed, 5.5):
			continue
		var wy := _sample_height(wx, wz)
		_make_tree(parent, Vector3(wx, wy, wz))
		placed.append(Vector2(wx, wz))
		spawned += 1

func _spawn_stumps(parent: Node3D, placed: PackedVector2Array, count: int) -> void:
	var attempts := 0
	var spawned  := 0
	while spawned < count and attempts < count * 25:
		attempts += 1
		var wx := _rng.randf_range(T_ORIGIN_X + 8, T_ORIGIN_X + T_WIDTH - 8)
		var wz := _rng.randf_range(T_ORIGIN_Z - T_DEPTH + 8, T_ORIGIN_Z - 8)
		if not _valid_pos(wx, wz, placed, 2.5):
			continue
		var wy := _sample_height(wx, wz)
		_make_stump(parent, Vector3(wx, wy, wz))
		placed.append(Vector2(wx, wz))
		spawned += 1

func _spawn_rocks(parent: Node3D, placed: PackedVector2Array, count: int) -> void:
	var attempts := 0
	var spawned  := 0
	while spawned < count and attempts < count * 25:
		attempts += 1
		var wx := _rng.randf_range(T_ORIGIN_X + 8, T_ORIGIN_X + T_WIDTH - 8)
		var wz := _rng.randf_range(T_ORIGIN_Z - T_DEPTH + 8, T_ORIGIN_Z - 8)
		if not _valid_pos(wx, wz, placed, 2.0):
			continue
		var wy := _sample_height(wx, wz)
		_make_rock(parent, Vector3(wx, wy, wz))
		placed.append(Vector2(wx, wz))
		spawned += 1

# ── Object builders ───────────────────────────────────────────────────────────
func _make_tree(parent: Node3D, pos: Vector3) -> void:
	var tree := Node3D.new()
	tree.position     = pos
	tree.rotation.y   = _rng.randf_range(0.0, TAU)
	var s := _rng.randf_range(0.75, 1.35)

	var trunk_mi := MeshInstance3D.new()
	var trunk_m  := BoxMesh.new()
	trunk_m.size   = Vector3(0.4, 2.2, 0.4) * s
	trunk_mi.mesh  = trunk_m
	trunk_mi.position = Vector3(0, 1.1 * s, 0)
	trunk_mi.set_surface_override_material(0, _mat_trunk)
	tree.add_child(trunk_mi)

	var low_mi := MeshInstance3D.new()
	var low_m  := BoxMesh.new()
	low_m.size    = Vector3(2.8, 2.2, 2.8) * s
	low_mi.mesh   = low_m
	low_mi.position = Vector3(0, 2.8 * s, 0)
	low_mi.set_surface_override_material(0, _mat_pine)
	tree.add_child(low_mi)

	var top_mi := MeshInstance3D.new()
	var top_m  := BoxMesh.new()
	top_m.size    = Vector3(1.8, 2.0, 1.8) * s
	top_mi.mesh   = top_m
	top_mi.position = Vector3(0, 4.5 * s, 0)
	top_mi.set_surface_override_material(0, _mat_pine)
	tree.add_child(top_mi)

	parent.add_child(tree)

func _make_stump(parent: Node3D, pos: Vector3) -> void:
	var s := _rng.randf_range(0.5, 1.1)
	var mi := MeshInstance3D.new()
	var m  := BoxMesh.new()
	m.size = Vector3(0.55, 0.45, 0.55) * s
	mi.mesh = m
	mi.position   = pos + Vector3(0, 0.225 * s, 0)
	mi.rotation.y = _rng.randf_range(0.0, TAU)
	mi.set_surface_override_material(0, _mat_stump)
	parent.add_child(mi)

func _make_rock(parent: Node3D, pos: Vector3) -> void:
	var sx := _rng.randf_range(0.4, 1.5)
	var sy := _rng.randf_range(0.3, 0.9)
	var sz := _rng.randf_range(0.4, 1.3)
	var mi := MeshInstance3D.new()
	var m  := BoxMesh.new()
	m.size = Vector3(sx, sy, sz)
	mi.mesh = m
	mi.position = pos + Vector3(0, sy * 0.5, 0)
	mi.rotation = Vector3(
		_rng.randf_range(-0.25, 0.25),
		_rng.randf_range(0.0, TAU),
		_rng.randf_range(-0.25, 0.25)
	)
	mi.set_surface_override_material(0, _mat_rock)
	parent.add_child(mi)
