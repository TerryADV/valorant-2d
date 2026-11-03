class_name BarrierOrbWall
extends StaticBody2D

signal health_changed(current_health: float, max_health: float)

@export var initial_health := 400.0
@export var hardened_health := 600.0
@export var hardening_duration := 2.0
@export var wall_duration := 40.0
@export var end_of_life_crack_duration := 2.0

var segment_health: Array[float] = []
var max_health_per_segment := 0.0
var is_hardened := false
var is_preview := false
var _end_of_life_crack_opacity := 0.0
var _segments: Array[Dictionary] = []

func _ready() -> void:
	_collect_segments()
	if is_preview:
		for segment in _segments:
			(segment.cracked as Sprite2D).visible = false
		return
	max_health_per_segment = initial_health
	for index in range(_segments.size()):
		segment_health.append(initial_health)
		_set_segment_cracked_opacity(index, 1.0)
	_emit_total_health()
	_harden_after_delay()
	_expire_after_duration()

func take_damage(amount: float, _attacker: Node = null, _weapon_name: String = "") -> void:
	if _segments.is_empty():
		return
	_apply_segment_damage(0, amount)

func take_damage_from(
	_collider: Object,
	shape_index: int,
	amount: float,
	attacker: Node = null,
	_weapon_name: String = ""
) -> void:
	if is_preview or amount <= 0.0 or not is_finite(amount):
		return
	var segment_index := _get_segment_index_from_shape(shape_index)
	if segment_index < 0:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		if attacker is BaseAgent:
			request_damage_rpc.rpc_id(1, segment_index, amount, attacker.get_path())
		return
	_apply_segment_damage(segment_index, amount)

@rpc("any_peer", "reliable")
func request_damage_rpc(segment_index: int, amount: float, attacker_path: NodePath) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var attacker := get_node_or_null(attacker_path) as BaseAgent
	if (
		not attacker
		or attacker.get_multiplayer_authority() != sender_id
		or segment_index < 0
		or segment_index >= _segments.size()
		or amount <= 0.0
		or not is_finite(amount)
		or amount > 500.0
	):
		return
	_apply_segment_damage(segment_index, amount)

@rpc("authority", "call_local", "reliable")
func sync_segment_rpc(
	segment_index: int, health: float, health_limit: float, hardened: bool
) -> void:
	if (
		segment_index < 0
		or segment_index >= _segments.size()
		or not is_finite(health)
		or not is_finite(health_limit)
		or health_limit <= 0.0
	):
		return
	max_health_per_segment = health_limit
	segment_health[segment_index] = clampf(health, 0.0, health_limit)
	is_hardened = hardened
	_update_segment_visual(segment_index)
	if segment_health[segment_index] <= 0.0:
		_remove_segment(segment_index)
	_emit_total_health()

func _harden_after_delay() -> void:
	await get_tree().create_timer(hardening_duration).timeout
	if not is_inside_tree():
		return
	max_health_per_segment = hardened_health
	is_hardened = true
	for index in range(_segments.size()):
		if segment_health[index] <= 0.0:
			continue
		segment_health[index] = hardened_health
		_update_segment_visual(index)
	_emit_total_health()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		for index in range(_segments.size()):
			sync_segment_rpc.rpc(index, segment_health[index], hardened_health, true)

func _expire_after_duration() -> void:
	var fade_duration := minf(end_of_life_crack_duration, wall_duration)
	var wait_before_cracking := maxf(0.0, wall_duration - fade_duration)
	await get_tree().create_timer(wait_before_cracking).timeout
	if not is_inside_tree():
		return
	var fade_tween := create_tween()
	fade_tween.tween_method(
		_set_end_of_life_crack_opacity,
		_end_of_life_crack_opacity,
		1.0,
		fade_duration
	)
	await fade_tween.finished
	if not is_inside_tree():
		return
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			expire_wall_rpc.rpc()
	else:
		queue_free()

func _apply_segment_damage(segment_index: int, amount: float) -> void:
	if (
		segment_index < 0
		or segment_index >= segment_health.size()
		or segment_health[segment_index] <= 0.0
		or amount <= 0.0
		or not is_finite(amount)
	):
		return
	segment_health[segment_index] = maxf(0.0, segment_health[segment_index] - amount)
	_update_segment_visual(segment_index)
	var all_segments_destroyed := false
	if segment_health[segment_index] <= 0.0:
		_remove_segment(segment_index)
		all_segments_destroyed = _are_all_segments_destroyed()
	_emit_total_health()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_segment_rpc.rpc(
			segment_index, segment_health[segment_index], max_health_per_segment, is_hardened
		)
		if all_segments_destroyed:
			break_wall_rpc.rpc()
	elif all_segments_destroyed:
		queue_free()

func _update_segment_visual(segment_index: int) -> void:
	if not is_hardened:
		_set_segment_cracked_opacity(segment_index, 1.0)
		return
	var damage_ratio := 1.0 - segment_health[segment_index] / max_health_per_segment
	_set_segment_cracked_opacity(
		segment_index, maxf(clampf(damage_ratio, 0.0, 1.0), _end_of_life_crack_opacity)
	)

func _set_end_of_life_crack_opacity(opacity: float) -> void:
	_end_of_life_crack_opacity = clampf(opacity, 0.0, 1.0)
	for index in range(_segments.size()):
		if segment_health[index] > 0.0:
			_update_segment_visual(index)

func _set_segment_cracked_opacity(segment_index: int, opacity: float) -> void:
	var cracked := _segments[segment_index].cracked as Sprite2D
	var tint := cracked.modulate
	tint.a = opacity
	cracked.modulate = tint
	cracked.visible = opacity > 0.0

func _remove_segment(segment_index: int) -> void:
	var segment := _segments[segment_index]
	(segment.sprite as Sprite2D).visible = false
	(segment.cracked as Sprite2D).visible = false
	(segment.collision as CollisionShape2D).set_deferred("disabled", true)
	(segment.occluder as LightOccluder2D).visible = false

func _are_all_segments_destroyed() -> bool:
	for health in segment_health:
		if health > 0.0:
			return false
	return true

func _emit_total_health() -> void:
	var total_health := 0.0
	for health in segment_health:
		total_health += health
	health_changed.emit(total_health, max_health_per_segment * segment_health.size())

@rpc("authority", "call_local", "reliable")
func break_wall_rpc() -> void:
	queue_free()

@rpc("authority", "call_local", "reliable")
func expire_wall_rpc() -> void:
	queue_free()

func _get_segment_index_from_shape(shape_index: int) -> int:
	if shape_index < 0:
		return -1
	var owner_id := shape_find_owner(shape_index)
	if owner_id < 0:
		return -1
	var shape_owner := shape_owner_get_owner(owner_id)
	for index in range(_segments.size()):
		if _segments[index].collision == shape_owner:
			return index
	return -1

func _collect_segments() -> void:
	_segments.clear()
	for index in range(1, 5):
		var suffix := "" if index == 1 else str(index)
		var sprite := get_node_or_null("Sprite2D" + suffix) as Sprite2D
		var collision := get_node_or_null("CollisionShape2D" + suffix) as CollisionShape2D
		var occluder := get_node_or_null("LightOccluder2D" + suffix) as LightOccluder2D
		var cracked := sprite.get_node_or_null("cracked" + suffix) as Sprite2D if sprite else null
		if sprite and collision and occluder and cracked:
			_segments.append({
				"sprite": sprite,
				"cracked": cracked,
				"collision": collision,
				"occluder": occluder,
			})
