extends Node

const ABILITY_ID := "Tailwind"
const INPUT_ACTION := "ability_slot_3"
const METERS_TO_PIXELS: float = WeaponData.PIXELS_PER_METER
@export_group("Tailwind")
@export_range(0.1, 30.0, 0.1, "suffix:m") var dash_distance_meters: float = 10.0
@export_range(0.1, 20.0, 0.1, "suffix:s") var ready_window: float = 7.5
@export_range(1.0, 2000.0, 1.0, "suffix:px/s") var dash_speed: float = 450.0

@export_group("Audio")
@export var press_audio: AudioCue
@export var active_audio: AudioCue
@export var voice_audio: AudioCue
@export var finish_audio: AudioCue

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var ready_time_remaining := 0.0
var dash_id := 0
var finish_audio_played := false

func reset_for_new_round() -> void:
	ready_time_remaining = 0.0
	finish_audio_played = false
	var hud := _get_local_hud()
	if hud:
		hud.hide_ability_timer()
		hud.hide_jett_dash_effect()

func handle_ability_input(event: InputEvent, input_action: String) -> bool:
	if input_action != INPUT_ACTION:
		return false
	if event is InputEventKey and (event as InputEventKey).echo:
		return true
	if not event.is_action_pressed(input_action):
		return false
	if ready_time_remaining > 0.0:
		_request_dash()
	else:
		_request_ready()
	return true

func _process(delta: float) -> void:
	if ready_time_remaining <= 0.0:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if agent.is_dead or agent.shop_open or agent.is_lobby_locked or agent.is_match_preparing:
		_end_ready_window()
		return
	ready_time_remaining = maxf(ready_time_remaining - delta, 0.0)
	if not finish_audio_played and _should_play_finish_audio():
		finish_audio_played = true
		_play_finish_audio_for_owner()
	if ready_time_remaining <= 0.0:
		_end_ready_window()

func _request_ready() -> void:
	if not _can_start():
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_ready_rpc.rpc_id(1)
	else:
		_start_ready_window()

func _can_start() -> bool:
	return (
		agent and agent.has_local_authority() and _can_start_authoritatively()
	)

func _can_start_authoritatively() -> bool:
	return (
		agent and not agent.is_dead and not agent.shop_open
		and not agent.is_lobby_locked and not agent.is_match_preparing
		and ready_time_remaining <= 0.0 and agent.has_ability_charge(ABILITY_ID)
	)

func _start_ready_window() -> void:
	if not agent or agent.is_dead or agent.shop_open or agent.is_lobby_locked or agent.is_match_preparing:
		return
	if ready_time_remaining > 0.0 or not agent.consume_ability_charge(ABILITY_ID):
		return
	ready_time_remaining = ready_window
	finish_audio_played = false
	if multiplayer.has_multiplayer_peer():
		sync_ready_rpc.rpc(agent.get_multiplayer_authority(), ready_window)
	else:
		_show_ready_effect(ready_window)

func _request_dash() -> void:
	if not agent or not agent.has_local_authority() or agent.is_match_preparing or ready_time_remaining <= 0.0:
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction.is_zero_approx():
		direction = Vector2.RIGHT.rotated(agent.global_rotation + agent.visuals.rotation)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_dash_rpc.rpc_id(1, direction.normalized())
	else:
		_perform_authoritative_dash(direction.normalized())

func _perform_authoritative_dash(direction: Vector2) -> void:
	if (
		not agent
		or agent.is_dead
		or agent.shop_open
		or agent.is_lobby_locked
		or agent.is_match_preparing
		or ready_time_remaining <= 0.0
	):
		return
	if direction.is_zero_approx() or not direction.is_finite():
		return
	var dash_motion := _get_dash_motion(direction.normalized())
	if dash_motion.is_zero_approx():
		return
	_play_dash_audio()
	ready_time_remaining = 0.0
	var new_dash_id := dash_id + 1
	var start_position := agent.global_position
	var destination := start_position + dash_motion
	if multiplayer.has_multiplayer_peer():
		sync_dash_rpc.rpc(agent.get_multiplayer_authority(), new_dash_id, start_position, destination)
	else:
		_apply_dash(new_dash_id, start_position, destination)
	var hud := _get_local_hud()
	if hud:
		hud.hide_ability_timer()
		hud.hide_jett_dash_effect()

func _get_dash_motion(direction: Vector2) -> Vector2:
	var updraft_active := _is_updraft_active()
	var query := PhysicsRayQueryParameters2D.create(
		agent.global_position,
		agent.global_position + direction * get_dash_distance_pixels()
	)
	var excluded_rids: Array[RID] = []
	excluded_rids.append(agent.get_rid())
	if updraft_active:
		for node in get_tree().get_nodes_in_group(&"updraft_traversable"):
			var body := node as CollisionObject2D
			if body:
				excluded_rids.append(body.get_rid())
	query.exclude = excluded_rids
	var space_state := agent.get_world_2d().direct_space_state
	var collision := space_state.intersect_ray(query)
	while not collision.is_empty() and _dash_can_pass_one_way(collision, direction):
		var collider := collision.get("collider") as CollisionObject2D
		if not collider:
			break
		excluded_rids.append(collider.get_rid())
		query.exclude = excluded_rids
		collision = space_state.intersect_ray(query)
	if collision.is_empty():
		return direction * get_dash_distance_pixels()
	var safe_distance := maxf(agent.global_position.distance_to(collision.position) - 8.0, 0.0)
	return direction * minf(get_dash_distance_pixels(), safe_distance)

func _is_updraft_active() -> bool:
	var updraft := agent.get_node_or_null("Components/UpdraftAbility") as Node
	return updraft != null and updraft.has_method("is_active") and updraft.is_active()

func _dash_can_pass_one_way(collision: Dictionary, dash_direction: Vector2) -> bool:
	var collider := collision.get("collider") as CollisionObject2D
	if not collider:
		return false
	var shape_index := int(collision.get("shape", -1))
	if shape_index < 0:
		return false
	var owner_id := collider.shape_find_owner(shape_index)
	var hit_shape := collider.shape_owner_get_owner(owner_id) as CollisionShape2D
	if not hit_shape or not hit_shape.one_way_collision:
		return false
	var world_normal := hit_shape.global_transform.basis_xform(
		hit_shape.one_way_collision_direction
	).normalized()
	if dash_direction.dot(world_normal) > 0.0:
		return false
	# Skipping a body is safe only when all its collision shapes are one-way.
	# Mixed solid/one-way bodies must remain dash blockers.
	var found_shape := false
	for shape_owner_id in collider.get_shape_owners():
		var owner_shape := collider.shape_owner_get_owner(shape_owner_id) as CollisionShape2D
		if not owner_shape:
			continue
		found_shape = true
		if not owner_shape.one_way_collision:
			return false
	return found_shape

func get_dash_distance_pixels() -> float:
	return dash_distance_meters * METERS_TO_PIXELS

func _apply_dash(new_dash_id: int, start_position: Vector2, destination: Vector2) -> void:
	if new_dash_id <= dash_id or not start_position.is_finite() or not destination.is_finite() or not agent:
		return
	if start_position.distance_to(destination) < 1.0:
		return
	dash_id = new_dash_id
	ready_time_remaining = 0.0
	
	var dash_distance := start_position.distance_to(destination)
	var dash_duration := dash_distance / dash_speed
	var hud := _get_local_hud()
	if hud:
		hud.hide_ability_timer()
		hud.hide_jett_dash_effect()
	if multiplayer.has_multiplayer_peer() and not agent.is_multiplayer_authority():
		return
	agent.is_movement_locked = true
	agent.global_position = start_position
	var collision_shape := agent.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var original_collision_layer := agent.collision_layer
	var original_collision_mask := agent.collision_mask
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	agent.collision_layer = 0
	agent.collision_mask = 0
	var dash_tween := agent.create_tween()
	dash_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	dash_tween.set_trans(Tween.TRANS_LINEAR)
	dash_tween.tween_method(func(progress: float) -> void:
		if is_instance_valid(agent):
			agent.global_position = start_position.lerp(destination, progress)
	, 0.0, 1.0, dash_duration)
	dash_tween.tween_callback(func() -> void:
		_finish_dash(original_collision_layer, original_collision_mask, collision_shape)
	)

func _finish_dash(
	original_collision_layer: int,
	original_collision_mask: int,
	collision_shape: CollisionShape2D
) -> void:
	if is_instance_valid(agent):
		agent.velocity = Vector2.ZERO
		agent.collision_layer = original_collision_layer
		agent.collision_mask = original_collision_mask
		if collision_shape and is_instance_valid(collision_shape):
			collision_shape.set_deferred("disabled", false)
		agent.is_movement_locked = false

func _end_ready_window() -> void:
	ready_time_remaining = 0.0
	var hud := _get_local_hud()
	if hud:
		hud.hide_ability_timer()
		hud.hide_jett_dash_effect()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_ready_ended_rpc.rpc(agent.get_multiplayer_authority())

func _show_ready_effect(duration: float) -> void:
	if press_audio and press_audio.stream:
		AudioManager.play_local_cue(press_audio, &"jett_tailwind_press")
	var hud := _get_local_hud()
	if hud:
		hud.start_ability_timer("PRESS AGAIN TO DASH", duration)
		hud.show_jett_dash_effect()

func _play_active_audio() -> void:
	if active_audio and active_audio.stream:
		AudioManager.play_world_cue(active_audio, agent.global_position)
	if agent.has_local_authority() and voice_audio and voice_audio.stream:
		AudioManager.play_local_cue(voice_audio, &"jett_tailwind_voice")

func _should_play_finish_audio() -> bool:
	if not finish_audio or not finish_audio.stream:
		return false
	var audio_duration := finish_audio.stream.get_length()
	return audio_duration > 0.0 and ready_time_remaining <= audio_duration

func _play_finish_audio_for_owner() -> void:
	if multiplayer.has_multiplayer_peer():
		sync_finish_audio_rpc.rpc(agent.get_multiplayer_authority())
	elif agent.has_local_authority() and finish_audio and finish_audio.stream:
		AudioManager.play_local_cue(finish_audio, &"jett_tailwind_finish")

func _get_local_hud() -> GameHud:
	var scene := get_tree().current_scene
	if not scene:
		return null
	var hud := scene.get_node_or_null("HUD") as GameHud
	if not hud:
		hud = scene.find_child("GameHud", true, false) as GameHud
	if hud and hud.player == agent:
		return hud
	return null

@rpc("any_peer", "reliable")
func request_ready_rpc() -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if (
		multiplayer.get_remote_sender_id() != agent.get_multiplayer_authority()
		or not _can_start_authoritatively()
	):
		return
	_start_ready_window()

@rpc("any_peer", "call_local", "reliable")
func sync_ready_rpc(owner_peer_id: int, duration: float) -> void:
	if not _rpc_is_from_server():
		return
	if agent.is_match_preparing:
		ready_time_remaining = 0.0
		return
	if owner_peer_id != agent.get_multiplayer_authority() or duration <= 0.0 or duration > ready_window:
		return
	ready_time_remaining = duration
	finish_audio_played = false
	if multiplayer.has_multiplayer_peer() and not agent.has_local_authority():
		return
	_show_ready_effect(duration)

@rpc("any_peer", "call_local", "reliable")
func sync_finish_audio_rpc(owner_peer_id: int) -> void:
	if not _rpc_is_from_server():
		return
	if owner_peer_id != agent.get_multiplayer_authority() or not agent.has_local_authority():
		return
	if finish_audio and finish_audio.stream:
		AudioManager.play_local_cue(finish_audio, &"jett_tailwind_finish")

@rpc("any_peer", "reliable")
func request_dash_rpc(direction: Vector2) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != agent.get_multiplayer_authority() or agent.is_match_preparing or ready_time_remaining <= 0.0:
		return
	_perform_authoritative_dash(direction)

func _play_dash_audio() -> void:
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			sync_dash_audio_rpc.rpc(agent.get_multiplayer_authority())
	else:
		_play_active_audio()

@rpc("any_peer", "call_local", "reliable")
func sync_dash_audio_rpc(owner_peer_id: int) -> void:
	if not _rpc_is_from_server():
		return
	if owner_peer_id != agent.get_multiplayer_authority():
		return
	_play_active_audio()

@rpc("any_peer", "call_local", "reliable")
func sync_dash_rpc(
	owner_peer_id: int,
	new_dash_id: int,
	start_position: Vector2,
	destination: Vector2
) -> void:
	if not _rpc_is_from_server():
		return
	if (
		owner_peer_id != agent.get_multiplayer_authority()
		or agent.is_match_preparing
		or not start_position.is_finite()
		or not destination.is_finite()
		or start_position.distance_to(destination) > get_dash_distance_pixels() + 0.01
	):
		return
	_apply_dash(new_dash_id, start_position, destination)

@rpc("any_peer", "call_local", "reliable")
func sync_ready_ended_rpc(owner_peer_id: int) -> void:
	if not _rpc_is_from_server():
		return
	if owner_peer_id != agent.get_multiplayer_authority():
		return
	ready_time_remaining = 0.0
	var hud := _get_local_hud()
	if hud:
		hud.hide_ability_timer()
		hud.hide_jett_dash_effect()

func _rpc_is_from_server() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	var sender_id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		return sender_id == 0 or sender_id == 1
	return sender_id == 1
