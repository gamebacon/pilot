extends Node3D
class_name HitReaction

## Reusable hit-response component. Add as child of any damageable entity.
## Call setup(bar_y) once, then connect HealthComponent.hp_changed -> on_hit().
##
## Renders a 2D ProgressBar inside a SubViewport, displayed as a Sprite3D
## billboard above the entity — proper left-anchored slider with no QuadMesh tricks.

const HIDE_DELAY:   float = 2.0
const LOW_HP_RATIO: float = 0.5

const BAR_VIEWPORT_W: int   = 200   # pixels — viewport & bar width
const BAR_VIEWPORT_H: int   = 22    # pixels — viewport & bar height
const BAR_PIXEL_SIZE: float = 0.005 # metres per pixel → 200 × 0.005 = 1.0 m wide
const BAR_CORNER_RAD: int   = 4     # rounded corner radius on StyleBoxFlat

## When set, the scale punch animates this node instead of get_parent().
var scale_target: Node3D = null

var _sprite:      Sprite3D    = null
var _viewport:    SubViewport = null
var _bar:         ProgressBar = null
var _fill_style:  StyleBoxFlat = null
var _hide_timer:  float       = 0.0
var _ratio:       float       = 1.0

func setup(bar_y: float) -> void:
	_build_bar(bar_y)
	_set_bar_visible(false)

func on_hit(current_hp: float, max_hp: float) -> void:
	_ratio = current_hp / max_hp if max_hp > 0.0 else 1.0
	if _ratio <= 0.0:
		_set_bar_visible(false)
		return
	_update_fill(_ratio)
	_set_bar_visible(true)
	if _ratio >= LOW_HP_RATIO:
		_hide_timer = HIDE_DELAY
	_play_scale_punch()

## Restore bar state silently — no punch animation.  Call on late-join sync.
func refresh_bar(current_hp: float, max_hp: float) -> void:
	if current_hp >= max_hp: return   # full health — bar stays hidden
	_ratio = current_hp / max_hp if max_hp > 0.0 else 1.0
	_update_fill(_ratio)             # also triggers UPDATE_ONCE
	_set_bar_visible(true)
	if _ratio >= LOW_HP_RATIO:
		_hide_timer = HIDE_DELAY

func _process(delta: float) -> void:
	if not _sprite or not _sprite.visible: return
	if _ratio >= LOW_HP_RATIO:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			_set_bar_visible(false)

# ── Bar construction ──────────────────────────────────────────────────────────

func _build_bar(bar_y: float) -> void:
	# SubViewport renders the 2D progress bar to a texture.
	_viewport                          = SubViewport.new()
	_viewport.size                     = Vector2i(BAR_VIEWPORT_W, BAR_VIEWPORT_H)
	_viewport.transparent_bg           = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	# Background style.
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.08, 0.9)
	_set_all_corners(bg_style, BAR_CORNER_RAD)

	# Fill style — cached so _update_fill can mutate its color in-place.
	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = Color(0.15, 0.9, 0.1)
	_set_all_corners(_fill_style, BAR_CORNER_RAD)

	_bar = ProgressBar.new()
	_bar.min_value       = 0.0
	_bar.max_value       = 1.0
	_bar.value           = 1.0
	_bar.show_percentage = false
	_bar.size            = Vector2(BAR_VIEWPORT_W, BAR_VIEWPORT_H)
	_bar.add_theme_stylebox_override("background", bg_style)
	_bar.add_theme_stylebox_override("fill",       _fill_style)
	_viewport.add_child(_bar)

	# Sprite3D displays the viewport texture as a billboard above the entity.
	_sprite              = Sprite3D.new()
	_sprite.texture      = _viewport.get_texture()
	_sprite.pixel_size   = BAR_PIXEL_SIZE
	_sprite.billboard    = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.no_depth_test = true
	_sprite.position     = Vector3(0.0, bar_y, 0.0)
	add_child(_sprite)

func _set_all_corners(style: StyleBoxFlat, radius: int) -> void:
	style.corner_radius_top_left     = radius
	style.corner_radius_top_right    = radius
	style.corner_radius_bottom_left  = radius
	style.corner_radius_bottom_right = radius

# ── Updates ───────────────────────────────────────────────────────────────────

func _update_fill(ratio: float) -> void:
	if not _bar: return
	_bar.value = ratio
	if _fill_style:
		_fill_style.bg_color = Color(1.0 - ratio, ratio * 0.88, 0.06)
	# Render once — viewport stays DISABLED every other frame.
	if _viewport:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _set_bar_visible(p_visible: bool) -> void:
	if _sprite:
		_sprite.visible = p_visible

func _play_scale_punch() -> void:
	var target: Node3D = scale_target if scale_target else get_parent() as Node3D
	if not target: return
	var tween: Tween = create_tween()
	tween.tween_property(target, "scale", Vector3.ONE * 0.95, 0.05)
	tween.tween_property(target, "scale", Vector3.ONE, 0.10).set_ease(Tween.EASE_OUT)
