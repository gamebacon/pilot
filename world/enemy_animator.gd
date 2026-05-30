class_name EnemyAnimator
extends Node

## Manages animation merging and playback for one enemy instance.
## Add as a child of the enemy body after the model node is attached.
##
## Usage:
##   var _animator := EnemyAnimator.new(anim_player, enemy_type)
##   add_child(_animator)
##   _animator.merge_animations()
##   _animator.play(enemy_type.anim_walk)

const BLEND_TIME: float = 0.2
const DEATH_BLEND_TIME: float = 0.4

## Emitted after the death animation (+ blend) finishes. Connect to queue_free.
signal death_finished

var _anim: AnimationPlayer = null
var _type: EnemyType       = null
var _is_dying: bool        = false
var _playing_once: bool    = false

func _init(anim_player: AnimationPlayer, enemy_type: EnemyType) -> void:
	_anim = anim_player
	_type = enemy_type

# ── Animation merging ─────────────────────────────────────────────────────────

## Load each FBX in enemy_type.anim_files, extract its "mixamo_com" clip, and
## register it under the logical name in the model's AnimationPlayer.
func merge_animations() -> void:
	if _anim == null or _type.anim_files.is_empty():
		return
	if not _anim.has_animation_library(""):
		return

	var lib: AnimationLibrary = _anim.get_animation_library("")

	for anim_name: String in _type.anim_files:
		var path: String = _type.anim_files[anim_name]
		if path == "" or not ResourceLoader.exists(path):
			continue

		var packed: PackedScene = load(path)
		if packed == null:
			continue

		var scene: Node3D = packed.instantiate() as Node3D
		if scene == null:
			continue

		var src_ap: AnimationPlayer = scene.find_child(
			"AnimationPlayer", true, false
		) as AnimationPlayer

		if src_ap and src_ap.has_animation_library(""):
			var src_lib: AnimationLibrary = src_ap.get_animation_library("")
			if src_lib.has_animation("mixamo_com"):
				lib.add_animation(anim_name, src_lib.get_animation("mixamo_com"))

		scene.queue_free()

	# Remove the raw placeholder now that named clips exist.
	if lib.has_animation("mixamo_com"):
		lib.remove_animation("mixamo_com")

# ── Playback ──────────────────────────────────────────────────────────────────

## Play a looping animation. No-ops while dying or if the clip doesn't exist.
func play(anim_name: String) -> void:
	if _is_dying or _anim == null or anim_name == "":
		return
	if not _anim.has_animation(anim_name):
		return
	_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_anim.play(anim_name, BLEND_TIME)

## Play a one-shot clip then resume resume_anim. Ignored while dying or if
## another one-shot is already in progress (prevents overlapping hurt coroutines).
func play_once(anim_name: String, resume_anim: String) -> void:
	if _is_dying or _playing_once or _anim == null:
		return
	if not _anim.has_animation(anim_name):
		return

	_playing_once = true
	_anim.get_animation(anim_name).loop_mode = Animation.LOOP_NONE
	_anim.play(anim_name, BLEND_TIME)
	await _anim.animation_finished
	_playing_once = false

	if _is_dying:
		return
	play(resume_anim)

## Play one attack swing then return to idle. Can interrupt a previous swing.
func play_attack() -> void:
	if _is_dying or _anim == null:
		return
	if not _anim.has_animation(_type.anim_attack):
		return
	_anim.get_animation(_type.anim_attack).loop_mode = Animation.LOOP_NONE
	_anim.play(_type.anim_attack, BLEND_TIME)
	await _anim.animation_finished
	if _is_dying:
		return
	play(_type.anim_idle)

## Play the death animation, wait for it to finish, then emit death_finished.
## The caller should connect death_finished to queue_free on the enemy.
func start_dying() -> void:
	_is_dying  = true
	_playing_once = false  # cancel any pending one-shot

	var death_duration: float = 0.0

	if _anim and _type.anim_death != "" and _anim.has_animation(_type.anim_death):
		var clip: Animation = _anim.get_animation(_type.anim_death)
		clip.loop_mode = Animation.LOOP_NONE
		death_duration = clip.length
		_anim.play(_type.anim_death, DEATH_BLEND_TIME)

	await get_tree().create_timer(death_duration + DEATH_BLEND_TIME).timeout
	death_finished.emit()
