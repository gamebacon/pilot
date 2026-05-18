extends Node

## Dynamic day/night cycle.
## Spawned as a child of the World root by WorldGenerator.generate().
## Finds Sun (DirectionalLight3D) and WorldEnvironment as siblings.
##
## Time convention:  0.0 = midnight · 0.25 = sunrise · 0.5 = solar noon · 0.75 = sunset

const DAY_DURATION := 2040.0     # shortened for testing — was 1200.0
const START_TIME   := 0.30    # start just after sunrise (≈ 07:12)

## Current time of day, 0..1.  Readable by HUD / other systems.
var time_of_day: float = START_TIME

var _sun:     DirectionalLight3D = null
var _sky_mat: PhysicalSkyMaterial = null
var _env:     Environment = null

# ── Setup ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("day_night")
	var root := get_parent()
	_sun = root.get_node_or_null("Sun") as DirectionalLight3D
	var we := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		_env = we.environment
		if _env.sky and _env.sky.sky_material is PhysicalSkyMaterial:
			_sky_mat = _env.sky.sky_material as PhysicalSkyMaterial
	_apply()

func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / DAY_DURATION, 1.0)
	_apply()

# ── Public helpers ────────────────────────────────────────────────────────────

func is_night() -> bool:
	return time_of_day > 0.75 or time_of_day < 0.25

## Returns in-game clock formatted as "HH:MM".
func get_time_string() -> String:
	var total_hours := time_of_day * 24.0
	var h := int(total_hours) % 24
	var m := int(fmod(total_hours, 1.0) * 60.0)
	return "%02d:%02d" % [h, m]

# ── Core ──────────────────────────────────────────────────────────────────────

## Sun elevation:  -1.0 = below horizon (midnight)  +1.0 = zenith (noon).
func _elevation() -> float:
	return sin(time_of_day * TAU - PI * 0.5)

func _apply() -> void:
	var elev := _elevation()

	# day_blend:  0 = deep night,  1 = full day.
	# Uses a smooth S-curve spanning ±0.30 elevation so there's no hard jump.
	var day_blend := _smooth(-0.30, 0.30, elev)

	# dawn_t:  1 = right at the horizon,  0 = high in the sky (~19°+).
	# Extra bloom of warm colour/haze close to the horizon.
	var dawn_t := 1.0 - _smooth(0.0, 0.34, elev)

	_update_sun(elev, day_blend, dawn_t)
	_update_sky(day_blend, dawn_t)
	_update_env(day_blend, dawn_t)

# ── Sun ───────────────────────────────────────────────────────────────────────

func _update_sun(elev: float, day_blend: float, dawn_t: float) -> void:
	if not _sun:
		return

	# Arc through the sky: max 66° elevation at noon (Nordic-ish latitude).
	_sun.rotation.x = -elev * deg_to_rad(66.0)
	# Slow east→west drift over the day.
	_sun.rotation.y = (time_of_day - 0.5) * PI

	# ── Colour: night blue → dawn gold → midday warm white ──
	_sun.light_color = _lerp3c(
		Color(0.38, 0.46, 0.85),   # moonlight blue
		Color(1.00, 0.52, 0.16),   # golden sunrise/sunset
		Color(0.97, 0.93, 0.84),   # warm midday white
		day_blend)

	# ── Energy ──
	# Kept clearly visible even at the horizon (0.45) so the sun disc never vanishes.
	# Deepens to a dim moonlight glow overnight.
	_sun.light_energy = _lerp3(0.030, 0.45, 1.52, day_blend)

# ── Sky material ──────────────────────────────────────────────────────────────

func _update_sky(day_blend: float, dawn_t: float) -> void:
	if not _sky_mat:
		return

	# ── Rayleigh: dark midnight blue → warm sunrise orange → clear nordic blue ──
	_sky_mat.rayleigh_color = _lerp3c(
		Color(0.04, 0.05, 0.20),   # night
		Color(0.72, 0.28, 0.10),   # dawn/dusk
		Color(0.20, 0.36, 0.56),   # midday
		day_blend)

	# ── Mie: strong scattering at dawn (creates the sun glow), subtle at midday ──
	_sky_mat.mie_color = _lerp3c(
		Color(0.48, 0.52, 0.80),   # night
		Color(0.96, 0.72, 0.44),   # dawn/dusk warm haze
		Color(0.72, 0.77, 0.84),   # midday neutral
		day_blend)
	_sky_mat.mie_coefficient  = _lerp3(0.001, 0.022, 0.0045, day_blend)
	# High eccentricity at dawn = very tight, visible solar corona.
	_sky_mat.mie_eccentricity = _lerp3(0.74, 0.96, 0.84, day_blend)

	# ── Turbidity: thin at night, heavy haze at dawn/dusk, clear at noon ──
	_sky_mat.turbidity = _lerp3(1.0, 8.5, 2.6, day_blend)

	# ── Sky brightness: never drops below 0.30 at dawn so the disc stays visible ──
	_sky_mat.energy_multiplier = _lerp3(0.006, 0.38, 1.0, day_blend)

	# ── Sun disc: large at horizon (atmospheric magnification), always prominent ──
	# Extra boost from dawn_t so it swells visibly as it approaches the horizon.
	_sky_mat.sun_disk_scale = _lerp3(8.0, 20.0, 12.0, day_blend) + dawn_t * 4.0

# ── Environment ───────────────────────────────────────────────────────────────

func _update_env(day_blend: float, _dawn_t: float) -> void:
	if not _env:
		return

	# ── Ambient colour: cold blue night → golden dawn → cool daylight ──
	_env.ambient_light_color = _lerp3c(
		Color(0.18, 0.20, 0.42),   # night — cold blue-grey
		Color(0.92, 0.70, 0.50),   # dawn — warm golden
		Color(0.62, 0.70, 0.88),   # day  — cool blue
		day_blend)

	# ── Ambient energy: smooth ramp, no hard step ──
	_env.ambient_light_energy = _lerp3(0.020, 0.28, 0.50, day_blend)

	# ── Fog: always on but nearly invisible at night; golden at dawn; thin at noon ──
	# Never hard-disabled — a near-zero density is imperceptible and avoids the pop.
	_env.fog_enabled = true
	_env.fog_light_color = _lerp3c(
		Color(0.20, 0.22, 0.40),   # night — barely lit
		Color(0.92, 0.64, 0.38),   # dawn/dusk — warm amber
		Color(0.68, 0.78, 0.92),   # day  — cool blue haze
		day_blend)
	_env.fog_density            = _lerp3(0.00008, 0.0080, 0.0014, day_blend)
	_env.fog_aerial_perspective = 0.40

# ── Helpers ───────────────────────────────────────────────────────────────────

## Smooth Hermite step: 0 when x ≤ edge0, 1 when x ≥ edge1, S-curve between.
static func _smooth(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## Three-stop float lerp: a at t=0, b at t=0.5, c at t=1.
static func _lerp3(a: float, b: float, c: float, t: float) -> float:
	if t < 0.5:
		return lerpf(a, b, t * 2.0)
	else:
		return lerpf(b, c, (t - 0.5) * 2.0)

## Three-stop Color lerp: a at t=0, b at t=0.5, c at t=1.
static func _lerp3c(a: Color, b: Color, c: Color, t: float) -> Color:
	if t < 0.5:
		return a.lerp(b, t * 2.0)
	else:
		return b.lerp(c, (t - 0.5) * 2.0)
