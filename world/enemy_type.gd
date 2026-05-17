class_name EnemyType

## Defines stats and sound paths for one enemy variant.
## Add a new static _xxx() method + include it in all() to register a new type.

var id: String            = ""
var display_name: String  = ""
var max_hp: float         = 60.0
var speed: float          = 3.5
var damage: float         = 10.0
var attack_cooldown: float = 1.0  # seconds between core hits
var body_color: Color     = Color(0.85, 0.15, 0.15)
var capsule_radius: float = 0.40
var capsule_height: float = 1.80
var wave_min: int         = 1     # first wave this type can appear

# Sound paths — empty string = no sound for that slot.
# Drop replacements into res://audio/sfx/ and update the paths here.
var snd_footstep: String = ""
var snd_attack: String   = ""
var snd_hurt: String     = ""
var snd_death: String    = ""
var snd_ambient: String  = ""

# ── Registry ──────────────────────────────────────────────────────────────────

static func all() -> Array[EnemyType]:
	return [_grunt(), _brute(), _runner()]

## Returns every type available on a given wave number.
static func for_wave(wave: int) -> Array[EnemyType]:
	var out: Array[EnemyType] = []
	for t in all():
		if t.wave_min <= wave:
			out.append(t)
	return out

## Look up by id string (used by RPC so both peers agree on the type).
static func by_id(search_id: String) -> EnemyType:
	for t in all():
		if t.id == search_id:
			return t
	return _grunt()

# ── Type definitions ──────────────────────────────────────────────────────────

static func _grunt() -> EnemyType:
	var t               := EnemyType.new()
	t.id                = "grunt"
	t.display_name      = "Grunt"
	t.max_hp            = 60.0
	t.speed             = 2.5
	t.damage            = 10.0
	t.attack_cooldown   = 1.0
	t.body_color        = Color(0.85, 0.15, 0.15)
	t.capsule_radius    = 0.40
	t.capsule_height    = 1.80
	t.wave_min          = 1
	t.snd_footstep      = "res://audio/sfx/footstep_default.mp3"
	t.snd_attack        = "res://audio/sfx/item_collide.mp3"
	t.snd_hurt          = "res://audio/sfx/item_collide.mp3"
	t.snd_death         = "res://audio/sfx/item_place.mp3"
	t.snd_ambient       = ""   # swap in: res://audio/sfx/enemy_grunt_idle.mp3
	return t

static func _brute() -> EnemyType:
	var t               := EnemyType.new()
	t.id                = "brute"
	t.display_name      = "Brute"
	t.max_hp            = 150.0
	t.speed             = 1.0
	t.damage            = 25.0
	t.attack_cooldown   = 2.5
	t.body_color        = Color(0.45, 0.08, 0.60)
	t.capsule_radius    = 0.65
	t.capsule_height    = 2.90
	t.wave_min          = 2
	t.snd_footstep      = "res://audio/sfx/footstep_default.mp3"
	t.snd_attack        = "res://audio/sfx/item_collide.mp3"
	t.snd_hurt          = "res://audio/sfx/item_collide.mp3"
	t.snd_death         = "res://audio/sfx/item_place.mp3"
	t.snd_ambient       = ""   # swap in: res://audio/sfx/enemy_brute_idle.mp3
	return t

static func _runner() -> EnemyType:
	var t               := EnemyType.new()
	t.id                = "runner"
	t.display_name      = "Runner"
	t.max_hp            = 25.0
	t.speed             = 4.0
	t.damage            = 5.0
	t.attack_cooldown   = 0.5
	t.body_color        = Color(1.00, 0.50, 0.05)
	t.capsule_radius    = 0.28
	t.capsule_height    = 1.40
	t.wave_min          = 3
	t.snd_footstep      = "res://audio/sfx/footstep_default.mp3"
	t.snd_attack        = "res://audio/sfx/item_collide.mp3"
	t.snd_hurt          = "res://audio/sfx/item_collide.mp3"
	t.snd_death         = "res://audio/sfx/item_place.mp3"
	t.snd_ambient       = ""   # swap in: res://audio/sfx/enemy_runner_idle.mp3
	return t
