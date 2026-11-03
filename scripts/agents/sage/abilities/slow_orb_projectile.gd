extends Area2D

@export var sync_interval := 0.05

const MAX_WALL_BOUNCES := 1
const WALL_BOUNCE_SEPARATION := 0.5
const MAX_FLIGHT_TIME := 2.0
const POST_BOUNCE_FLIGHT_TIME := 0.5

var movement_direction := Vector2.ZERO
var remaining_distance := 0.0
var throw_speed := 0.0
var owner_peer_id := 1
var wall_bounces := 0
var ability: Node
var initialized := false
var stopped := false
var flight_time := 0.0
var post_bounce_flight_time := 0.0
var _sync_elapsed := 0.0

func initialize(
	p_owner_peer_id: int,
	start_position: Vector2,
	direction: Vector2,
	travel_distance: float,
	p_throw_speed: float,
	p_ability: Node
) -> void:
	owner_peer_id = p_owner_peer_id
	ability = p_ability
	global_position = start_position
	movement_direction = direction.normalized()
	remaining_distance = maxf(travel_distance, 0.0)
	throw_speed = maxf(p_throw_speed, 0.0)
	rotation = movement_direction.angle() + PI / 2.0
	monitoring = false
	monitorable = false
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	initialized = true

func _physics_process(delta: float) -> void:
	if not initialized or stopped:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if remaining_distance <= 0.01 or throw_speed <= 0.0 or flight_time >= MAX_FLIGHT_TIME:
		_stop_at(global_position)
		return
	var frame_time := minf(delta, MAX_FLIGHT_TIME - flight_time)
	var step_distance := minf(throw_speed * frame_time, remaining_distance)
	var destination := global_position + movement_direction * step_distance
	var bounced_this_frame := false
	var elapsed_after_bounce := 0.0
	var query := PhysicsRayQueryParameters2D.create(global_position, destination)
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _get_excluded_rids()
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit:
		var hit_position: Vector2 = hit["position"]
		var hit_normal: Vector2 = hit["normal"]
		var distance_to_hit := global_position.distance_to(hit_position)
		remaining_distance = maxf(remaining_distance - distance_to_hit, 0.0)
		if wall_bounces >= MAX_WALL_BOUNCES or hit_normal.is_zero_approx():
			_stop_at(hit_position)
			return
		var time_to_hit := distance_to_hit / throw_speed
		wall_bounces += 1
		bounced_this_frame = true
		elapsed_after_bounce = maxf(frame_time - time_to_hit, 0.0)
		throw_speed *= 0.2
		movement_direction = movement_direction.bounce(hit_normal).normalized()
		rotation = movement_direction.angle() + PI / 2.0
		global_position = hit_position + hit_normal * WALL_BOUNCE_SEPARATION
	else:
		global_position = destination
		remaining_distance -= step_distance
	flight_time += frame_time
	if wall_bounces > 0:
		post_bounce_flight_time += elapsed_after_bounce if bounced_this_frame else frame_time
	_sync_elapsed += frame_time
	if multiplayer.has_multiplayer_peer() and _sync_elapsed >= sync_interval:
		_sync_elapsed = 0.0
		sync_projectile_rpc.rpc(global_position, rotation)
	if (
		remaining_distance <= 0.01
		or flight_time >= MAX_FLIGHT_TIME
		or post_bounce_flight_time >= POST_BOUNCE_FLIGHT_TIME
	):
		_stop_at(global_position)

func _get_excluded_rids() -> Array[RID]:
	var excluded: Array[RID] = [get_rid()]
	var owner_agent := NetworkManager.call("find_player", owner_peer_id) as BaseAgent
	if owner_agent:
		_add_collision_rids(owner_agent, excluded)
	return excluded

func _add_collision_rids(node: Node, rids: Array[RID]) -> void:
	if node is CollisionObject2D:
		rids.append((node as CollisionObject2D).get_rid())
	for child in node.get_children():
		_add_collision_rids(child, rids)

func _stop_at(stop_position: Vector2) -> void:
	if stopped:
		return
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		stop_projectile_rpc.rpc(stop_position, rotation)
		if is_instance_valid(ability):
			ability.call("spawn_zone", owner_peer_id, stop_position)
		despawn_projectile_rpc.rpc()
	else:
		_apply_stop(stop_position, rotation)
		if not multiplayer.has_multiplayer_peer() and is_instance_valid(ability):
			ability.call("spawn_zone", owner_peer_id, stop_position)
		if not multiplayer.has_multiplayer_peer():
			queue_free()

@rpc("authority", "call_remote", "unreliable")
func sync_projectile_rpc(network_position: Vector2, network_rotation: float) -> void:
	if not multiplayer.is_server() and network_position.is_finite():
		global_position = network_position
		rotation = network_rotation
		movement_direction = Vector2.RIGHT.rotated(network_rotation - PI / 2.0)

@rpc("authority", "call_local", "reliable")
func stop_projectile_rpc(stop_position: Vector2, stop_rotation: float) -> void:
	if stop_position.is_finite():
		_apply_stop(stop_position, stop_rotation)

@rpc("authority", "call_local", "reliable")
func despawn_projectile_rpc() -> void:
	queue_free()

func _apply_stop(stop_position: Vector2, stop_rotation: float) -> void:
	global_position = stop_position
	rotation = stop_rotation
	remaining_distance = 0.0
	stopped = true
	set_physics_process(false)
