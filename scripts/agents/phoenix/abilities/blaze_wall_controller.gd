extends Node2D

const SEGMENT_SPACING_RATIO: float = 0.9
const FLASH_OCCLUSION_LAYER: int = 1 << 6

@onready var segments: Node2D = $Segments
@onready var damage_area: Area2D = $DamageArea
@onready var damage_shape: CollisionShape2D = $DamageArea/CollisionShape2D

var owner_peer_id := 1
var wall_length := 0.0
var segment_length := 0.0
var segment_step := 0.0
var segment_base_scale := Vector2.ONE
var route_points := PackedVector2Array()
var segment_lengths := PackedFloat32Array()
var segment_damage_shapes: Array[CollisionShape2D] = []
var grow_duration := 1.5
var growth_elapsed := 0.0
var grown_length := 0.0
var duration := 8.0
var damage_per_second := 30.0
var elapsed_time := 0.0
var initialized := false
var expiration_started := false
var owner_healing_granted := false

func initialize(
	p_owner_peer_id: int,
	start_position: Vector2,
	p_route_points: PackedVector2Array,
	p_grow_duration: float,
	p_duration: float,
	p_damage_per_second: float,
	segment_scene: PackedScene
) -> void:
	owner_peer_id = p_owner_peer_id
	route_points = p_route_points
	wall_length = _get_route_length(route_points)
	grow_duration = maxf(p_grow_duration, 0.01)
	duration = maxf(p_duration, 0.1)
	damage_per_second = maxf(p_damage_per_second, 0.0)
	global_position = start_position

	var first_segment := segment_scene.instantiate() as Area2D
	var first_shape := first_segment.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var first_rectangle := first_shape.shape as RectangleShape2D if first_shape else null
	if not first_rectangle:
		push_error("Blaze segment needs a RectangleShape2D named CollisionShape2D.")
		first_segment.free()
		queue_free()
		return
	segment_base_scale = first_segment.scale
	segment_length = first_rectangle.size.y * absf(segment_base_scale.y)
	if segment_length <= 0.0:
		push_error("Blaze segment length must be greater than zero.")
		first_segment.free()
		queue_free()
		return
	segment_step = segment_length * SEGMENT_SPACING_RATIO

	var segment_count := ceili(wall_length / segment_step)
	for index in range(segment_count):
		var segment := first_segment if index == 0 else segment_scene.instantiate() as Area2D
		segments.add_child(segment)
		segment.visible = false
		var start_distance := float(index) * segment_step
		segment_lengths.append(minf(segment_length, wall_length - start_distance))

	var rectangle := damage_shape.shape as RectangleShape2D
	if not rectangle:
		push_error("Blaze wall damage area needs a RectangleShape2D.")
		queue_free()
		return
	for index in range(segment_count):
		var shape_node := damage_shape if index == 0 else CollisionShape2D.new()
		if index > 0:
			damage_area.add_child(shape_node)
		var segment_rectangle := RectangleShape2D.new()
		segment_rectangle.size = Vector2(segment_lengths[index], segment_length)
		shape_node.shape = segment_rectangle
		shape_node.disabled = true
		segment_damage_shapes.append(shape_node)
	_update_growth(0.0)
	initialized = true

func _physics_process(delta: float) -> void:
	if not initialized:
		return

	if grown_length < wall_length:
		growth_elapsed = minf(growth_elapsed + delta, grow_duration)
		var growth_ratio := minf(growth_elapsed / grow_duration, 1.0)
		_update_growth(wall_length * growth_ratio)
		if grown_length < wall_length:
			if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
				_check_owner_healing()
			return

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	elapsed_time += delta
	_check_owner_healing()
	_apply_wall_damage(delta)
	if elapsed_time >= duration:
		_expire_wall()

func _update_growth(new_length: float) -> void:
	grown_length = clampf(new_length, 0.0, wall_length)
	for index in range(segments.get_child_count()):
		var segment := segments.get_child(index) as Area2D
		var start_distance := float(index) * segment_step
		var visible_length := clampf(
			grown_length - start_distance,
			0.0,
			segment_lengths[index]
		)
		segment.visible = visible_length > 0.01
		segment.collision_layer = FLASH_OCCLUSION_LAYER if visible_length > 0.01 else 0
		segment.scale = Vector2(
			segment_base_scale.x,
			segment_base_scale.y * visible_length / segment_length
		)
		var center_distance := start_distance + visible_length * 0.5
		segment.position = _point_at_distance(center_distance)
		segment.rotation = _angle_at_distance(center_distance) - PI / 2.0

	for index in range(segment_damage_shapes.size()):
		var start_distance := float(index) * segment_step
		var visible_length := clampf(
			grown_length - start_distance,
			0.0,
			segment_lengths[index]
		)
		var shape_node := segment_damage_shapes[index]
		var shape := shape_node.shape as RectangleShape2D
		if shape:
			shape.size = Vector2(maxf(visible_length, 0.01), segment_length)
		var center_distance := start_distance + visible_length * 0.5
		shape_node.position = _point_at_distance(center_distance)
		shape_node.rotation = _angle_at_distance(center_distance)
		shape_node.set_deferred("disabled", visible_length <= 0.01)

func _get_route_length(points: PackedVector2Array) -> float:
	var length := 0.0
	for index in range(1, points.size()):
		length += points[index - 1].distance_to(points[index])
	return length

func _point_at_distance(distance: float) -> Vector2:
	var remaining := distance
	for index in range(1, route_points.size()):
		var start := route_points[index - 1]
		var offset := route_points[index] - start
		var edge_length := offset.length()
		if edge_length <= 0.001:
			continue
		if remaining <= edge_length:
			return start + offset * (remaining / edge_length)
		remaining -= edge_length
	return route_points[-1]

func _angle_at_distance(distance: float) -> float:
	var remaining := distance
	for index in range(1, route_points.size()):
		var offset := route_points[index] - route_points[index - 1]
		var edge_length := offset.length()
		if edge_length <= 0.001:
			continue
		if remaining <= edge_length:
			return offset.angle()
		remaining -= edge_length
	return (route_points[-1] - route_points[-2]).angle()

func _apply_wall_damage(delta: float) -> void:
	var owner_agent := NetworkManager.find_player(owner_peer_id)
	for body in damage_area.get_overlapping_bodies():
		if not body.has_method("take_damage"):
			continue
		if body is BaseAgent and (body as BaseAgent).is_dead:
			continue
		if body is BaseAgent and (body as BaseAgent).get_multiplayer_authority() == owner_peer_id:
			continue
		DamageSystem.apply_hit(body, damage_per_second * delta, owner_agent, "Blaze", false)

func _check_owner_healing() -> void:
	var owner_agent := NetworkManager.find_player(owner_peer_id)
	if not owner_agent:
		return
	for body in damage_area.get_overlapping_bodies():
		if body != owner_agent or owner_agent.is_dead:
			continue
		if not owner_healing_granted:
			owner_healing_granted = true
			var healing_component := owner_agent.get_node_or_null("Components/PhoenixHealing")
			if healing_component and healing_component.has_method("apply_healing_effect"):
				healing_component.call("apply_healing_effect", "Blaze")
		break

func _expire_wall() -> void:
	if expiration_started:
		return
	expiration_started = true
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		remove_wall_rpc.rpc()
	else:
		queue_free()

@rpc("any_peer", "call_local", "reliable")
func remove_wall_rpc() -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if multiplayer.is_server():
			if sender_id != 0 and sender_id != 1:
				return
		elif sender_id != 1:
			return
	queue_free()
