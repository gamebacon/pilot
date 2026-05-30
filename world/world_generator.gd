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
const HEIGHT_AMP := 13.0

# ── State ─────────────────────────────────────────────────────────────────────
var _rng        := RandomNumberGenerator.new()
var _noise      := FastNoiseLite.new()
var _heights:   PackedFloat32Array        # [i + j*VERT_W], j=0 → z=T_ORIGIN_Z
# Explicit ore counter — Godot auto-names diverge between server/client.
# Driven by the same seeded order on all peers so names are deterministic.
var _ore_counter: int = 0

const FoliageSystem          = preload("res://world/foliage_system.gd")
const DayNightCycle          = preload("res://world/day_night_cycle.gd")
const CoreScript             = preload("res://world/core.gd")
const WaveSpawnerScript      = preload("res://world/wave_spawner.gd")
const ITEM_SCENE             = preload("res://items/physical_item.tscn")
const HarvestableDepositScript = preload("res://world/harvestable_rock.gd")

## Set by _spawn_core() so world.gd can read it for player spawn positioning.
var core_position := Vector3.ZERO

var _mat_snow:  StandardMaterial3D
var _biome_noise  := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()  # high-freq for terrain micro-variation

# ── Entry ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("world_generator")

# Called by world.gd so the seed is always controlled externally.
func generate(seed_val: int) -> void:
	_rng.seed   = seed_val
	_noise.seed = seed_val
	_noise.noise_type             = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency              = 0.0038
	_noise.fractal_octaves        = 5
	_noise.fractal_lacunarity     = 2.1
	_noise.fractal_gain           = 0.50
	_noise.domain_warp_enabled    = true
	_noise.domain_warp_amplitude  = 42.0
	_noise.domain_warp_frequency  = 0.003

	_biome_noise.seed            = seed_val + 99
	_biome_noise.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_biome_noise.frequency       = 0.006
	_biome_noise.fractal_octaves = 3
	_biome_noise.fractal_gain    = 0.5

	# Detail noise — small splotchy variation to break up solid terrain colour.
	_detail_noise.seed            = seed_val + 557
	_detail_noise.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.frequency       = 0.075
	_detail_noise.fractal_octaves = 2

	_init_mats()
	_setup_environment()
	_build_heightmap()
	_build_terrain()
	_spawn_foliage()
	_spawn_day_night_cycle()
	_spawn_core()
	_spawn_ore_deposits()
	_setup_navigation()

# ── Environment / sky ─────────────────────────────────────────────────────────
func _setup_environment() -> void:
	var we  := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if not we:
		return

	# Physical sky — DayNightCycle will animate its properties each frame.
	var sky_mat := PhysicalSkyMaterial.new()
	sky_mat.rayleigh_coefficient = 2.0
	sky_mat.rayleigh_color       = Color(0.20, 0.36, 0.56)
	sky_mat.mie_coefficient      = 0.004
	sky_mat.mie_eccentricity     = 0.82
	sky_mat.mie_color            = Color(0.72, 0.77, 0.84)
	sky_mat.turbidity            = 3.0
	sky_mat.sun_disk_scale       = 8.0
	sky_mat.ground_color         = Color(0.42, 0.46, 0.40)
	sky_mat.energy_multiplier    = 1.0

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := we.environment
	if not env:
		env = Environment.new()
		we.environment = env

	env.background_mode = Environment.BG_SKY
	env.sky             = sky

	# Ambient — manual colour so DayNightCycle drives it directly.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(0.62, 0.70, 0.88)
	env.ambient_light_energy = 0.45

	# Filmic tonemapper — richer darks and highlights vs flat LINEAR.
	env.tonemap_mode     = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white    = 1.0

	# Screen-space ambient occlusion — grounds foliage and terrain, adds depth.
	env.ssao_enabled   = true
	env.ssao_radius    = 0.90
	env.ssao_intensity = 1.6
	env.ssao_power     = 1.5
	env.ssao_detail    = 0.5

	# Subtle bloom — sun disc halos at horizon, bright surfaces breathe.
	env.glow_enabled   = true
	env.glow_intensity = 0.32
	env.glow_bloom     = 0.18
	env.glow_strength  = 0.60

	# Depth fog — DayNightCycle animates colour + density each frame.
	env.fog_enabled             = true
	env.fog_density             = 0.0018
	env.fog_light_color         = Color(0.70, 0.80, 0.92)
	env.fog_aerial_perspective  = 0.40

	if sun:
		sun.light_color    = Color(0.97, 0.93, 0.84)
		sun.light_energy   = 1.52
		sun.shadow_enabled = true
		sun.sky_mode       = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY

# ── Materials ─────────────────────────────────────────────────────────────────
func _init_mats() -> void:
	_mat_snow  = StandardMaterial3D.new()
	_mat_snow.vertex_color_use_as_albedo = true
	_mat_snow.roughness = 0.92
	_mat_snow.metallic  = 0.0

func _terrain_color(wx: float, wz: float, h: float) -> Color:
	var h_norm := h / HEIGHT_AMP
	var biome  := (_biome_noise.get_noise_2d(wx, wz) + 1.0) * 0.5

	# Biome base colours — intentionally dark and desaturated for realism.
	const COL_BOG    := Color(0.048, 0.072, 0.030)  # near-black peaty bog
	const COL_FOREST := Color(0.068, 0.108, 0.042)  # dark damp forest floor
	const COL_ROCKY  := Color(0.145, 0.128, 0.088)  # dark slate / shale
	const COL_SNOW   := Color(0.56,  0.60,  0.58)   # grey-blue packed snow

	var base: Color
	if biome < 0.42:
		base = COL_BOG.lerp(COL_FOREST, biome / 0.42)
	else:
		base = COL_FOREST.lerp(COL_ROCKY, (biome - 0.42) / 0.58)

	# Snow cap on the upper 25 % of the height range.
	if h_norm > 0.72:
		base = base.lerp(COL_SNOW, (h_norm - 0.72) / 0.28)

	# Micro-variation: subtle splotchy darkening/lightening (±9 %) so the
	# terrain doesn't look like flat painted polygons up close.
	var detail := (_detail_noise.get_noise_2d(wx, wz) + 1.0) * 0.5
	var v      := lerpf(0.89, 1.06, detail)
	base = Color(base.r * v, base.g * v, base.b * v, 1.0)

	return base

# ── Heightmap ─────────────────────────────────────────────────────────────────
func _build_heightmap() -> void:
	_heights = PackedFloat32Array()
	_heights.resize(VERT_W * VERT_D)
	for j in VERT_D:
		for i in VERT_W:
			var wx := T_ORIGIN_X + i * CELL_W
			var wz := T_ORIGIN_Z - j * CELL_D
			_heights[i + j * VERT_W] = (_noise.get_noise_2d(wx, wz) + 1.0) * 0.5 * HEIGHT_AMP

# ── Terrain mesh + collision ──────────────────────────────────────────────────
func _build_terrain() -> void:
	# Visual mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for j in VERT_D:
		for i in VERT_W:
			var wx := T_ORIGIN_X + i * CELL_W
			var wz := T_ORIGIN_Z - j * CELL_D
			var h  := _heights[i + j * VERT_W]
			st.set_uv(Vector2(float(i) / GRID_W * 24.0, float(j) / GRID_D * 24.0))
			st.set_color(_terrain_color(wx, wz, h))
			st.add_vertex(Vector3(wx, h, wz))

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
	mi.add_to_group("nav_static")
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

# ── Day / night cycle ─────────────────────────────────────────────────────────
func _spawn_day_night_cycle() -> void:
	# Remove any stale instance (e.g. hot-reload).
	var old := get_parent().get_node_or_null("DayNightCycle")
	if old:
		old.queue_free()
	var dnc := DayNightCycle.new()
	dnc.name = "DayNightCycle"
	get_parent().add_child(dnc)

# ── Foliage ───────────────────────────────────────────────────────────────────
func _spawn_foliage() -> void:
	var fs := FoliageSystem.new()
	fs.name = "Foliage"
	add_child(fs)
	fs.populate(_rng, _biome_noise, _sample_height, _valid_pos,
		T_ORIGIN_X, T_ORIGIN_Z, T_WIDTH, T_DEPTH, HEIGHT_AMP, _rng.seed)

# ── Core + wave spawner ───────────────────────────────────────────────────────

func _spawn_core() -> void:
	# Pick a random flat-ish spot 15–35 m from origin.
	var angle := _rng.randf() * TAU
	var dist  := _rng.randf_range(15.0, 35.0)
	var cx    := cos(angle) * dist
	var cz    := sin(angle) * dist
	var cy    := _sample_height(cx, cz)

	core_position = Vector3(cx, cy, cz)

	# Visual: a glowing green pillar.
	var body := StaticBody3D.new()
	body.set_script(CoreScript)
	body.name = "Core"

	var col    := CollisionShape3D.new()
	var cshape := CylinderShape3D.new()
	cshape.radius = 0.8
	cshape.height = 3.0
	col.shape     = cshape
	body.add_child(col)

	var mi   := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius    = 0.8
	mesh.bottom_radius = 0.8
	mesh.height        = 3.0
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color      = Color(0.1, 0.9, 0.4)
	mat.emission_enabled  = true
	mat.emission          = Color(0.0, 0.6, 0.25)
	mi.set_surface_override_material(0, mat)
	body.add_child(mi)

	var light := OmniLight3D.new()
	light.light_color  = Color(0.3, 1.0, 0.55)
	light.light_energy = 3.0
	light.omni_range   = 28.0
	body.add_child(light)

	get_parent().add_child(body)
	body.global_position = core_position + Vector3(0.0, 1.5, 0.0)

	# Wave spawner — lives on the world root so it has correct multiplayer context.
	var ws := Node.new()
	ws.set_script(WaveSpawnerScript)
	ws.name = "WaveSpawner"
	get_parent().add_child(ws)
	ws.core_position = core_position

## Spawns ore deposits using OreRegistry's weighted distribution.
## Common ores appear frequently; Legendary ores are rare finds.
func _spawn_ore_deposits() -> void:
	var spawned := 0
	var tries   := 0
	while spawned < 60 and tries < 1200:
		tries += 1
		var wx := _rng.randf_range(T_ORIGIN_X + 15.0, T_ORIGIN_X + T_WIDTH - 15.0)
		var wz := _rng.randf_range(T_ORIGIN_Z - T_DEPTH + 15.0, T_ORIGIN_Z - 15.0)
		var h  := _sample_height(wx, wz)
		if h > HEIGHT_AMP * 0.80:
			continue
		var ore  := OreRegistry.get_random_weighted(_rng)
		var body := StaticBody3D.new()
		body.name = "Ore_%d" % _ore_counter
		_ore_counter += 1
		body.set_script(HarvestableDepositScript)
		body.set("ore_data", ore)
		get_parent().add_child(body)
		body.global_position = Vector3(wx, h, wz)
		spawned += 1

# ── Navigation ────────────────────────────────────────────────────────────────

func _setup_navigation() -> void:
	var nav_mesh := NavigationMesh.new()

	nav_mesh.cell_size = 0.75
	nav_mesh.cell_height = 0.3

	nav_mesh.agent_height = 2.0
	nav_mesh.agent_radius = 0.45
	nav_mesh.agent_max_slope = 60.0
	nav_mesh.agent_max_climb = 2.4

	nav_mesh.region_min_size = 2.0
	nav_mesh.edge_max_length = 12.0

	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_mesh.geometry_source_group_name = "nav_static"

	var nav_region := NavigationRegion3D.new()
	nav_region.name = "NavigationRegion"
	nav_region.navigation_mesh = nav_mesh

	get_parent().add_child(nav_region)

	await get_tree().process_frame
	await get_tree().process_frame

	nav_region.bake_navigation_mesh()

	await nav_region.bake_finished

func _valid_pos(wx: float, wz: float, placed: PackedVector2Array, min_dist: float) -> bool:
	if wx < T_ORIGIN_X + 8 or wx > T_ORIGIN_X + T_WIDTH - 8:
		return false
	if wz > T_ORIGIN_Z - 8 or wz < T_ORIGIN_Z - T_DEPTH + 8:
		return false
	var md_sq := min_dist * min_dist
	for p: Vector2 in placed:
		var dx := wx - p.x; var dz := wz - p.y
		if dx * dx + dz * dz < md_sq:
			return false
	return true
