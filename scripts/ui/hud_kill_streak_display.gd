extends RefCounted

const KILL_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/ui/main/kill1.png"),
	preload("res://assets/sprites/ui/main/kill2.png"),
	preload("res://assets/sprites/ui/main/kill3.png"),
	preload("res://assets/sprites/ui/main/kill4.png"),
	preload("res://assets/sprites/ui/main/kill5.png"),
	preload("res://assets/sprites/ui/main/kill6.png"),
]
const KILL_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/sfx/hud/kills/kill1.MP3"),
	preload("res://assets/audio/sfx/hud/kills/kill2.MP3"),
	preload("res://assets/audio/sfx/hud/kills/kill3.MP3"),
	preload("res://assets/audio/sfx/hud/kills/kill4.MP3"),
	preload("res://assets/audio/sfx/hud/kills/kill5.MP3"),
	preload("res://assets/audio/sfx/hud/kills/kill6.MP3"),
]
const SCALE_IN_DURATION := 0.22
const FULL_TURN_DURATION := 0.42
const DEFAULT_DISPLAY_DURATION := 1.5
const HIGH_STREAK_DISPLAY_DURATION := 4.0

var _base: TextureRect
var _count: TextureRect
var _last_kill_count := 0
var _base_scale := Vector2.ONE
var _base_rotation := 0.0
var _count_rotation := 0.0
var _animation: Tween
var _hide_timer: Tween

func setup(base: TextureRect, count: TextureRect) -> void:
	_base = base
	_count = count
	_base_scale = base.scale
	_base_rotation = base.rotation
	_count_rotation = count.rotation
	_base.pivot_offset = base.size * 0.5
	if not base.resized.is_connected(_update_pivot):
		base.resized.connect(_update_pivot)
	reset()

func register_kill() -> void:
	_last_kill_count += 1
	var kill_index := mini(_last_kill_count, KILL_TEXTURES.size()) - 1
	_count.texture = KILL_TEXTURES[kill_index]
	AudioManager.play_global_stream(KILL_SOUNDS[kill_index], 0.0, 1.0)
	_play_animation()
	var display_duration := (
		HIGH_STREAK_DISPLAY_DURATION
		if _last_kill_count >= 5
		else DEFAULT_DISPLAY_DURATION
	)
	_schedule_hide(display_duration)

func reset() -> void:
	_last_kill_count = 0
	_stop_animation()
	_stop_hide_timer()
	_base.visible = false
	_base.scale = _base_scale
	_base.rotation = _base_rotation
	_count.rotation = _count_rotation

func _play_animation() -> void:
	_stop_animation()
	_base.visible = true
	_base.scale = Vector2.ZERO
	_base.rotation = _base_rotation
	_count.rotation = _count_rotation
	_animation = _base.create_tween()
	_animation.tween_property(
		_base, "scale", _base_scale, SCALE_IN_DURATION
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_animation.tween_property(
		_count, "rotation", _count_rotation + TAU, FULL_TURN_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_animation.tween_callback(func() -> void: _count.rotation = _count_rotation)

func _stop_animation() -> void:
	if _animation and _animation.is_running():
		_animation.kill()
	_animation = null

func _schedule_hide(duration: float) -> void:
	_stop_hide_timer()
	_hide_timer = _base.create_tween()
	_hide_timer.tween_interval(duration)
	_hide_timer.tween_callback(_hide)

func _stop_hide_timer() -> void:
	if _hide_timer and _hide_timer.is_running():
		_hide_timer.kill()
	_hide_timer = null

func _hide() -> void:
	_base.visible = false
	_base.scale = _base_scale
	_base.rotation = _base_rotation
	_count.rotation = _count_rotation

func _update_pivot() -> void:
	if _base:
		_base.pivot_offset = _base.size * 0.5
