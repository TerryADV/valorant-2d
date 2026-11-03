extends Area2D

@export_flags_2d_physics var wall_collision_mask: int = 1

var owner_peer_id := 1
var cast_id := 0
var movement_direction := Vector2.ZERO
var remaining_distance := 0.0
var max_flight_time := 0.0
var flight_time := 0.0
var distance_travelled := 0.0
var throw_speed := 0.0
var wall_bounces := 0
var ability: Node
var initialized := false
var detonation_started := false

func initialize(
	p_owner_peer_id: int,
	p_cast_id: int,
	start_position: Vector2,
	direction: Vector2,
	p_travel_distance: float,
	p_max_flight_time: float,
	p_ability: Node
) -> void:
	owner_peer_id = p_owner_peer_id
	cast_id = p_cast_id
	ability = p_ability
	global_position = start_position
	movement_direction = direction.normalized()
	remaining_distance = maxf(p_travel_distance, 0.0)
	max_flight_time = maxf(p_max_flight_time, 0.0)
	throw_speed = remaining_distance / max_flight_time if max_flight_time > 0.0 else 0.0
	rotation = movement_direction.angle() - PI / 2.0
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

	var from_position := global_position
	if remaining_distance <= 0.01:
		_detonate(global_position)
		return
	var frame_distance := minf(throw_speed * delta, remaining_distance)
	var to_position := from_position + movement_direction * frame_distance

	var query := PhysicsRayQueryParameters2D.create(from_position, to_position)
	query.collision_mask = wall_collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _get_owner_collision_rids()

	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit:
		var hit_position: Vector2 = hit["position"]
		var normal: Vector2 = hit["normal"]
		var distance_to_hit := from_position.distance_to(hit_position)
		distance_travelled += distance_to_hit
		remaining_distance = maxf(remaining_distance - distance_to_hit, 0.0)
		if wall_bounces == 0 and not normal.is_zero_approx():
			wall_bounces += 1
			throw_speed *= 0.5
			global_position = hit_position + normal * 0.5
			movement_direction = movement_direction.bounce(normal).normalized()
			rotation = movement_direction.angle() - PI / 2.0
		else:
			_detonate(hit_position)
			return
	else:
		global_position = to_position
		distance_travelled += frame_distance
		remaining_distance = maxf(remaining_distance - frame_distance, 0.0)
		if remaining_distance <= 0.01:
			_detonate(global_position)
			return
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_projectile_state.rpc(global_position, rotation)

func _get_owner_collision_rids() -> Array[RID]:
	var excluded: Array[RID] = []
	var owner_agent := NetworkManager.call("find_player", owner_peer_id) as BaseAgent
	if owner_agent:
		_add_collision_rids(owner_agent, excluded)
	return excluded

func _add_collision_rids(node: Node, rids: Array[RID]) -> void:
	if node is CollisionObject2D:
		rids.append(node.get_rid())
	for child in node.get_children():
		_add_collision_rids(child, rids)

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
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and is_instance_valid(ability):
		ability.call("spawn_zone", owner_peer_id, cast_id, at_position)
	elif not multiplayer.has_multiplayer_peer() and is_instance_valid(ability):
		ability.call("spawn_zone", owner_peer_id, cast_id, at_position)
	queue_free()

@rpc("authority", "call_remote", "unreliable")
func sync_projectile_state(network_position: Vector2, network_rotation: float) -> void:
	if multiplayer.is_server():
		return
	global_position = network_position
	rotation = network_rotation
