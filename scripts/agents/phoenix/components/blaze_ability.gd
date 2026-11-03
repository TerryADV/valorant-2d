extends Node

const WALL_SEGMENT_SCENE: PackedScene = preload("res://scenes/agents/phoenix/blaze_wall.tscn")
const WALL_CONTROLLER_SCENE: PackedScene = preload("res://scenes/agents/phoenix/blaze_wall_controller.tscn")
const METERS_TO_PIXELS: float = WeaponData.PIXELS_PER_METER
const ROUTE_SAMPLE_DISTANCE: float = 2.0
const PREVIEW_ORB_RADIUS: float = 1.0
const PREVIEW_ORB_POINT_COUNT: int = 20

@export_group("Audio")
@export var cast_audio: AudioCue
@export var voice_audio: AudioCue
@export var active_audio: AudioCue

@export_range(1.0, 50.0, 0.5) var wall_length_meters: float = 20.0
@export_range(30.0, 1000.0, 10.0) var wall_projectile_speed: float = 100.0
@export_range(45.0, 1080.0, 15.0) var wall_projectile_turn_speed: float = 360.0
@export_range(0.1, 5.0, 0.1) var wall_grow_duration: float = 1.5
@export_range(1.0, 30.0, 0.5) var wall_duration: float = 8.0
@export_range(0.0, 500.0, 0.5) var damage_per_second: float = 30.0
@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var held_segment: Area2D
var held_segment_sprite: Sprite2D
var held_segment_sprite_base_scale := Vector2.ONE
var is_equipped := false
var request_pending := false
var next_wall_id := 0
var is_drawing_wall := false
var route_start_position := Vector2.ZERO
var wall_projectile_position := Vector2.ZERO
var wall_projectile_direction := Vector2.ZERO
var wall_travelled_length := 0.0
var wall_route := PackedVector2Array()
var route_preview_line: Line2D
var route_preview_orb: Line2D

func reset_for_new_round() -> void:
	is_drawing_wall = false
	request_pending = false
	wall_route.clear()
	_clear_route_preview()
	_set_equipped(false)

func _ready() -> void:
	held_segment = agent.get_node_or_null("Visuals/BlazeHeld") as Area2D
	if not held_segment:
		push_error("Blaze held segment is missing from the agent scene.")
		return
	held_segment.top_level = true
	held_segment.monitoring = false
	held_segment.monitorable = false
	held_segment_sprite = held_segment.get_node_or_null("Sprite2D") as Sprite2D
	if not held_segment_sprite:
		push_error("Blaze held segment sprite is missing from the agent scene.")
		return
	held_segment_sprite_base_scale = held_segment_sprite.scale
	held_segment.visible = false
	_position_held_segment()

func _process(delta: float) -> void:
	if is_equipped:
		_position_held_segment()
		if is_drawing_wall:
			_advance_wall_projectile(delta)
			if wall_travelled_length >= wall_length_meters * METERS_TO_PIXELS:
				_finish_wall_route()
			else:
				_update_route_preview()
	if agent and (agent.is_dead or agent.shop_open) and is_equipped:
		is_drawing_wall = false
		wall_route.clear()
		_set_equipped(false)

func _input(event: InputEvent) -> void:
	if not agent or not agent.has_local_authority() or agent.is_dead or agent.shop_open or agent.is_match_preparing:
		return

	if not is_equipped or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse_event.pressed:
		if request_pending or is_drawing_wall:
			return
		_begin_wall_route()
		get_viewport().set_input_as_handled()
		return
	if not is_drawing_wall:
		return

	_finish_wall_route()
	get_viewport().set_input_as_handled()

func _finish_wall_route() -> void:
	if not is_drawing_wall:
		return
	_append_final_wall_point()
	is_drawing_wall = false
	if wall_route.size() < 2 or _get_route_length(wall_route) <= 0.01:
		wall_route.clear()
		_clear_route_preview()
		return
	_clear_route_preview()
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_pending = true
		_set_equipped(false)
		request_wall_rpc.rpc_id(1, route_start_position, wall_route)
	else:
		_launch_wall(route_start_position, wall_route)
	wall_route = PackedVector2Array()

func blocks_weapon_input() -> bool:
	return is_equipped or request_pending

@rpc("any_peer", "reliable")
func request_equipped_rpc(equipped: bool) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != agent.get_multiplayer_authority():
		return
	if agent.is_dead or agent.shop_open or agent.is_match_preparing:
		return
	_sync_equipped_state(equipped)

@rpc("any_peer", "call_local", "reliable")
func sync_equipped_rpc(owner_peer_id: int, equipped: bool) -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if multiplayer.is_server():
			if sender_id != 0 and sender_id != 1:
				return
		elif sender_id != 1:
			return
	if owner_peer_id != agent.get_multiplayer_authority():
		return
	_set_equipped(equipped)

func _sync_equipped_state(equipped: bool) -> void:
	sync_equipped_rpc.rpc(agent.get_multiplayer_authority(), equipped)

@rpc("any_peer", "reliable")
func request_wall_rpc(start_position: Vector2, route: PackedVector2Array) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != agent.get_multiplayer_authority():
		return
	if (
		agent.is_dead
		or agent.shop_open
		or agent.is_match_preparing
		or not is_equipped
		or not agent.has_ability_charge("Blaze")
	):
		wall_rejected_rpc.rpc_id(agent.get_multiplayer_authority())
		return
	if not start_position.is_finite() or not _is_valid_route(route):
		wall_rejected_rpc.rpc_id(agent.get_multiplayer_authority())
		return
	_launch_wall(start_position, route)

@rpc("any_peer", "call_remote", "reliable")
func wall_rejected_rpc() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	request_pending = false
	if (
		agent.has_local_authority()
		and not agent.is_dead
		and not agent.shop_open
		and agent.has_ability_charge("Blaze")
	):
		_set_equipped(true)

func _launch_wall(start_position: Vector2, route: PackedVector2Array) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if not agent.consume_ability_charge("Blaze"):
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			wall_rejected_rpc.rpc_id(agent.get_multiplayer_authority())
		return
	next_wall_id += 1
	var owner_peer_id := agent.get_multiplayer_authority() if multiplayer.has_multiplayer_peer() else 1
	_play_voice_for_owner(owner_peer_id)
	var route_copy := route.duplicate()
	request_pending = false
	agent.set_active_ability("")
	_set_equipped(false)
	if agent.weapon_controller:
		agent.weapon_controller.suppress_shoot_until_released()

	if multiplayer.has_multiplayer_peer():
		spawn_wall_rpc.rpc(
			owner_peer_id,
			next_wall_id,
			start_position,
			route_copy,
			wall_grow_duration
		)
	else:
		_spawn_wall(
			owner_peer_id,
			next_wall_id,
			start_position,
			route_copy,
			wall_grow_duration
		)

func _play_voice_for_owner(owner_peer_id: int) -> void:
	if not multiplayer.has_multiplayer_peer() or owner_peer_id == 1:
		AudioManager.play_global_cue(voice_audio)
	elif multiplayer.is_server():
		play_voice_rpc.rpc_id(owner_peer_id)
	else:
		push_error("Only the server can route Blaze voice audio.")

@rpc("any_peer", "call_remote", "reliable")
func play_voice_rpc() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if not agent.has_local_authority():
		return
	AudioManager.play_global_cue(voice_audio)

@rpc("any_peer", "call_local", "reliable")
func spawn_wall_rpc(
	owner_peer_id: int,
	wall_id: int,
	start_position: Vector2,
	route: PackedVector2Array,
	grow_duration: float
) -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if multiplayer.is_server():
			if sender_id != 0 and sender_id != 1:
				return
		elif sender_id != 1:
			return
	if not _is_valid_route(route):
		return
	if not is_finite(grow_duration) or grow_duration <= 0.0:
		return

	next_wall_id = maxi(next_wall_id, wall_id)
	request_pending = false
	_set_equipped(false)
	if agent.weapon_controller:
		agent.weapon_controller.suppress_shoot_until_released()
	_spawn_wall(owner_peer_id, wall_id, start_position, route, grow_duration)

func _spawn_wall(
	owner_peer_id: int,
	wall_id: int,
	start_position: Vector2,
	route: PackedVector2Array,
	grow_duration: float
) -> void:
	var current_scene := get_tree().current_scene
	if not current_scene:
		push_error("Cannot spawn Blaze wall without an active scene.")
		return
	AudioManager.play_world_cue(active_audio, start_position)
	var wall := WALL_CONTROLLER_SCENE.instantiate() as Node2D
	wall.name = "BlazeWall_%d_%d" % [owner_peer_id, wall_id]
	wall.add_to_group("skirmish_round_effects")
	current_scene.add_child(wall)
	wall.call(
		"initialize",
		owner_peer_id,
		start_position,
		route,
		grow_duration,
		wall_duration,
		damage_per_second,
		WALL_SEGMENT_SCENE
	)

func _begin_wall_route() -> void:
	route_start_position = _get_muzzle_position()
	wall_route = PackedVector2Array([Vector2.ZERO])
	wall_projectile_position = Vector2.ZERO
	wall_travelled_length = 0.0
	wall_projectile_direction = (
		agent.get_global_mouse_position() - route_start_position
	).normalized()
	if wall_projectile_direction.is_zero_approx():
		wall_projectile_direction = Vector2.RIGHT.rotated(agent.visuals.global_rotation)
	is_drawing_wall = true
	_create_route_preview()
	_update_route_preview()

func _advance_wall_projectile(delta: float) -> void:
	if not is_drawing_wall or wall_route.is_empty():
		return
	var remaining_length := wall_length_meters * METERS_TO_PIXELS - wall_travelled_length
	if remaining_length <= 0.0:
		return
	var target_point := agent.get_global_mouse_position() - route_start_position
	var offset := target_point - wall_projectile_position
	if delta <= 0.0:
		return
	if not offset.is_zero_approx():
		var turn_amount := deg_to_rad(wall_projectile_turn_speed) * delta
		var new_angle := rotate_toward(
			wall_projectile_direction.angle(),
			offset.angle(),
			turn_amount
		)
		wall_projectile_direction = Vector2.RIGHT.rotated(new_angle)
	var travelled_this_frame := minf(
		wall_projectile_speed * delta,
		remaining_length
	)
	wall_projectile_position += wall_projectile_direction * travelled_this_frame
	wall_travelled_length += travelled_this_frame
	var last_route_point: Vector2 = wall_route[-1]
	if (
		last_route_point.distance_to(wall_projectile_position) >= ROUTE_SAMPLE_DISTANCE
		or wall_travelled_length >= wall_length_meters * METERS_TO_PIXELS
	):
		wall_route.append(wall_projectile_position)

func _append_final_wall_point() -> void:
	var target_length := wall_length_meters * METERS_TO_PIXELS
	if wall_route.is_empty():
		wall_route.append(Vector2.ZERO)

	var last_route_point: Vector2 = wall_route[-1]
	if wall_travelled_length > 0.01 and last_route_point.distance_to(wall_projectile_position) > 0.01:
		wall_route.append(wall_projectile_position)

	var route_length := _get_route_length(wall_route)
	if route_length >= target_length:
		return

	var extension_direction := Vector2.ZERO
	if not wall_projectile_direction.is_zero_approx():
		extension_direction = wall_projectile_direction
	elif wall_route.size() >= 2:
		extension_direction = wall_route[-1] - wall_route[-2]
	if extension_direction.is_zero_approx():
		extension_direction = agent.get_global_mouse_position() - route_start_position
	if extension_direction.is_zero_approx():
		extension_direction = Vector2.RIGHT.rotated(agent.visuals.global_rotation)

	wall_route.append(
		wall_route[-1] + extension_direction.normalized() * (target_length - route_length)
	)

func _create_route_preview() -> void:
	var current_scene := get_tree().current_scene
	if not current_scene:
		push_error("Cannot preview Blaze route without an active scene.")
		return
	route_preview_line = Line2D.new()
	route_preview_line.name = "BlazeRoutePreview"
	route_preview_line.add_to_group("skirmish_round_effects")
	route_preview_line.top_level = true
	route_preview_line.width = 2.0
	route_preview_line.default_color = Color(1.0, 0.55, 0.12, 0.95)
	route_preview_line.z_index = 20
	current_scene.add_child(route_preview_line)
	route_preview_line.global_position = route_start_position

	route_preview_orb = Line2D.new()
	route_preview_orb.name = "BlazeProjectilePreview"
	route_preview_orb.add_to_group("skirmish_round_effects")
	route_preview_orb.top_level = true
	route_preview_orb.width = 2.0
	route_preview_orb.default_color = Color(1.0, 0.85, 0.25, 1.0)
	route_preview_orb.z_index = 21
	var orb_points := PackedVector2Array()
	for index in range(PREVIEW_ORB_POINT_COUNT + 1):
		var angle := TAU * float(index) / float(PREVIEW_ORB_POINT_COUNT)
		orb_points.append(Vector2(cos(angle), sin(angle)) * PREVIEW_ORB_RADIUS)
	route_preview_orb.points = orb_points
	current_scene.add_child(route_preview_orb)
	route_preview_orb.global_position = route_start_position

func _update_route_preview() -> void:
	if not is_instance_valid(route_preview_line) or not is_instance_valid(route_preview_orb):
		return
	route_preview_line.points = wall_route
	route_preview_orb.global_position = route_start_position + wall_projectile_position

func _clear_route_preview() -> void:
	if is_instance_valid(route_preview_line):
		route_preview_line.queue_free()
	if is_instance_valid(route_preview_orb):
		route_preview_orb.queue_free()
	route_preview_line = null
	route_preview_orb = null

func _get_route_length(route: PackedVector2Array) -> float:
	var length := 0.0
	for index in range(1, route.size()):
		length += route[index - 1].distance_to(route[index])
	return length

func _is_valid_route(route: PackedVector2Array) -> bool:
	if route.size() < 2 or route.size() > 512 or not route[0].is_zero_approx():
		return false
	for point in route:
		if not point.is_finite():
			return false
	return _get_route_length(route) > 0.01 and _get_route_length(route) <= wall_length_meters * METERS_TO_PIXELS + 0.01

func _set_equipped(equipped: bool) -> void:
	var was_equipped := is_equipped
	is_equipped = equipped
	if equipped and not was_equipped and agent and agent.has_local_authority():
		AudioManager.play_global_cue(cast_audio)
	if not equipped and is_drawing_wall:
		is_drawing_wall = false
		wall_route.clear()
		_clear_route_preview()
	if held_segment:
		if equipped:
			_position_held_segment()
		if held_segment_sprite:
			agent.animate_held_ability_equip(
				held_segment_sprite,
				held_segment_sprite_base_scale,
				equipped
			)
		held_segment.visible = equipped
	if agent and agent.weapon_controller:
		agent.weapon_controller.aiming = false
		agent.weapon_controller.aim_level = 0
		if equipped:
			if agent.weapon_controller.equip_tween:
				agent.weapon_controller.equip_tween.kill()
			agent.weapon_controller.is_equipping = false
			agent.weapon_controller.weapon_sprite.visible = false
		else:
			agent.weapon_controller.update_visual(true)

func _position_held_segment() -> void:
	if not agent or not held_segment:
		return
	var weapon_pivot := agent.get_node_or_null("Visuals/BodySprite/WeaponPivot") as Node2D
	if weapon_pivot:
		held_segment.global_position = weapon_pivot.global_position
		held_segment.global_rotation = weapon_pivot.global_rotation

func _get_muzzle_position() -> Vector2:
	var muzzle := agent.get_node_or_null("Visuals/BodySprite/WeaponPivot/Muzzle") as Marker2D
	return muzzle.global_position if muzzle else agent.global_position
