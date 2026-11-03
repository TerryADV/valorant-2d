extends Node

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/agents/sage/orb.tscn")
const ZONE_SCENE: PackedScene = preload("res://scenes/agents/sage/slow_orb.tscn")
const ABILITY_ID := "SlowOrb"
const MAX_RANGE := 40.0 * WeaponData.PIXELS_PER_METER
const THROW_SPEED := 20.0 * WeaponData.PIXELS_PER_METER

@export_group("Audio")
@export var cast_audio: AudioCue
@export var throw_audio: AudioCue
@export var voice_audio: AudioCue
@export var active_audio: AudioCue

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var cast_pending := false
var next_projectile_id := 0

func handle_ability_input(event: InputEvent, input_action: String) -> bool:
	if not event.is_action_pressed(input_action):
		return false
	if event is InputEventKey and (event as InputEventKey).echo:
		return true
	if agent.active_ability_name != ABILITY_ID:
		var orb_ability := agent.get_node_or_null("Components/SageOrbAbility")
		if orb_ability and orb_ability.has_method("activate_ability"):
			if bool(orb_ability.call("activate_ability", ABILITY_ID)):
				AudioManager.play_local_cue(cast_audio, &"sage_slow_orb_cast")
	get_viewport().set_input_as_handled()
	return true

func _input(event: InputEvent) -> void:
	if (
		not agent
		or not agent.has_local_authority()
		or agent.is_dead
		or agent.is_match_preparing
		or agent.shop_open
		or agent.active_ability_name != ABILITY_ID
		or cast_pending
	):
		return
	var orb_ability := agent.get_node_or_null("Components/SageOrbAbility")
	if orb_ability and bool(orb_ability.get("is_appearing")):
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT and mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return
	_request_throw(agent.get_global_mouse_position(), mouse_event.button_index == MOUSE_BUTTON_RIGHT)
	get_viewport().set_input_as_handled()

func blocks_weapon_input() -> bool:
	return cast_pending or (agent != null and agent.active_ability_name == ABILITY_ID)

func reset_for_new_round() -> void:
	cast_pending = false

@rpc("any_peer", "reliable")
func request_throw_rpc(target_position: Vector2, throw_to_mouse: bool) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var aim_offset := target_position - _get_start_position()
	if (
		sender_id != agent.get_multiplayer_authority()
		or agent.is_dead
		or agent.is_match_preparing
		or agent.shop_open
		or agent.active_ability_name != ABILITY_ID
		or not target_position.is_finite()
		or aim_offset.is_zero_approx()
		or not aim_offset.is_finite()
		or (throw_to_mouse and aim_offset.length() > MAX_RANGE + 1.0)
		or not agent.has_ability_charge(ABILITY_ID)
	):
		throw_rejected_rpc.rpc_id(sender_id)
		return
	_try_server_throw(target_position, throw_to_mouse)

@rpc("any_peer", "call_remote", "reliable")
func throw_rejected_rpc() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() == 1 and agent.has_local_authority():
		cast_pending = false

func _request_throw(target_position: Vector2, throw_to_mouse: bool) -> void:
	if cast_pending:
		return
	var aim_offset := target_position - _get_start_position()
	if aim_offset.is_zero_approx() or not aim_offset.is_finite():
		return
	cast_pending = true
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_throw_rpc.rpc_id(1, target_position, throw_to_mouse)
	else:
		_try_server_throw(target_position, throw_to_mouse)

func _try_server_throw(target_position: Vector2, throw_to_mouse: bool) -> void:
	var start_position := _get_start_position()
	var aim_offset := target_position - start_position
	if (
		agent.is_dead
		or agent.shop_open
		or agent.active_ability_name != ABILITY_ID
		or aim_offset.is_zero_approx()
		or not aim_offset.is_finite()
		or (throw_to_mouse and aim_offset.length() > MAX_RANGE + 1.0)
		or not agent.consume_ability_charge(ABILITY_ID)
	):
		cast_pending = false
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			throw_rejected_rpc.rpc_id(agent.get_multiplayer_authority())
		return
	var direction := aim_offset.normalized()
	var travel_distance := aim_offset.length() if throw_to_mouse else MAX_RANGE
	travel_distance = minf(travel_distance, MAX_RANGE)
	cast_pending = false
	agent.set_active_ability("")
	var owner_peer_id := agent.get_multiplayer_authority() if multiplayer.has_multiplayer_peer() else 1
	next_projectile_id += 1
	if multiplayer.has_multiplayer_peer():
		spawn_projectile_rpc.rpc(
			owner_peer_id,
			next_projectile_id,
			start_position,
			direction,
			travel_distance,
			THROW_SPEED
		)
	else:
		_spawn_projectile(
			owner_peer_id, next_projectile_id, start_position, direction, travel_distance, THROW_SPEED
		)
		_return_to_weapon()

@rpc("any_peer", "call_local", "reliable")
func spawn_projectile_rpc(
	owner_peer_id: int,
	projectile_id: int,
	start_position: Vector2,
	direction: Vector2,
	travel_distance: float,
	throw_speed: float
) -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if (multiplayer.is_server() and sender_id != 0 and sender_id != 1) or (not multiplayer.is_server() and sender_id != 1):
			return
	if (
		owner_peer_id != agent.get_multiplayer_authority()
		or projectile_id <= 0
		or not start_position.is_finite()
		or direction.is_zero_approx()
		or not direction.is_finite()
		or travel_distance <= 0.0
		or travel_distance > MAX_RANGE + 1.0
		or not is_equal_approx(throw_speed, THROW_SPEED)
	):
		return
	cast_pending = false
	next_projectile_id = maxi(next_projectile_id, projectile_id)
	_spawn_projectile(owner_peer_id, projectile_id, start_position, direction, travel_distance, throw_speed)
	_return_to_weapon()

func _return_to_weapon() -> void:
	if not agent.has_local_authority():
		return
	var weapon_controller = agent.weapon_controller
	if not weapon_controller or not weapon_controller.current_weapon:
		return
	weapon_controller.suppress_shoot_until_released()
	weapon_controller.select_weapon_slot(weapon_controller.current_weapon_slot, false, true)

func _spawn_projectile(
	owner_peer_id: int,
	projectile_id: int,
	start_position: Vector2,
	direction: Vector2,
	travel_distance: float,
	throw_speed: float
) -> void:
	var current_scene := get_tree().current_scene
	if not current_scene:
		return
	var projectile := PROJECTILE_SCENE.instantiate() as Area2D
	projectile.name = "SageSlowOrb_%d_%d" % [owner_peer_id, projectile_id]
	projectile.add_to_group("skirmish_round_effects")
	current_scene.add_child(projectile)
	projectile.call(
		"initialize", owner_peer_id, start_position, direction, travel_distance, throw_speed, self
	)
	AudioManager.play_world_cue(throw_audio, start_position)
	if agent.has_local_authority():
		AudioManager.play_local_cue(voice_audio, &"sage_slow_orb_voice")

func spawn_zone(owner_peer_id: int, zone_position: Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			spawn_zone_rpc.rpc(owner_peer_id, zone_position)
		return
	_spawn_zone(owner_peer_id, zone_position)

@rpc("any_peer", "call_local", "reliable")
func spawn_zone_rpc(owner_peer_id: int, zone_position: Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if (multiplayer.is_server() and sender_id != 0 and sender_id != 1) or (not multiplayer.is_server() and sender_id != 1):
			return
	if (
		owner_peer_id != agent.get_multiplayer_authority()
		or not zone_position.is_finite()
	):
		return
	_spawn_zone(owner_peer_id, zone_position)

func _spawn_zone(owner_peer_id: int, zone_position: Vector2) -> void:
	var current_scene := get_tree().current_scene
	if not current_scene:
		return
	var zone := ZONE_SCENE.instantiate() as Area2D
	zone.name = "SageSlowOrbZone_%d_%d" % [owner_peer_id, next_projectile_id]
	zone.add_to_group("skirmish_round_effects")
	current_scene.add_child(zone)
	zone.global_position = zone_position
	AudioManager.play_world_cue(active_audio, zone_position)

func _get_start_position() -> Vector2:
	var weapon_pivot := agent.get_node_or_null("Visuals/BodySprite/WeaponPivot") as Node2D
	return weapon_pivot.global_position if weapon_pivot else agent.global_position
