extends Node

const ABILITY_ID := "HealingOrb"
const HEALING_ABILITY_NAME := "Healing Orb"
const HEALING_AMOUNT := 100.0
const HEALING_DURATION := 5.0
const HEALING_PER_SECOND := HEALING_AMOUNT / HEALING_DURATION
const DAMAGE_INTERRUPTION_DURATION := 2.0
const AGENT_COLLISION_MASK := 16
const HEALTH_SYNC_INTERVAL := 0.1

@export_group("Audio")
@export var cast_audio: AudioCue
@export var active_audio: AudioCue
@export var voice_audio: AudioCue

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var cast_pending := false
var next_effect_id := 0
var healing_effects: Dictionary = {}
var preview_target_peer_id := 0

func play_cast_audio() -> void:
	AudioManager.play_local_cue(cast_audio, &"sage_healing_orb_cast")

func _exit_tree() -> void:
	_clear_healing_preview()

func _input(event: InputEvent) -> void:
	if (
		not agent
		or not agent.has_local_authority()
		or agent.is_dead
		or agent.is_match_preparing
		or agent.shop_open
		or agent.active_ability_name != ABILITY_ID
		or cast_pending
		or not event is InputEventMouseButton
	):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	var target_peer_id := 0
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		target_peer_id = agent.get_multiplayer_authority()
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
		target_peer_id = _get_ally_target_peer_id()
	else:
		return
	get_viewport().set_input_as_handled()
	if target_peer_id == 0:
		return
	var orb_ability := agent.get_node_or_null("Components/SageOrbAbility")
	if orb_ability and bool(orb_ability.get("is_appearing")):
		return
	cast_pending = true
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_heal_rpc.rpc_id(1, target_peer_id)
		return
	if not _start_heal(target_peer_id):
		cast_pending = false

func _process(delta: float) -> void:
	_update_healing_preview()
	if healing_effects.is_empty():
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if NetworkManager.is_skirmish_mode() and NetworkManager.is_skirmish_preparation():
		_clear_healing_effects()
		return
	var expired_effects: Array[int] = []
	for effect_id in healing_effects.keys():
		var effect: Dictionary = healing_effects[effect_id]
		var target_peer_id := int(effect["target_peer_id"])
		var target := _find_healing_target(target_peer_id)
		if not target or bool(target.get("is_dead")):
			expired_effects.append(int(effect_id))
			continue
		var remaining := float(effect["remaining"])
		var interruption_remaining := float(effect.get("interruption_remaining", 0.0))
		var paused_delta := minf(delta, interruption_remaining)
		interruption_remaining = maxf(interruption_remaining - delta, 0.0)
		var effect_delta := minf(delta, remaining)
		var active_delta := maxf(effect_delta - paused_delta, 0.0)
		var healing_amount := HEALING_PER_SECOND * active_delta
		remaining = maxf(remaining - effect_delta, 0.0)
		effect["remaining"] = remaining
		effect["interruption_remaining"] = interruption_remaining
		if not multiplayer.has_multiplayer_peer():
			_get_target_health(target).heal(healing_amount)
		elif multiplayer.is_server():
			_accumulate_network_healing(target, effect, healing_amount, delta)
		healing_effects[effect_id] = effect
		_update_local_healing_state(int(effect["status_id"]), target, remaining)
		if remaining <= 0.0:
			expired_effects.append(int(effect_id))
	for effect_id in expired_effects:
		_remove_healing_effect(effect_id, true)

func blocks_weapon_input() -> bool:
	return cast_pending or (agent != null and agent.active_ability_name == ABILITY_ID)

func reset_for_new_round() -> void:
	cast_pending = false
	_clear_healing_effects()

func _start_heal(target_peer_id: int) -> bool:
	if (
		agent.is_dead
		or agent.is_match_preparing
		or agent.shop_open
		or agent.active_ability_name != ABILITY_ID
		or not _is_valid_healing_target(target_peer_id)
	):
		return false
	var target := _find_healing_target(target_peer_id)
	if not target or not agent.consume_ability_charge(ABILITY_ID):
		return false
	_play_healing_audio(target_peer_id)
	_clear_healing_preview()
	next_effect_id += 1
	var effect_id := next_effect_id
	var status_id := agent.get_multiplayer_authority() * 100000 + effect_id
	_register_healing_effect(effect_id, target_peer_id, status_id, HEALING_DURATION)
	var owner_peer_id := agent.get_multiplayer_authority()
	var base_target := target as BaseAgent
	if multiplayer.has_multiplayer_peer() and target_peer_id == owner_peer_id and owner_peer_id != 1:
		show_healing_effect_rpc.rpc_id(owner_peer_id, effect_id, target_peer_id, status_id, HEALING_DURATION)
	elif (
		multiplayer.has_multiplayer_peer()
		and base_target != null
		and target_peer_id > 1
		and target_peer_id != owner_peer_id
	):
		base_target.show_healing_status_rpc.rpc_id(target_peer_id, status_id, HEALING_DURATION)
	agent.set_active_ability("")
	cast_pending = false
	if agent.has_local_authority():
		_return_to_weapon()
	elif multiplayer.has_multiplayer_peer():
		heal_started_rpc.rpc_id(owner_peer_id)
	return true

func _return_to_weapon() -> void:
	if not agent.has_local_authority():
		return
	var weapon_controller = agent.weapon_controller
	if not weapon_controller or not weapon_controller.current_weapon:
		return
	weapon_controller.suppress_shoot_until_released()
	weapon_controller.select_weapon_slot(weapon_controller.current_weapon_slot, false, true)

func _get_ally_target_peer_id() -> int:
	var local_team := _get_actor_team(agent)
	if local_team < 0:
		return 0
	var query := PhysicsPointQueryParameters2D.new()
	query.position = agent.get_global_mouse_position()
	query.collision_mask = AGENT_COLLISION_MASK
	query.collide_with_areas = false
	for result in agent.get_world_2d().direct_space_state.intersect_point(query, 16):
		var target := result.get("collider") as Node2D
		if (
			target
			and target != agent
			and _is_valid_ally_target(target)
			and _has_line_of_sight(target)
		):
			return _get_target_actor_id(target)
	return 0

func _update_healing_preview() -> void:
	if (
		not agent
		or not agent.has_local_authority()
		or agent.is_dead
		or agent.shop_open
		or agent.active_ability_name != ABILITY_ID
	):
		_clear_healing_preview()
		return
	var target_peer_id := _get_ally_target_peer_id()
	if target_peer_id == preview_target_peer_id:
		return
	_clear_healing_preview()
	if target_peer_id == 0:
		return
	var target := _find_healing_target(target_peer_id)
	if target and target.has_method("set_sage_healing_preview"):
		target.set_sage_healing_preview(_get_preview_id(), true)
		preview_target_peer_id = target_peer_id

func _clear_healing_preview() -> void:
	if preview_target_peer_id == 0 or not is_instance_valid(agent):
		preview_target_peer_id = 0
		return
	var target := _find_healing_target(preview_target_peer_id)
	if target and target.has_method("set_sage_healing_preview"):
		target.set_sage_healing_preview(_get_preview_id(), false)
	preview_target_peer_id = 0

func _get_preview_id() -> int:
	return 2_000_000_000 - agent.get_multiplayer_authority()

func _find_healing_target(target_id: int) -> Node2D:
	if target_id > 0:
		if target_id == agent.get_multiplayer_authority():
			return agent
		return NetworkManager.call("find_player", target_id) as BaseAgent
	if target_id < 0:
		return NetworkManager.call("find_deathmatch_actor", target_id) as BaseAgent
	return null

func _get_target_actor_id(target: Node2D) -> int:
	if target is BaseAgent:
		return target.get_deathmatch_id()
	return 0

func _get_target_health(target: Node2D) -> HealthComponent:
	if target is BaseAgent:
		return target.health_component
	return null

func _is_valid_ally_target(target: Node2D) -> bool:
	if not target or bool(target.get("is_dead")):
		return false
	var target_health := _get_target_health(target)
	var local_team := _get_actor_team(agent)
	return target_health != null and target_health.current_health < target_health.max_health and (
		local_team >= 0 and _get_actor_team(target) == local_team
	)

func _get_actor_team(target: Node2D) -> int:
	if target is BaseAgent and not target.is_ai_dummy:
		var peer_id := target.get_multiplayer_authority()
		var assigned_team := NetworkManager.get_skirmish_team_for_peer(peer_id)
		if assigned_team >= 0:
			return assigned_team
	return int(target.get("skirmish_team"))

func _is_valid_healing_target(target_id: int) -> bool:
	var target := _find_healing_target(target_id)
	if not target or bool(target.get("is_dead")):
		return false
	var target_health := _get_target_health(target)
	if not target_health or target_health.current_health >= target_health.max_health:
		return false
	if target == agent:
		return true
	return (
		_is_valid_ally_target(target)
		and _has_line_of_sight(target)
	)

func _has_line_of_sight(target: Node2D) -> bool:
	if not target or target == agent or not is_instance_valid(target):
		return false
	var query := PhysicsRayQueryParameters2D.create(agent.global_position, target.global_position)
	query.collision_mask = 0x7FFFFFFF
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [agent.get_rid()]
	var result := agent.get_world_2d().direct_space_state.intersect_ray(query)
	return not result.is_empty() and result.get("collider") == target

func _accumulate_network_healing(
	target: Node2D,
	effect: Dictionary,
	healing_amount: float,
	delta: float
) -> void:
	effect["health_sync_elapsed"] = float(effect.get("health_sync_elapsed", 0.0)) + delta
	effect["pending_healing"] = float(effect.get("pending_healing", 0.0)) + healing_amount
	if (
		float(effect["health_sync_elapsed"]) >= HEALTH_SYNC_INTERVAL
		or float(effect["remaining"]) <= 0.0
	):
		var pending_healing := float(effect["pending_healing"])
		if pending_healing > 0.0:
			_get_target_health(target).heal(pending_healing)
		effect["health_sync_elapsed"] = 0.0
		effect["pending_healing"] = 0.0
		var target_peer_id := int(effect["target_peer_id"])
		var base_target := target as BaseAgent
		if base_target and target_peer_id > 1:
			base_target.update_healing_status_rpc.rpc_id(
				target_peer_id,
				int(effect["status_id"]),
				float(effect["remaining"])
			)

func _register_healing_effect(
	effect_id: int,
	target_peer_id: int,
	status_id: int,
	duration: float
) -> void:
	if effect_id <= 0 or not is_equal_approx(duration, HEALING_DURATION):
		return
	healing_effects[effect_id] = {
		"target_peer_id": target_peer_id,
		"status_id": status_id,
		"remaining": duration,
		"health_sync_elapsed": 0.0,
		"pending_healing": 0.0,
		"interruption_remaining": 0.0,
	}
	var target := _find_healing_target(target_peer_id)
	if target and (not multiplayer.has_multiplayer_peer() or multiplayer.is_server()):
		var damage_callback := _on_healing_target_damaged.bind(effect_id)
		var target_health := _get_target_health(target)
		if target_health and not target_health.damage_taken.is_connected(damage_callback):
			target_health.damage_taken.connect(damage_callback)
	var base_target := target as BaseAgent
	if base_target and base_target.has_local_authority():
		var hud := _get_game_hud()
		if hud:
			hud.add_healing_state(status_id, HEALING_ABILITY_NAME, duration)
		base_target.set_local_healing_audio_status(status_id, true)
	elif (
		base_target
		and multiplayer.has_multiplayer_peer()
		and multiplayer.is_server()
		and base_target.get_multiplayer_authority() != 1
	):
		base_target.sync_incoming_healing_status_rpc.rpc_id(
			base_target.get_multiplayer_authority(), status_id, true
		)

func _update_local_healing_state(status_id: int, target: Node2D, remaining: float) -> void:
	var base_target := target as BaseAgent
	if not base_target or not base_target.has_local_authority():
		return
	var hud := _get_game_hud()
	if hud:
		hud.update_healing_state(status_id, remaining)

func _remove_healing_effect(effect_id: int, notify_owner: bool) -> void:
	if not healing_effects.has(effect_id):
		return
	var effect: Dictionary = healing_effects[effect_id]
	healing_effects.erase(effect_id)
	var target := _find_healing_target(int(effect["target_peer_id"]))
	if target:
		var damage_callback := _on_healing_target_damaged.bind(effect_id)
		var target_health := _get_target_health(target)
		if target_health and target_health.damage_taken.is_connected(damage_callback):
			target_health.damage_taken.disconnect(damage_callback)
	var base_target := target as BaseAgent
	if base_target and base_target.has_local_authority():
		var hud := _get_game_hud()
		if hud:
			hud.remove_healing_state(int(effect["status_id"]))
		base_target.set_local_healing_audio_status(int(effect["status_id"]), false)
	elif (
		base_target
		and notify_owner
		and multiplayer.has_multiplayer_peer()
		and multiplayer.is_server()
		and base_target.get_multiplayer_authority() != 1
	):
		base_target.sync_incoming_healing_status_rpc.rpc_id(
			base_target.get_multiplayer_authority(), int(effect["status_id"]), false
		)
	elif (
		notify_owner
		and target is BaseAgent
		and not base_target.is_ai_dummy
		and multiplayer.has_multiplayer_peer()
		and multiplayer.is_server()
	):
		base_target.sync_incoming_healing_status_rpc.rpc_id(
			base_target.get_multiplayer_authority(), int(effect["status_id"]), false
		)
		var owner_peer_id := agent.get_multiplayer_authority()
		if int(effect["target_peer_id"]) == owner_peer_id and owner_peer_id != 1:
			remove_healing_effect_rpc.rpc_id(owner_peer_id, effect_id)
		else:
			base_target.remove_healing_status_rpc.rpc_id(
				base_target.get_multiplayer_authority(), int(effect["status_id"])
			)

func _on_healing_target_damaged(_amount: float, effect_id: int) -> void:
	if not healing_effects.has(effect_id):
		return
	var effect: Dictionary = healing_effects[effect_id]
	effect["interruption_remaining"] = DAMAGE_INTERRUPTION_DURATION
	healing_effects[effect_id] = effect

func _clear_healing_effects() -> void:
	for effect_id in healing_effects.keys():
		_remove_healing_effect(int(effect_id), true)

func _set_healing_visual(target: Node2D, effect_id: int, active: bool) -> void:
	if not target or not target.has_method("set_sage_healing_visual"):
		return
	if target == agent:
		return
	# El preview lo controla Sage localmente; el servidor sincroniza solo el efecto real.
	if effect_id == _get_preview_id():
		target.set_sage_healing_visual(effect_id, active)
		return
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		target.rpc("sync_sage_healing_visual", effect_id, active)
	else:
		target.set_sage_healing_visual(effect_id, active)

@rpc("any_peer", "call_remote", "reliable")
func request_heal_rpc(target_peer_id: int) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != agent.get_multiplayer_authority():
		return
	if agent.is_dead or agent.is_match_preparing or agent.shop_open:
		return
	if not _start_heal(target_peer_id):
		heal_rejected_rpc.rpc_id(sender_id)

@rpc("any_peer", "call_remote", "reliable")
func heal_rejected_rpc() -> void:
	if (
		multiplayer.has_multiplayer_peer()
		and multiplayer.get_remote_sender_id() == 1
		and agent.has_local_authority()
	):
		cast_pending = false

@rpc("any_peer", "call_remote", "reliable")
func heal_started_rpc() -> void:
	if (
		not multiplayer.has_multiplayer_peer()
		or multiplayer.get_remote_sender_id() != 1
		or not agent.has_local_authority()
	):
		return
	cast_pending = false
	_return_to_weapon()

@rpc("any_peer", "call_remote", "reliable")
func show_healing_effect_rpc(
	effect_id: int,
	target_peer_id: int,
	status_id: int,
	duration: float
) -> void:
	if (
		not multiplayer.has_multiplayer_peer()
		or multiplayer.get_remote_sender_id() != 1
		or not agent.has_local_authority()
		or target_peer_id != agent.get_multiplayer_authority()
	):
		return
	_register_healing_effect(effect_id, target_peer_id, status_id, duration)

@rpc("any_peer", "call_remote", "reliable")
func remove_healing_effect_rpc(effect_id: int) -> void:
	if (
		not multiplayer.has_multiplayer_peer()
		or multiplayer.get_remote_sender_id() != 1
		or not agent.has_local_authority()
	):
		return
	_remove_healing_effect(effect_id, false)

func _get_game_hud() -> GameHud:
	var current_scene := get_tree().current_scene
	if not current_scene:
		return null
	var hud := current_scene.get_node_or_null("HUD") as GameHud
	if not hud:
		hud = current_scene.find_child("GameHud", true, false) as GameHud
	return hud

func _play_healing_audio(target_peer_id: int) -> void:
	var healing_an_ally := target_peer_id != agent.get_multiplayer_authority()
	if not multiplayer.has_multiplayer_peer():
		AudioManager.play_local_cue(
			active_audio, &"sage_healing_orb_active", agent.global_position
		)
		if healing_an_ally:
			AudioManager.play_local_cue(voice_audio, &"sage_healing_orb_voice")
		return
	if multiplayer.is_server():
		sync_healing_audio_rpc.rpc(agent.get_multiplayer_authority(), target_peer_id)

@rpc("any_peer", "call_local", "reliable")
func sync_healing_audio_rpc(owner_peer_id: int, target_peer_id: int) -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if (multiplayer.is_server() and sender_id not in [0, 1]) or (
			not multiplayer.is_server() and sender_id != 1
		):
			return
	var local_peer_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	if local_peer_id == owner_peer_id:
		AudioManager.play_local_cue(
			active_audio, &"sage_healing_orb_active", agent.global_position
		)
		if target_peer_id != owner_peer_id:
			AudioManager.play_local_cue(voice_audio, &"sage_healing_orb_voice")
	elif target_peer_id > 0 and local_peer_id == target_peer_id:
		AudioManager.play_local_cue(
			active_audio, &"sage_healing_orb_active", agent.global_position
		)
