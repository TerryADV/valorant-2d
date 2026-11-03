class_name DummyHazardArea
extends Area2D

const DEFAULT_AVOIDANCE_MARGIN := 18.0
var _dummy_detour_sides: Dictionary = {}

func _ready() -> void:
	add_to_group("dummy_hazards")

func _exit_tree() -> void:
	_dummy_detour_sides.clear()

func get_dummy_avoidance_direction(
	dummy: Node2D,
	from_position: Vector2,
	to_position: Vector2
) -> Vector2:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not shape_node or shape_node.disabled or not shape_node.shape:
		return Vector2.ZERO

	var hazard_radius := _get_avoidance_radius(shape_node.shape)
	if hazard_radius <= 0.0:
		return Vector2.ZERO
	hazard_radius *= maxf(absf(shape_node.global_scale.x), absf(shape_node.global_scale.y))
	var avoidance_radius := hazard_radius + DEFAULT_AVOIDANCE_MARGIN
	var dummy_id := dummy.get_instance_id()
	var segment := to_position - from_position
	var closest_point := from_position
	if segment.length_squared() > 0.001:
		var along_segment := clampf(
			(shape_node.global_position - from_position).dot(segment) / segment.length_squared(),
			0.0,
			1.0
		)
		closest_point += segment * along_segment

	var away := closest_point - shape_node.global_position
	var distance := away.length()
	if distance >= avoidance_radius + DEFAULT_AVOIDANCE_MARGIN:
		_dummy_detour_sides.erase(dummy_id)
		return Vector2.ZERO
	if distance >= avoidance_radius:
		return Vector2.ZERO
	if distance <= 0.001:
		away = from_position - shape_node.global_position
		if away.length_squared() <= 0.001:
			away = Vector2.UP
	var outward := away.normalized()
	var tangent_a := outward.rotated(PI / 2.0)
	var toward_destination := segment.normalized()
	if not _dummy_detour_sides.has(dummy_id):
		_dummy_detour_sides[dummy_id] = 1 if tangent_a.dot(toward_destination) >= 0.0 else -1
	var tangent := tangent_a * float(_dummy_detour_sides[dummy_id])
	var urgency := clampf((avoidance_radius - distance) / avoidance_radius, 0.0, 1.0)
	return (tangent + outward * (0.5 + urgency * 1.5)).normalized()

func _get_avoidance_radius(shape: Shape2D) -> float:
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size.length() * 0.5
	return 0.0
