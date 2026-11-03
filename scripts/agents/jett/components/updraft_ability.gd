extends Node

const ABILITY_ID := "Updraft"
@export_group("Updraft")
@export var traversable_group: StringName = &"updraft_traversable"

@export_range(0.1, 3.0, 0.05) var duration: float = 1.5
@export_range(0.1, 1.0, 0.05) var collision_scale: float = 0.5
@export_range(0.0, 30.0, 0.25, "suffix:°") var weapon_spread_degrees: float = 5.0
@export_range(1.0, 4.0, 0.1, "suffix:x") var weapon_recoil_multiplier: float = 1.5

@export_group("Audio")
@export var updraft_audio: AudioCue
@export var voice_audio: AudioCue

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var activation_id := 0
var active_activation_id := -1
var remaining_duration := 0.0
var pending_activation_recoil := false
var original_collision_shape_scale := Vector2.ONE
var collision_exceptions_added: Array[PhysicsBody2D] = []
var hidden_traversable_occluders: Dictionary = {}

func _ready() -> void:
	var collision_shape := _get_agent_collision_shape()
	if not collision_shape:
		push_error("BaseAgent is missing CollisionShape2D required by Updraft.")
		return
	original_collision_shape_scale = collision_shape.scale

func _exit_tree() -> void:
	_restore_activation()
	_remove_all_traversable_collision_exceptions()
	_restore_traversable_occluders()

func reset_for_new_round() -> void:
	_restore_activation()
	_remove_all_traversable_collision_exceptions()
	_restore_traversable_occluders()
	pending_activation_recoil = false

func handle_ability_input(event: InputEvent, input_action: String) -> bool:
	if not event.is_action_pressed(input_action):
		return false
	if event is InputEventKey and (event as InputEventKey).echo:
		return true
	_request_activation()
	return true

func _process(delta: float) -> void:
	_restore_cleared_traversable_collision_exceptions()
	if active_activation_id < 0:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if agent.is_dead or agent.shop_open or agent.is_lobby_locked or agent.is_match_preparing:
		_finish_activation()
		if agent.is_dead:
			_remove_all_traversable_collision_exceptions()
		return
	remaining_duration -= delta
	if remaining_duration <= 0.0:
		_finish_activation()

func _request_activation() -> void:
	if not _can_activate():
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		pending_activation_recoil = true
		request_activation_rpc.rpc_id(1)
		return
	_start_authoritative_activation()

func _can_activate() -> bool:
	return (
		agent
		and agent.has_local_authority()
		and not agent.is_dead
		and not agent.shop_open
		and not agent.is_lobby_locked
		and not agent.is_match_preparing
		and active_activation_id < 0
		and agent.has_ability_charge(ABILITY_ID)
	)

func _start_authoritative_activation() -> void:
	if (
		not agent
		or agent.is_dead
		or agent.shop_open
		or agent.is_lobby_locked
		or agent.is_match_preparing
		or active_activation_id >= 0
		or not agent.has_ability_charge(ABILITY_ID)
	):
		return
	if not agent.consume_ability_charge(ABILITY_ID):
		return

	activation_id += 1
	if active_activation_id < 0:
		_apply_activation(activation_id)
	if multiplayer.has_multiplayer_peer():
		sync_activation_started_rpc.rpc(agent.get_multiplayer_authority(), activation_id)

func _finish_activation() -> void:
	if active_activation_id < 0:
		return
	var finished_id := active_activation_id
	_restore_activation()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_activation_finished_rpc.rpc(agent.get_multiplayer_authority(), finished_id)

func _apply_activation(new_activation_id: int) -> void:
	if new_activation_id < active_activation_id or (new_activation_id == active_activation_id and active_activation_id >= 0):
		return
	var collision_shape := _get_agent_collision_shape()
	if not collision_shape:
		push_error("Cannot activate Updraft without the agent CollisionShape2D.")
		return

	active_activation_id = new_activation_id
	pending_activation_recoil = false
	activation_id = maxi(activation_id, new_activation_id)
	remaining_duration = duration
	if updraft_audio and updraft_audio.stream:
		AudioManager.play_world_cue(updraft_audio, agent.global_position)
	if agent.has_local_authority() and voice_audio and voice_audio.stream:
		AudioManager.play_local_cue(voice_audio, &"jett_updraft_voice")
	original_collision_shape_scale = collision_shape.scale
	collision_shape.scale = original_collision_shape_scale * collision_scale
	_add_traversable_collision_exceptions()
	_hide_traversable_occluders()

func _restore_activation() -> void:
	if active_activation_id < 0:
		return
	active_activation_id = -1
	remaining_duration = 0.0
	var collision_shape := _get_agent_collision_shape()
	if collision_shape:
		collision_shape.scale = original_collision_shape_scale
	_restore_cleared_traversable_collision_exceptions()

func _add_traversable_collision_exceptions() -> void:
	collision_exceptions_added.clear()
	for node in get_tree().get_nodes_in_group(traversable_group):
		var body := node as PhysicsBody2D
		if not body or agent.get_collision_exceptions().has(body):
			continue
		agent.add_collision_exception_with(body)
		collision_exceptions_added.append(body)

func _restore_cleared_traversable_collision_exceptions(force: bool = false) -> void:
	# Keep the entire traversable set disabled for the whole Updraft window.
	# Restoring a body as soon as Jett clears it can block her against a second
	# object directly behind it before she has reached that object.
	if not force and active_activation_id >= 0:
		return
	if not force:
		if _agent_overlaps_any_traversable_body():
			return
	_remove_all_traversable_collision_exceptions()
	_restore_traversable_occluders()

func _agent_overlaps_any_traversable_body() -> bool:
	for node in get_tree().get_nodes_in_group(traversable_group):
		var body := node as PhysicsBody2D
		if body and _agent_overlaps_body(body):
			return true
	return false

func _remove_all_traversable_collision_exceptions() -> void:
	for body in collision_exceptions_added:
		if is_instance_valid(body) and is_instance_valid(agent):
			agent.remove_collision_exception_with(body)
	collision_exceptions_added.clear()

func _agent_overlaps_body(body: PhysicsBody2D) -> bool:
	var collision_shape := _get_agent_collision_shape()
	if not collision_shape or not collision_shape.shape or body.collision_layer == 0:
		return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	# Keep the exception until the agent's normal-sized collider clears the body.
	# During Updraft the CollisionShape2D is scaled down, which otherwise makes
	# this check restore collision while the agent is still passing through.
	if not is_zero_approx(collision_shape.scale.x) and not is_zero_approx(collision_shape.scale.y):
		query.transform = query.transform.scaled_local(
			original_collision_shape_scale / collision_shape.scale
		)
	query.collision_mask = body.collision_layer
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [agent.get_rid()]
	for result in agent.get_world_2d().direct_space_state.intersect_shape(query, 64):
		if result.get("collider") == body:
			return true
	return false

func _hide_traversable_occluders() -> void:
	if not agent.has_local_authority():
		return
	hidden_traversable_occluders.clear()
	for node in get_tree().get_nodes_in_group(traversable_group):
		var body := node as Node
		if not body:
			continue
		for child in body.find_children("*", "LightOccluder2D", true, false):
			var occluder := child as LightOccluder2D
			if occluder and occluder.visible:
				hidden_traversable_occluders[occluder] = true
				occluder.visible = false

func _restore_traversable_occluders() -> void:
	for node in hidden_traversable_occluders:
		var occluder := node as LightOccluder2D
		if is_instance_valid(occluder):
			occluder.visible = bool(hidden_traversable_occluders[node])
	hidden_traversable_occluders.clear()

func _get_agent_collision_shape() -> CollisionShape2D:
	return agent.get_node_or_null("CollisionShape2D") as CollisionShape2D

func get_weapon_recoil_multiplier() -> float:
	return weapon_recoil_multiplier if active_activation_id >= 0 or pending_activation_recoil else 1.0

func is_active() -> bool:
	return active_activation_id >= 0

func is_overlapping_traversable_body(body: PhysicsBody2D) -> bool:
	return (
		body != null
		and body.is_in_group(traversable_group)
		and _agent_overlaps_body(body)
	)

func get_weapon_spread_degrees() -> float:
	return weapon_spread_degrees if active_activation_id >= 0 or pending_activation_recoil else 0.0

@rpc("any_peer", "reliable")
func request_activation_rpc() -> void:
	if (
		not multiplayer.has_multiplayer_peer()
		or not multiplayer.is_server()
		or multiplayer.get_remote_sender_id() != agent.get_multiplayer_authority()
	):
		return
	if (
		agent.is_dead
		or agent.shop_open
		or agent.is_lobby_locked
		or agent.is_match_preparing
		or active_activation_id >= 0
		or not agent.has_ability_charge(ABILITY_ID)
	):
		activation_rejected_rpc.rpc_id(agent.get_multiplayer_authority())
		return
	_start_authoritative_activation()

@rpc("authority", "call_remote", "reliable")
func activation_rejected_rpc() -> void:
	if (
		not multiplayer.has_multiplayer_peer()
		or multiplayer.is_server()
		or multiplayer.get_remote_sender_id() != 1
		or not agent.has_local_authority()
	):
		return
	pending_activation_recoil = false

@rpc("any_peer", "call_local", "reliable")
func sync_activation_started_rpc(owner_peer_id: int, new_activation_id: int) -> void:
	if not _rpc_is_from_server():
		return
	if (
		owner_peer_id != agent.get_multiplayer_authority()
		or new_activation_id <= 0
		or agent.is_dead
		or agent.is_match_preparing
	):
		return
	_apply_activation(new_activation_id)

@rpc("any_peer", "call_local", "reliable")
func sync_activation_finished_rpc(owner_peer_id: int, finished_activation_id: int) -> void:
	if not _rpc_is_from_server():
		return
	if (
		owner_peer_id != agent.get_multiplayer_authority()
		or active_activation_id != finished_activation_id
	):
		return
	_restore_activation()

func _rpc_is_from_server() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	var sender_id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		return sender_id == 0 or sender_id == 1
	return sender_id == 1
