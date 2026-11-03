extends Node

const ABILITY_ID := "Resurrection"
const REVIVE_DURATION := 2.5

@export_group("Audio")
@export var cast_audio: AudioCue
@export var active_audio: AudioCue
@export var voice_audio: AudioCue

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var is_selected := false
var cast_pending := false
var preview_target_id := 0

func _exit_tree() -> void:
	_clear_resurrection_preview()

func _process(_delta: float) -> void:
	if not agent:
		return
	var hud := _get_local_hud()
	if hud and hud.sage_resurrection_overlay.visible != is_selected:
		hud.sage_resurrection_overlay.visible = is_selected
	_update_resurrection_preview()

func _input(event: InputEvent) -> void:
	if not agent or not agent.has_local_authority():
		return
	if (
		agent.agent_data
		and event.is_action_pressed(agent.agent_data.ultimate_input_action)
		and _can_use_ultimate()
	):
		if event is InputEventKey and (event as InputEventKey).echo:
			return
		get_viewport().set_input_as_handled()
		if cast_pending:
			return
		if is_selected:
			_set_selected(false)
		elif agent.has_ultimate_charge():
			_set_selected(true)
		return
	if (
		is_selected and not cast_pending and event is InputEventMouseButton
	):
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		get_viewport().set_input_as_handled()
		var target_peer_id := _get_dead_ally_under_mouse()
		if target_peer_id == 0:
			return
		cast_pending = true
		agent.weapon_controller.suppress_shoot_until_released()
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			request_resurrection_rpc.rpc_id(1, target_peer_id)
			return
		if not _start_resurrection(target_peer_id):
			cast_pending = false

func blocks_weapon_input() -> bool:
	return is_selected or cast_pending

func reset_for_new_round() -> void:
	cast_pending = false
	_set_selected(false)

func handle_weapon_equipped() -> void:
	cast_pending = false
	_set_selected(false)

func _can_use_ultimate() -> bool:
	return (
		agent != null
		and
		not agent.is_dead
		and not agent.is_match_preparing
		and not agent.shop_open
		and not agent.agent_select_open
		and not agent.is_lobby_locked
	)

func _set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	var hud := _get_local_hud()
	if selected:
		agent.weapon_controller.suppress_shoot_until_released()
		agent.weapon_controller.set_weapon_hidden_by_ability(true)
		AudioManager.play_local_cue(cast_audio, &"sage_resurrection_cast")
		if hud:
			hud.show_sage_resurrection_effect()
	else:
		agent.weapon_controller.set_weapon_hidden_by_ability(false)
		if hud:
			hud.hide_sage_resurrection_effect()
	agent.set_ultimate_state(agent.has_ultimate_charge(), selected)

func _get_local_hud() -> GameHud:
	if not agent.has_local_authority():
		return null
	var current_scene := get_tree().current_scene
	if not current_scene:
		return null
	return current_scene.get_node_or_null("HUD") as GameHud

func _get_dead_ally_under_mouse() -> int:
	if agent.skirmish_team < 0:
		return 0
	var current_scene := get_tree().current_scene
	if not current_scene:
		return 0
	var mouse_position := agent.get_global_mouse_position()
	for node in current_scene.get_children():
		var target := node as Node2D
		if not _is_valid_actor_to_revive(target):
			continue
		var body_sprite := _get_actor_body_sprite(target)
		if not body_sprite or not body_sprite.get_rect().has_point(body_sprite.to_local(mouse_position)):
			continue
		if _has_line_of_sight(target):
			return _get_actor_id(target)
	return 0

func _update_resurrection_preview() -> void:
	if not is_selected or not agent.has_local_authority() or cast_pending:
		_clear_resurrection_preview()
		return
	var target_id := _get_dead_ally_under_mouse()
	if target_id == preview_target_id:
		return
	_clear_resurrection_preview()
	if target_id == 0:
		return
	var target := _find_actor(target_id)
	if target and target.has_method("set_sage_resurrection_indicator"):
		target.set_sage_resurrection_indicator(_get_preview_id(), true)
		preview_target_id = target_id

func _clear_resurrection_preview() -> void:
	if preview_target_id == 0 or not is_instance_valid(agent):
		preview_target_id = 0
		return
	var target := _find_actor(preview_target_id)
	if target and target.has_method("set_sage_resurrection_indicator"):
		target.set_sage_resurrection_indicator(_get_preview_id(), false)
	preview_target_id = 0

func _get_preview_id() -> int:
	return 1_000_000_000 + agent.get_multiplayer_authority()

func _is_valid_actor_to_revive(target: Node2D) -> bool:
	if not target or target == agent or not target.get("is_dead"):
		return false
	if target.get("is_match_preparing"):
		return false
	if int(target.get("skirmish_team")) != agent.skirmish_team:
		return false
	return target is BaseAgent and (not target.is_ai_dummy or target.is_in_match)

func _get_actor_body_sprite(target: Node2D) -> Sprite2D:
	if target is BaseAgent:
		return target.get_node_or_null("Visuals/BodySprite") as Sprite2D
	return null

func _get_actor_id(target: Node2D) -> int:
	if target is BaseAgent:
		return target.get_deathmatch_id()
	return 0

func _find_actor(actor_id: int) -> Node2D:
	if actor_id > 0:
		return NetworkManager.call("find_player", actor_id) as BaseAgent
	if actor_id < 0:
		return NetworkManager.call("find_deathmatch_actor", actor_id) as BaseAgent
	return null

func _has_line_of_sight(target: Node2D) -> bool:
	if not target or not is_instance_valid(target):
		return false
	var query := PhysicsRayQueryParameters2D.create(agent.global_position, target.global_position)
	query.collision_mask = 0x7FFFFFFF
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [agent.get_rid()]
	var result := agent.get_world_2d().direct_space_state.intersect_ray(query)
	return result.is_empty() or result.get("collider") == target

func _find_ally(peer_id: int) -> BaseAgent:
	return NetworkManager.call("find_player", peer_id) as BaseAgent

func _is_valid_resurrection_target(peer_id: int) -> bool:
	if peer_id == 0 or peer_id == agent.get_multiplayer_authority():
		return false
	var target := _find_actor(peer_id)
	return (
		target != null
		and _is_valid_actor_to_revive(target)
		and _get_actor_id(target) == peer_id
		and _has_line_of_sight(target)
	)

func _start_resurrection(target_peer_id: int) -> bool:
	if (
		not _can_use_ultimate()
		or not is_selected
		or not agent.has_ultimate_charge()
		or not _is_valid_resurrection_target(target_peer_id)
		or not agent.consume_ultimate_charge()
	):
		return false
	var target := _find_actor(target_peer_id)
	if not target:
		return false
	if multiplayer.has_multiplayer_peer():
		sync_resurrection_audio_rpc.rpc(agent.global_position)
	else:
		_play_resurrection_audio(agent.global_position)
	_set_selected(false)
	cast_pending = false
	if multiplayer.has_multiplayer_peer():
		sync_resurrection_started_rpc.rpc(agent.get_multiplayer_authority())
		target.begin_sage_revival_rpc.rpc()
		_finish_resurrection_after_delay(target_peer_id)
	else:
		target.begin_sage_revival()
		_finish_resurrection_after_delay(target_peer_id)
	return true

func _play_resurrection_audio(world_position: Vector2) -> void:
	AudioManager.play_world_cue(active_audio, world_position)
	if voice_audio and voice_audio.stream:
		var pitch := randf_range(
			minf(voice_audio.pitch_min, voice_audio.pitch_max),
			maxf(voice_audio.pitch_min, voice_audio.pitch_max)
		)
		AudioManager.play_global_stream(voice_audio.stream, voice_audio.volume_db, pitch)

@rpc("any_peer", "call_local", "reliable")
func sync_resurrection_audio_rpc(world_position: Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if (multiplayer.is_server() and sender_id not in [0, 1]) or (
			not multiplayer.is_server() and sender_id != 1
		):
			return
	if not world_position.is_finite():
		return
	_play_resurrection_audio(world_position)

func _finish_resurrection_after_delay(target_peer_id: int) -> void:
	await get_tree().create_timer(REVIVE_DURATION).timeout
	var target := _find_actor(target_peer_id)
	if not target:
		return
	if multiplayer.has_multiplayer_peer():
		target.finish_sage_revival_rpc.rpc()
	else:
		target.finish_sage_revival()

@rpc("any_peer", "call_remote", "reliable")
func request_resurrection_rpc(target_peer_id: int) -> void:
	if (
		not multiplayer.has_multiplayer_peer()
		or not multiplayer.is_server()
		or multiplayer.get_remote_sender_id() != agent.get_multiplayer_authority()
	):
		return
	if not _start_resurrection(target_peer_id):
		resurrection_rejected_rpc.rpc_id(multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "reliable")
func resurrection_rejected_rpc() -> void:
	if (
		multiplayer.has_multiplayer_peer()
		and multiplayer.get_remote_sender_id() == 1
		and agent.has_local_authority()
	):
		cast_pending = false

@rpc("any_peer", "call_remote", "reliable")
func sync_resurrection_started_rpc(owner_peer_id: int) -> void:
	if (
		owner_peer_id != agent.get_multiplayer_authority()
		or (
			multiplayer.has_multiplayer_peer()
			and multiplayer.get_remote_sender_id() != 1
		)
	):
		return
	cast_pending = false
	_set_selected(false)
