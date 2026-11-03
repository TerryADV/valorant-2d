extends Node

const ABILITY_ID := "Cloudburst"
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/agents/jett/cloud_burst.tscn")
@export_group("Cloudburst")
@export_range(0.01, 0.5, 0.01, "suffix:s") var aim_update_interval: float = 0.05
@export_range(1.0, 256.0, 1.0, "suffix:px") var max_start_distance: float = 64.0

@export_group("Audio")
@export var keep_audio: AudioCue
@export var smoke_audio: AudioCue
@export var voice_audio_1: AudioCue
@export var voice_audio_2: AudioCue

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var next_cast_id := 0
var held_cast_id := -1
var input_is_held := false
var aim_update_timer := 0.0
var projectiles: Dictionary = {}

func reset_for_new_round() -> void:
	input_is_held = false
	held_cast_id = -1
	aim_update_timer = 0.0
	projectiles.clear()

func handle_ability_input(event: InputEvent, input_action: String) -> bool:
	if not event.is_action_pressed(input_action) and not event.is_action_released(input_action):
		return false
	if event is InputEventKey and (event as InputEventKey).echo:
		return true

	if event.is_action_pressed(input_action):
		if input_is_held or not _can_start_cast():
			return true
		input_is_held = true
		_play_cast_audio_locally()
		agent.set_active_ability(ABILITY_ID)
		_start_cast()
	elif input_is_held:
		input_is_held = false
		_release_cast()
		agent.set_active_ability("")
	return true

func _process(delta: float) -> void:
	if not input_is_held or not agent.has_local_authority():
		return
	if (
		agent.is_dead
		or agent.is_match_preparing
		or agent.shop_open
		or agent.agent_select_open
		or not Input.is_action_pressed("ability_slot_1")
	):
		input_is_held = false
		_release_cast()
		agent.set_active_ability("")
		return
	if held_cast_id < 0:
		return

	var projectile := projectiles.get(held_cast_id) as Node2D
	if not projectile:
		return
	var direction := agent.get_global_mouse_position() - agent.global_position
	if direction.is_zero_approx() or not direction.is_finite():
		return
	direction = direction.normalized()
	projectile.call("set_movement_direction", direction)

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		aim_update_timer -= delta
		if aim_update_timer <= 0.0:
			request_aim_rpc.rpc_id(1, held_cast_id, direction)
			aim_update_timer = aim_update_interval

func blocks_weapon_input() -> bool:
	return input_is_held

func _play_cast_audio_locally() -> void:
	if keep_audio and keep_audio.stream:
		AudioManager.play_local_cue(keep_audio, &"jett_cloudburst_keep")
	var voice_cue := voice_audio_1 if randi_range(0, 1) == 0 else voice_audio_2
	if voice_cue and voice_cue.stream:
		AudioManager.play_local_cue(voice_cue, &"jett_cloudburst_voice")

func _can_start_cast() -> bool:
	return (
		agent
		and agent.has_local_authority()
		and not agent.is_dead
		and not agent.is_match_preparing
		and not agent.shop_open
		and not agent.agent_select_open
		and held_cast_id < 0
		and agent.has_ability_charge(ABILITY_ID)
	)

func _start_cast() -> void:
	var muzzle := agent.get_node_or_null(
		"Visuals/BodySprite/WeaponPivot/Muzzle"
	) as Marker2D
	if not muzzle:
		push_error("Jett is missing the weapon muzzle needed to launch Cloudburst.")
		input_is_held = false
		agent.set_active_ability("")
		return
	var direction := agent.get_global_mouse_position() - agent.global_position
	if direction.is_zero_approx() or not direction.is_finite():
		direction = Vector2.RIGHT.rotated(muzzle.global_rotation)
	direction = direction.normalized()
	next_cast_id += 1
	held_cast_id = next_cast_id
	aim_update_timer = 0.0

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_start_cast_rpc.rpc_id(1, held_cast_id, direction)
		return
	_start_authoritative_cast(held_cast_id, _get_muzzle_position(), direction)

func _get_muzzle_position() -> Vector2:
	var muzzle := agent.get_node_or_null(
		"Visuals/BodySprite/WeaponPivot/Muzzle"
	) as Marker2D
	return muzzle.global_position if muzzle else agent.global_position

func _start_authoritative_cast(
	cast_id: int,
	start_position: Vector2,
	direction: Vector2
) -> void:
	if (
		not agent
		or agent.is_dead
		or agent.is_match_preparing
		or agent.shop_open
		or not agent.has_ability_charge(ABILITY_ID)
		or not direction.is_finite()
		or direction.is_zero_approx()
		or not start_position.is_finite()
		or start_position.distance_to(agent.global_position) > max_start_distance
		or (held_cast_id >= 0 and held_cast_id != cast_id)
	):
		_reject_cast(agent.get_multiplayer_authority())
		return
	var current_scene := get_tree().current_scene
	if not current_scene:
		push_error("Cannot launch Cloudburst without an active scene.")
		_reject_cast(agent.get_multiplayer_authority())
		return
	if not agent.consume_ability_charge(ABILITY_ID):
		_reject_cast(agent.get_multiplayer_authority())
		return

	next_cast_id = maxi(next_cast_id, cast_id)
	held_cast_id = cast_id
	if multiplayer.has_multiplayer_peer():
		spawn_cloudburst_rpc.rpc(
			agent.get_multiplayer_authority(),
			cast_id,
			start_position,
			direction.normalized()
		)
	else:
		_spawn_cloudburst(
			agent.get_multiplayer_authority(),
			cast_id,
			start_position,
			direction.normalized()
		)

func _release_cast() -> void:
	if held_cast_id < 0:
		return
	var cast_id := held_cast_id
	var final_direction := agent.get_global_mouse_position() - agent.global_position
	if not final_direction.is_zero_approx() and final_direction.is_finite():
		final_direction = final_direction.normalized()
	else:
		final_direction = Vector2.RIGHT
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_detonate_rpc.rpc_id(1, cast_id, final_direction)
	elif multiplayer.has_multiplayer_peer():
		_detonate_cast(cast_id, final_direction)
	else:
		var projectile := projectiles.get(cast_id) as Node2D
		if projectile:
			projectile.call("detonate_at_current_position", final_direction)

func _detonate_cast(cast_id: int, final_direction: Vector2) -> void:
	if held_cast_id != cast_id:
		return
	var projectile := projectiles.get(cast_id) as Node2D
	if projectile:
		projectile.call("detonate_at_current_position", final_direction)

func broadcast_cloudburst_detonation(cast_id: int, smoke_position: Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		if not multiplayer.is_server():
			return
	var projectile := projectiles.get(cast_id) as Node2D
	if not projectile:
		push_warning("Cannot detonate Cloudburst because its projectile is missing.")
		return
	projectile.call("enter_smoke", smoke_position)
	if multiplayer.has_multiplayer_peer():
		sync_cloudburst_detonation_rpc.rpc(cast_id, smoke_position)

func broadcast_cloudburst_removal(cast_id: int) -> void:
	if multiplayer.has_multiplayer_peer():
		if not multiplayer.is_server():
			return
	var projectile := projectiles.get(cast_id) as Node2D
	if not projectile:
		return
	projectile.call("remove_smoke")
	if multiplayer.has_multiplayer_peer():
		sync_cloudburst_removal_rpc.rpc(cast_id)

func _reject_cast(peer_id: int) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and peer_id != 1:
		cast_rejected_rpc.rpc_id(peer_id)
	elif peer_id == 1:
		input_is_held = false
		held_cast_id = -1
		agent.set_active_ability("")

func _spawn_cloudburst(
	owner_peer_id: int,
	cast_id: int,
	start_position: Vector2,
	direction: Vector2
) -> void:
	if projectiles.has(cast_id):
		return
	var current_scene := get_tree().current_scene
	if not current_scene:
		push_error("Cannot create Cloudburst without an active scene.")
		return
	var projectile := PROJECTILE_SCENE.instantiate() as Area2D
	if not projectile:
		push_error("Could not instantiate the Cloudburst projectile scene.")
		return
	projectile.name = "Cloudburst_%d_%d" % [owner_peer_id, cast_id]
	projectile.add_to_group("skirmish_round_effects")
	current_scene.add_child(projectile)
	projectile.call(
		"initialize",
		owner_peer_id,
		cast_id,
		start_position,
		direction,
		self
	)
	projectiles[cast_id] = projectile
	held_cast_id = cast_id

func _on_cloudburst_detonated(cast_id: int) -> void:
	var projectile := projectiles.get(cast_id) as Node2D
	if projectile and smoke_audio and smoke_audio.stream:
		AudioManager.play_world_cue(smoke_audio, projectile.global_position)
	if held_cast_id == cast_id:
		held_cast_id = -1
		input_is_held = false
		if agent.has_local_authority() and not agent.is_dead:
			agent.weapon_controller.select_weapon_slot(
				agent.weapon_controller.current_weapon_slot
			)
		else:
			agent.set_active_ability("")

func _on_cloudburst_removed(cast_id: int) -> void:
	projectiles.erase(cast_id)
	if held_cast_id == cast_id:
		held_cast_id = -1

@rpc("any_peer", "reliable")
func request_start_cast_rpc(
	cast_id: int,
	direction: Vector2
) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if (
		sender_id != agent.get_multiplayer_authority()
		or cast_id <= next_cast_id
		or held_cast_id >= 0
	):
		_reject_cast(sender_id)
		return
	_start_authoritative_cast(cast_id, _get_muzzle_position(), direction)

@rpc("any_peer", "unreliable")
func request_aim_rpc(cast_id: int, direction: Vector2) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if (
		multiplayer.get_remote_sender_id() != agent.get_multiplayer_authority()
		or cast_id != held_cast_id
		or not direction.is_finite()
		or direction.is_zero_approx()
	):
		return
	var projectile := projectiles.get(cast_id) as Node2D
	if projectile:
		projectile.call("set_movement_direction", direction.normalized())

@rpc("any_peer", "reliable")
func request_detonate_rpc(cast_id: int, final_direction: Vector2) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if (
		multiplayer.get_remote_sender_id() != agent.get_multiplayer_authority()
		or not final_direction.is_finite()
		or final_direction.is_zero_approx()
	):
		return
	_detonate_cast(cast_id, final_direction.normalized())

@rpc("any_peer", "call_local", "reliable")
func spawn_cloudburst_rpc(
	owner_peer_id: int,
	cast_id: int,
	start_position: Vector2,
	direction: Vector2
) -> void:
	if (
		not _rpc_is_from_server()
		or owner_peer_id != agent.get_multiplayer_authority()
		or cast_id <= 0
		or not start_position.is_finite()
		or not direction.is_finite()
		or direction.is_zero_approx()
	):
		return
	_spawn_cloudburst(owner_peer_id, cast_id, start_position, direction.normalized())

@rpc("any_peer", "call_remote", "reliable")
func cast_rejected_rpc() -> void:
	if (
		not multiplayer.has_multiplayer_peer()
		or not _rpc_is_from_server()
		or not agent.has_local_authority()
	):
		return
	input_is_held = false
	held_cast_id = -1
	agent.set_active_ability("")

@rpc("any_peer", "call_remote", "reliable")
func sync_cloudburst_detonation_rpc(cast_id: int, smoke_position: Vector2) -> void:
	if not _rpc_is_from_server():
		return
	var projectile := projectiles.get(cast_id) as Node2D
	if not projectile or not smoke_position.is_finite():
		return
	projectile.call("enter_smoke", smoke_position)

@rpc("any_peer", "call_remote", "reliable")
func sync_cloudburst_removal_rpc(cast_id: int) -> void:
	if not _rpc_is_from_server():
		return
	var projectile := projectiles.get(cast_id) as Node2D
	if projectile:
		projectile.call("remove_smoke")

func remove_cloudburst_locally(cast_id: int) -> void:
	var projectile := projectiles.get(cast_id) as Node2D
	if projectile:
		projectile.call("remove_smoke")

func _rpc_is_from_server() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	var sender_id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		return sender_id == 0 or sender_id == 1
	return sender_id == 1
