extends Node

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/agents/phoenix/hot_hands.tscn")
const ZONE_SCENE: PackedScene = preload("res://scenes/agents/phoenix/hot_hands_zone.tscn")
const METERS_TO_PIXELS: float = WeaponData.PIXELS_PER_METER

@export_group("Audio")
@export var cast_audio: AudioCue
@export var throw_audio: AudioCue
@export var active_audio: AudioCue
@export var voice_audio: AudioCue

@export_range(0.1, 50.0, 0.1) var primary_range_meters: float = 25.0
@export_range(0.1, 10.0, 0.1) var primary_flight_time: float = 2.0
@export_range(0.1, 50.0, 0.1) var secondary_range_meters: float = 7.0
@export_range(0.1, 10.0, 0.1) var secondary_flight_time: float = 1.5

var agent: BaseAgent
var held_projectile: Area2D
var held_projectile_sprite: Sprite2D
var held_projectile_sprite_base_scale := Vector2.ONE
var next_cast_id := 0
var cast_pending := false
var is_equipped := false

func reset_for_new_round() -> void:
	cast_pending = false
	_set_equipped(false)

func _ready() -> void:
	agent = get_parent().get_parent() as BaseAgent
	held_projectile = agent.get_node_or_null("Visuals/HotHands") as Area2D
	if not held_projectile:
		push_error("Hot Hands scene instance is missing from the agent scene.")
		return
	held_projectile_sprite = held_projectile.get_node_or_null("Sprite2D") as Sprite2D
	if not held_projectile_sprite:
		push_error("Hot Hands held sprite is missing from the agent scene.")
		return
	held_projectile_sprite_base_scale = held_projectile_sprite.scale
	held_projectile.visible = false
	_position_held_projectile()

func _process(_delta: float) -> void:
	if is_equipped:
		_position_held_projectile()
	if agent and (agent.is_dead or agent.shop_open) and is_equipped:
		_set_equipped(false)

func _input(event: InputEvent) -> void:
	if not agent or not agent.has_local_authority() or agent.is_dead or agent.shop_open or agent.is_match_preparing:
		return

	if not is_equipped or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or (mouse_event.button_index != MOUSE_BUTTON_LEFT and mouse_event.button_index != MOUSE_BUTTON_RIGHT):
		return
	if cast_pending:
		return

	_request_throw(agent.get_global_mouse_position(), mouse_event.button_index == MOUSE_BUTTON_RIGHT)
	get_viewport().set_input_as_handled()

func blocks_weapon_input() -> bool:
	return is_equipped or cast_pending

@rpc("any_peer", "reliable")
func request_equipped_rpc(equipped: bool) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != agent.get_multiplayer_authority() or agent.is_dead or agent.shop_open or agent.is_match_preparing:
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
func request_cast_rpc(target_position: Vector2, throw_to_mouse: bool) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != agent.get_multiplayer_authority():
		return
	var direction := target_position - _get_muzzle_position()
	if not _can_cast(direction):
		cast_rejected_rpc.rpc_id(sender_id)
		return

	_try_server_cast(target_position, throw_to_mouse)

@rpc("any_peer", "call_remote", "reliable")
func cast_rejected_rpc() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	cast_pending = false
	if (
		agent
		and agent.has_local_authority()
		and not agent.is_dead
		and not agent.shop_open
		and agent.has_ability_charge("HotHands")
	):
		_set_equipped(true)

func _can_cast(direction: Vector2) -> bool:
	return (
		agent != null
		and not agent.is_dead
		and not agent.shop_open
		and not agent.is_match_preparing
		and is_equipped
		and agent.has_ability_charge("HotHands")
		and direction.is_finite()
		and not direction.is_zero_approx()
	)

func _request_throw(target_position: Vector2, throw_to_mouse: bool) -> void:
	if cast_pending:
		return
	var direction := target_position - _get_muzzle_position()
	if not _can_cast(direction):
		return

	cast_pending = true
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_cast_rpc.rpc_id(1, target_position, throw_to_mouse)
		_set_equipped(false)
	else:
		_try_server_cast(target_position, throw_to_mouse)

func _try_server_cast(target_position: Vector2, throw_to_mouse: bool) -> void:
	var start_position := _get_muzzle_position()
	var direction := target_position - start_position
	if not _can_cast(direction):
		cast_pending = false
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			cast_rejected_rpc.rpc_id(agent.get_multiplayer_authority())
		return

	if not agent.consume_ability_charge("HotHands"):
		cast_pending = false
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			cast_rejected_rpc.rpc_id(agent.get_multiplayer_authority())
		return
	next_cast_id += 1
	var owner_peer_id := agent.get_multiplayer_authority() if multiplayer.has_multiplayer_peer() else 1
	_play_voice_for_owner(owner_peer_id)
	var max_distance := get_max_distance()
	var direction_normalized := direction.normalized()
	var travel_distance := minf(direction.length(), max_distance) if throw_to_mouse else max_distance
	var flight_time := get_flight_time(travel_distance)
	agent.set_active_ability("")
	_set_equipped(false)
	agent.weapon_controller.suppress_shoot_until_released()
	cast_pending = false
	if multiplayer.has_multiplayer_peer():
		spawn_projectile_rpc.rpc(
			owner_peer_id,
			next_cast_id,
			start_position,
			direction_normalized,
			travel_distance,
			flight_time
		)
	else:
		_spawn_projectile(
			owner_peer_id,
			next_cast_id,
			start_position,
			direction_normalized,
			travel_distance,
			flight_time
		)

func _play_voice_for_owner(owner_peer_id: int) -> void:
	if not multiplayer.has_multiplayer_peer() or owner_peer_id == 1:
		AudioManager.play_global_cue(voice_audio)
	elif multiplayer.is_server():
		play_voice_rpc.rpc_id(owner_peer_id)
	else:
		push_error("Only the server can route Hot Hands voice audio.")

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
func spawn_projectile_rpc(
	owner_peer_id: int,
	cast_id: int,
	start_position: Vector2,
	direction: Vector2,
	travel_distance: float,
	flight_time: float
) -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if multiplayer.is_server():
			if sender_id != 0 and sender_id != 1:
				return
		elif sender_id != 1:
			return

	cast_pending = false
	next_cast_id = maxi(next_cast_id, cast_id)
	_set_equipped(false)
	agent.weapon_controller.suppress_shoot_until_released()
	_spawn_projectile(owner_peer_id, cast_id, start_position, direction, travel_distance, flight_time)

func _spawn_projectile(
	owner_peer_id: int,
	cast_id: int,
	start_position: Vector2,
	direction: Vector2,
	travel_distance: float,
	flight_time: float
) -> void:
	var current_scene := get_tree().current_scene
	if not current_scene:
		push_error("Cannot spawn Hot Hands projectile without an active scene.")
		return
	AudioManager.play_world_cue(throw_audio, start_position)
	var projectile := PROJECTILE_SCENE.instantiate() as Area2D
	projectile.name = "HotHands_%d_%d" % [owner_peer_id, cast_id]
	projectile.add_to_group("skirmish_round_effects")
	current_scene.add_child(projectile)
	projectile.call(
		"initialize",
		owner_peer_id,
		cast_id,
		start_position,
		direction,
		travel_distance,
		flight_time,
		self
	)

func _set_equipped(equipped: bool) -> void:
	var was_equipped := is_equipped
	is_equipped = equipped
	if equipped and not was_equipped and agent and agent.has_local_authority():
		AudioManager.play_global_cue(cast_audio)
	if held_projectile:
		if equipped:
			_position_held_projectile()
		if held_projectile_sprite:
			agent.animate_held_ability_equip(
				held_projectile_sprite,
				held_projectile_sprite_base_scale,
				equipped
			)
		held_projectile.visible = equipped
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

func _position_held_projectile() -> void:
	if not agent or not held_projectile:
		return
	var weapon_pivot := agent.get_node_or_null("Visuals/BodySprite/WeaponPivot") as Node2D
	if not weapon_pivot:
		push_error("Hot Hands cannot follow the agent because its WeaponPivot is missing.")
		return
	held_projectile.global_position = weapon_pivot.global_position
	held_projectile.global_rotation = weapon_pivot.global_rotation

func _get_muzzle_position() -> Vector2:
	var muzzle := agent.get_node_or_null("Visuals/BodySprite/WeaponPivot/Muzzle") as Marker2D
	return muzzle.global_position if muzzle else agent.global_position

func get_max_distance() -> float:
	return primary_range_meters * METERS_TO_PIXELS

func get_flight_time(distance_pixels: float) -> float:
	var distance_meters := distance_pixels / METERS_TO_PIXELS
	return primary_flight_time * clampf(distance_meters / primary_range_meters, 0.0, 1.0)

func spawn_zone(owner_peer_id: int, cast_id: int, zone_position: Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		spawn_zone_rpc.rpc(owner_peer_id, cast_id, zone_position)
	else:
		_spawn_zone(owner_peer_id, cast_id, zone_position)

@rpc("any_peer", "call_local", "reliable")
func spawn_zone_rpc(owner_peer_id: int, cast_id: int, zone_position: Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if multiplayer.is_server():
			if sender_id != 0 and sender_id != 1:
				return
		elif sender_id != 1:
			return
	_spawn_zone(owner_peer_id, cast_id, zone_position)

func _spawn_zone(owner_peer_id: int, cast_id: int, zone_position: Vector2) -> void:
	var current_scene := get_tree().current_scene
	if not current_scene:
		push_error("Cannot spawn Hot Hands zone without an active scene.")
		return

	AudioManager.play_world_cue(active_audio, zone_position)
	var zone := ZONE_SCENE.instantiate() as Area2D
	zone.name = "HotHandsZone_%d_%d" % [owner_peer_id, cast_id]
	zone.add_to_group("skirmish_round_effects")
	current_scene.add_child(zone)
	zone.global_position = zone_position
	zone.call("initialize", owner_peer_id)
