extends Area2D

@export_flags_2d_physics var wall_collision_mask: int = 1
@export_range(1.0, 100.0, 1.0) var projectile_speed_meters_per_second: float = 25.0
@export_range(0.1, 10.0, 0.1) var smoke_duration: float = 2.5
@export_range(1.0, 20.0, 0.5) var smoke_scale: float = 5
@export_range(0.05, 2.0, 0.05) var expansion_duration: float = 0.2
@export_range(0.0, 720.0, 5.0) var smoke_rotation_speed_degrees: float = 180.0
@export_range(0.01, 0.2, 0.01) var network_sync_interval: float = 0.05
@export var exterior_smoke_color := Color(0.12, 0.72, 0.70, 1.0)
@export_range(12, 96, 4) var exterior_smoke_segments: int = 48

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var smoke_sprite: Sprite2D = $Sprite2D

var owner_peer_id := 1
var cast_id := 0
var movement_direction := Vector2.RIGHT
var ability: Node
var initialized := false
var smoke_started := false
var smoke_elapsed := 0.0
var smoke_expansion_elapsed := 0.0
var network_sync_timer := 0.0
var original_scale := Vector2.ONE
var exterior_smoke_fill: Polygon2D
var exterior_smoke_sprite: Sprite2D

func initialize(
	p_owner_peer_id: int,
	p_cast_id: int,
	start_position: Vector2,
	direction: Vector2,
	p_ability: Node
) -> void:
	owner_peer_id = p_owner_peer_id
	cast_id = p_cast_id
	ability = p_ability
	global_position = start_position
	original_scale = scale
	set_movement_direction(direction)
	initialized = true

func set_movement_direction(direction: Vector2) -> void:
	if direction.is_zero_approx() or not direction.is_finite():
		return
	movement_direction = direction.normalized()
	rotation = movement_direction.angle()

func _physics_process(delta: float) -> void:
	if not initialized:
		return
	if smoke_started:
		_update_smoke_view_layers()
		_process_smoke(delta)
	else:
		_process_projectile(delta)

func _process_projectile(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		global_position += (
			movement_direction
			* projectile_speed_meters_per_second
			* WeaponData.PIXELS_PER_METER
			* delta
		)
		return

	var travel_distance := (
		projectile_speed_meters_per_second
		* WeaponData.PIXELS_PER_METER
		* delta
	)
	var from_position := global_position
	var to_position := from_position + movement_direction * travel_distance
	var query := PhysicsRayQueryParameters2D.create(from_position, to_position)
	query.collision_mask = wall_collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _get_owner_collision_rids()
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit:
		var hit_position: Vector2 = hit["position"]
		_detonate_at(hit_position)
		return

	global_position = to_position
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		network_sync_timer -= delta
		if network_sync_timer <= 0.0:
			sync_projectile_state.rpc(global_position, movement_direction)
			network_sync_timer = network_sync_interval

func _process_smoke(delta: float) -> void:
	rotation += deg_to_rad(smoke_rotation_speed_degrees) * delta
	smoke_elapsed += delta
	smoke_expansion_elapsed += delta
	var expansion_progress := clampf(smoke_expansion_elapsed / expansion_duration, 0.0, 1.0)
	scale = original_scale * lerpf(1.0, smoke_scale, expansion_progress)
	if smoke_elapsed < smoke_duration:
		return
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			if is_instance_valid(ability):
				ability.call("broadcast_cloudburst_removal", cast_id)
		elif is_instance_valid(ability):
			ability.call("remove_cloudburst_locally", cast_id)
		return
	remove_smoke()

func detonate_at_current_position(final_direction: Vector2 = Vector2.ZERO) -> void:
	if not final_direction.is_zero_approx() and final_direction.is_finite():
		set_movement_direction(final_direction)
	_detonate_at(global_position)

func _detonate_at(smoke_position: Vector2) -> void:
	if smoke_started:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if multiplayer.has_multiplayer_peer():
		if is_instance_valid(ability):
			ability.call("broadcast_cloudburst_detonation", cast_id, smoke_position)
	else:
		enter_smoke(smoke_position)

func enter_smoke(smoke_position: Vector2) -> void:
	if smoke_started:
		return
	smoke_started = true
	add_to_group("vision_occluders")
	global_position = smoke_position
	smoke_elapsed = 0.0
	smoke_expansion_elapsed = 0.0
	collision_shape.set_deferred("disabled", true)
	_create_smoke_view_layers()
	_update_smoke_view_layers()
	if is_instance_valid(ability):
		ability.call("_on_cloudburst_detonated", cast_id)

func _create_smoke_view_layers() -> void:
	if exterior_smoke_fill or exterior_smoke_sprite or not smoke_sprite.texture:
		return
	exterior_smoke_fill = Polygon2D.new()
	exterior_smoke_fill.name = "ExteriorSmokeFill"
	exterior_smoke_fill.color = exterior_smoke_color
	exterior_smoke_fill.polygon = _build_exterior_smoke_polygon()
	exterior_smoke_fill.z_index = 100
	add_child(exterior_smoke_fill)

	exterior_smoke_sprite = Sprite2D.new()
	exterior_smoke_sprite.name = "ExteriorSmokeTexture"
	exterior_smoke_sprite.texture = smoke_sprite.texture
	exterior_smoke_sprite.texture_filter = smoke_sprite.texture_filter
	exterior_smoke_sprite.centered = smoke_sprite.centered
	exterior_smoke_sprite.offset = smoke_sprite.offset
	exterior_smoke_sprite.position = smoke_sprite.position
	exterior_smoke_sprite.scale = smoke_sprite.scale
	exterior_smoke_sprite.modulate = smoke_sprite.modulate
	exterior_smoke_sprite.self_modulate = smoke_sprite.self_modulate
	exterior_smoke_sprite.z_index = 101
	add_child(exterior_smoke_sprite)

func _build_exterior_smoke_polygon() -> PackedVector2Array:
	var polygon := PackedVector2Array()
	var circle := collision_shape.shape as CircleShape2D
	if not circle:
		return polygon
	var radius := circle.radius * maxf(
		absf(collision_shape.scale.x), absf(collision_shape.scale.y)
	)
	for index in range(exterior_smoke_segments):
		var angle := TAU * float(index) / float(exterior_smoke_segments)
		polygon.append(collision_shape.position + Vector2.from_angle(angle) * radius)
	return polygon

func _update_smoke_view_layers() -> void:
	if not exterior_smoke_fill or not exterior_smoke_sprite:
		return
	var camera := get_viewport().get_camera_2d()
	if not camera:
		exterior_smoke_fill.visible = true
		exterior_smoke_sprite.visible = true
		return
	var circle := collision_shape.shape as CircleShape2D
	if not circle:
		exterior_smoke_fill.visible = true
		exterior_smoke_sprite.visible = true
		return
	var smoke_radius := circle.radius * maxf(
		absf(collision_shape.global_scale.x), absf(collision_shape.global_scale.y)
	)
	var viewer_position := _get_local_viewer_position(camera)
	var viewer_is_inside := (
		viewer_position.distance_squared_to(collision_shape.global_position)
		<= smoke_radius * smoke_radius
	)
	exterior_smoke_fill.visible = not viewer_is_inside
	exterior_smoke_sprite.visible = not viewer_is_inside

func _get_local_viewer_position(camera: Camera2D) -> Vector2:
	var scene := get_tree().current_scene
	if scene:
		for node in scene.find_children("*", "BaseAgent", true, false):
			var agent := node as BaseAgent
			if not agent or agent.is_ai_dummy or not agent.has_local_authority():
				continue
			var agent_camera := agent.player_camera
			if agent_camera and agent_camera.is_current():
				return agent.global_position
	return camera.global_position

func blocks_vision(from_position: Vector2, to_position: Vector2) -> bool:
	if not smoke_started or not collision_shape.shape is CircleShape2D:
		return false
	var segment := to_position - from_position
	var segment_length_squared := segment.length_squared()
	var closest_point := from_position
	if segment_length_squared > 0.0:
		var along_segment := clampf(
			(global_position - from_position).dot(segment) / segment_length_squared,
			0.0,
			1.0
		)
		closest_point += segment * along_segment

	var smoke_shape := collision_shape.shape as CircleShape2D
	var smoke_radius := smoke_shape.radius * maxf(absf(global_scale.x), absf(global_scale.y))
	return closest_point.distance_squared_to(global_position) <= smoke_radius * smoke_radius

func _get_owner_collision_rids() -> Array[RID]:
	var excluded: Array[RID] = []
	var owner_agent := NetworkManager.find_player(owner_peer_id)
	if owner_agent:
		excluded.append(owner_agent.get_rid())
	return excluded

func remove_smoke() -> void:
	if is_instance_valid(ability):
		ability.call("_on_cloudburst_removed", cast_id)
	queue_free()

@rpc("authority", "call_remote", "unreliable")
func sync_projectile_state(
	server_position: Vector2,
	server_direction: Vector2
) -> void:
	if (
		multiplayer.is_server()
		or smoke_started
		or multiplayer.get_remote_sender_id() != 1
		or not server_direction.is_finite()
		or server_direction.is_zero_approx()
	):
		return
	global_position = server_position
	set_movement_direction(server_direction)
