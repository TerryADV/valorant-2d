extends Area2D

const MAX_WALL_BOUNCES: int = 1
const WALL_BOUNCE_SEPARATION: float = 0.5

@export_flags_2d_physics var wall_collision_mask: int = 3
@export_range(2, 64, 1) var trail_point_limit: int = 10
@export_range(0.0, 2.0, 0.01) var trail_point_spacing: float = 2.0

@onready var ball_sprite: Sprite2D = $Sprite2D
@onready var halo: Sprite2D = $Halo
@onready var projectile_trail: Line2D = $Line2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var owner_peer_id := 1
var cast_id := 0
var movement_direction := Vector2.ZERO
var curve_sign := 1.0
var wall_bounces := 0
var speed_multiplier := 1.0
var travel_distance := 0.0
var distance_travelled := 0.0
var flight_time := 0.0
var max_flight_time := 0.0
var curve_angle_degrees := 90.0
var ability: Node
var trail_positions: Array[Vector2] = []
var detonation_started := false
var initialized := false

func initialize(
	p_owner_peer_id: int,
	p_cast_id: int,
	start_position: Vector2,
	direction: Vector2,
	p_curve_sign: float,
	p_travel_distance: float,
	p_flight_time: float,
	p_curve_angle_degrees: float,
	p_ability: Node
) -> void:
	owner_peer_id = p_owner_peer_id
	cast_id = p_cast_id
	movement_direction = direction.normalized()
	curve_sign = signf(p_curve_sign)
	travel_distance = p_travel_distance
	max_flight_time = p_flight_time
	curve_angle_degrees = p_curve_angle_degrees
	ability = p_ability
	global_position = start_position
	rotation = movement_direction.angle()
	monitoring = false
	monitorable = false
	collision_shape.set_deferred("disabled", true)
	ball_sprite.visible = true
	halo.visible = true
	projectile_trail.visible = true
	trail_positions.clear()
	trail_positions.append(global_position)
	_update_trail()
	initialized = true

func _physics_process(delta: float) -> void:
	if not initialized or detonation_started:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	flight_time += delta
	if max_flight_time <= 0.0 or flight_time >= max_flight_time:
		_detonate(global_position)
		return

	var remaining_distance := maxf(travel_distance - distance_travelled, 0.0)
	if remaining_distance <= 0.01:
		_detonate(global_position)
		return
	var curve_per_second := deg_to_rad(curve_angle_degrees) / max_flight_time
	movement_direction = movement_direction.rotated(curve_sign * curve_per_second * delta)
	rotation = movement_direction.angle()
	var frame_distance := minf(
		travel_distance / max_flight_time * speed_multiplier * delta,
		remaining_distance
	)
	var remaining_frame_distance := frame_distance
	while remaining_frame_distance > 0.01:
		var from_position := global_position
		var to_position := from_position + movement_direction * remaining_frame_distance
		var query := PhysicsRayQueryParameters2D.create(from_position, to_position)
		query.collision_mask = wall_collision_mask
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = _get_owner_collision_rids()
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			global_position = to_position
			distance_travelled += remaining_frame_distance
			break

		var hit_position: Vector2 = hit["position"]
		var hit_normal: Vector2 = hit["normal"]
		var distance_to_hit := from_position.distance_to(hit_position)
		distance_travelled += distance_to_hit
		remaining_frame_distance = maxf(remaining_frame_distance - distance_to_hit, 0.0)
		if wall_bounces >= MAX_WALL_BOUNCES or hit_normal.is_zero_approx():
			_detonate(hit_position)
			return

		wall_bounces += 1
		speed_multiplier *= 0.5
		movement_direction = movement_direction.bounce(hit_normal).normalized()
		rotation = movement_direction.angle()
		global_position = hit_position + hit_normal * WALL_BOUNCE_SEPARATION

	_record_trail_position()
	_update_trail()
	if distance_travelled >= travel_distance - 0.01:
		_detonate(global_position)
	elif multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_projectile_state.rpc(global_position, rotation)

func _record_trail_position() -> void:
	if trail_positions[-1].distance_to(global_position) < trail_point_spacing:
		return
	trail_positions.append(global_position)
	while trail_positions.size() > trail_point_limit:
		trail_positions.pop_front()

func _update_trail() -> void:
	var points := PackedVector2Array()
	for point in trail_positions:
		points.append(to_local(point))
	points.append(Vector2.ZERO)
	projectile_trail.points = points

func _get_owner_collision_rids() -> Array[RID]:
	var excluded: Array[RID] = []
	var owner_agent := NetworkManager.find_player(owner_peer_id)
	if owner_agent:
		excluded.append(owner_agent.get_rid())
	return excluded

func _detonate(at_position: Vector2) -> void:
	if detonation_started:
		return
	detonation_started = true
	if multiplayer.has_multiplayer_peer():
		detonate_rpc.rpc(at_position)
	else:
		_finish_detonation(at_position)

@rpc("any_peer", "call_local", "reliable")
func detonate_rpc(at_position: Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if multiplayer.is_server():
			if sender_id != 0 and sender_id != 1:
				return
		elif sender_id != 1:
			return
	_finish_detonation(at_position)

func _finish_detonation(at_position: Vector2) -> void:
	global_position = at_position
	ball_sprite.visible = false
	halo.visible = false
	projectile_trail.visible = false
	collision_shape.set_deferred("disabled", true)
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server() and is_instance_valid(ability):
			ability.call("apply_flash_at", at_position)
	elif is_instance_valid(ability):
		ability.call("apply_flash_at", at_position)
	if is_instance_valid(ability) and ability.has_method("play_active_audio"):
		ability.call("play_active_audio", at_position)
	queue_free()

@rpc("authority", "call_remote", "unreliable")
func sync_projectile_state(network_position: Vector2, network_rotation: float) -> void:
	if multiplayer.is_server() or detonation_started:
		return
	global_position = network_position
	rotation = network_rotation
	movement_direction = Vector2.RIGHT.rotated(network_rotation)
	_record_trail_position()
	_update_trail()
