extends Node2D

const FADE_DURATION := 0.7

var _barriers: Array[StaticBody2D] = []
var _sprites: Array[Sprite2D] = []
var _collisions: Array[CollisionShape2D] = []
var _base_modulates: Array[Color] = []
var _tweens: Array[Tween] = []

func _ready() -> void:
	for barrier_name in ["EquipA", "EquipB"]:
		var barrier := get_node_or_null(barrier_name) as StaticBody2D
		if not barrier:
			continue
		var sprite := barrier.get_node_or_null("Sprite2D") as Sprite2D
		var collision := barrier.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if not sprite or not collision:
			continue
		_barriers.append(barrier)
		_sprites.append(sprite)
		_collisions.append(collision)
		_base_modulates.append(sprite.modulate)
		_tweens.append(null)

func set_barriers_enabled(enabled: bool, animate_fade: bool = false) -> void:
	for index in _barriers.size():
		var barrier := _barriers[index]
		var sprite := _sprites[index]
		var collision := _collisions[index]
		var tween := _tweens[index]
		if tween and tween.is_running():
			tween.kill()
		if enabled:
			barrier.visible = true
			sprite.modulate = _base_modulates[index]
			collision.set_deferred("disabled", false)
			_tweens[index] = null
		elif animate_fade:
			barrier.visible = true
			collision.set_deferred("disabled", false)
			var fade := create_tween()
			_tweens[index] = fade
			fade.tween_property(sprite, "modulate:a", 0.0, FADE_DURATION)
			fade.tween_callback(_finish_fade.bind(index))
		else:
			_finish_fade(index)

func _finish_fade(index: int) -> void:
	if index < 0 or index >= _barriers.size():
		return
	_collisions[index].set_deferred("disabled", true)
	_barriers[index].visible = false
	_tweens[index] = null
