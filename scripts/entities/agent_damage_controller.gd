extends RefCounted

var _agent: Node

func setup(agent: Node) -> void:
	_agent = agent

func on_health_changed(current_health: float, max_health: float) -> void:
	var health_component := _agent.get("health_component") as HealthComponent
	_agent.call(
		"_emit_health_and_shield_changed",
		current_health,
		max_health,
		health_component.current_shield,
		health_component.max_shield
	)
	if bool(_agent.get("is_ai_dummy")):
		return
	var multiplayer_api := _agent.get_multiplayer()
	if (
		multiplayer_api.has_multiplayer_peer()
		and not bool(_agent.get("is_applying_network_health_state"))
		and (multiplayer_api.is_server() or _agent.is_multiplayer_authority())
	):
		NetworkManager.publish_player_health_state(
			_agent.get_multiplayer_authority(),
			current_health,
			health_component.current_shield,
			max_health,
			health_component.max_shield,
			health_component.regenerative_shield_reserve,
			health_component.regenerative_recharge_delay_remaining
		)

func on_damage_taken(amount: float) -> void:
	_agent.call("mark_combat_activity")
	_agent.call("_emit_damage_taken", amount)
	if bool(_agent.get("is_ai_dummy")):
		AudioManager.play_event_world(&"damage_taken", Vector2(_agent.get("global_position")))
		play_damage_flash()
		return
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer():
		AudioManager.play_event_world(&"damage_taken", Vector2(_agent.get("global_position")))
		play_local_hurt_audio()
		play_damage_flash()
	elif multiplayer_api.is_server():
		var owner_peer_id := _agent.get_multiplayer_authority()
		if owner_peer_id == multiplayer_api.get_unique_id():
			play_local_hurt_audio()
		else:
			_agent.rpc_id(owner_peer_id, "sync_local_hurt_audio_rpc")
		_agent.rpc("sync_damage_flash_rpc")
	var damage_source := _agent.get("damage_source_for_current_hit") as Node2D
	if not is_instance_valid(damage_source):
		return
	var direction := (damage_source.global_position - Vector2(_agent.get("global_position"))).normalized()
	_agent.call("_emit_damage_direction", direction)
	if multiplayer_api.has_multiplayer_peer() and multiplayer_api.is_server():
		var owner_peer_id := _agent.get_multiplayer_authority()
		if owner_peer_id > 1:
			NetworkManager.sync_player_damage_direction_rpc.rpc_id(
				owner_peer_id, owner_peer_id, direction
			)

func play_damage_flash() -> void:
	if bool(_agent.get("is_dead")):
		return
	var previous_tween := _agent.get("damage_flash_tween") as Tween
	if previous_tween and previous_tween.is_running():
		previous_tween.kill()
	_agent.set("modulate", Color.WHITE)
	var tween := _agent.create_tween()
	_agent.set("damage_flash_tween", tween)
	tween.tween_property(_agent, "modulate", Color(1.0, 0.2, 0.2, 1.0), 0.05)
	tween.tween_property(_agent, "modulate", Color.WHITE, 0.1)

func play_local_hurt_audio() -> void:
	var components := _agent.get_node_or_null("Components")
	if not components:
		return
	for component in components.get_children():
		if component.has_method("schedule_hurt_audio_locally"):
			component.call("schedule_hurt_audio_locally")
			return

func sync_local_hurt_audio() -> void:
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer() or multiplayer_api.is_server():
		return
	if multiplayer_api.get_remote_sender_id() != 1 or not _agent.is_multiplayer_authority():
		return
	play_local_hurt_audio()

func sync_damage_flash() -> void:
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer():
		return
	var sender_id := multiplayer_api.get_remote_sender_id()
	if multiplayer_api.is_server():
		if sender_id != 0 and sender_id != 1:
			return
	elif sender_id != 1:
		return
	AudioManager.play_event_world(&"damage_taken", Vector2(_agent.get("global_position")))
	play_damage_flash()

func show_damage_indicator(direction: Vector2) -> void:
	var multiplayer_api := _agent.get_multiplayer()
	if multiplayer_api.has_multiplayer_peer() and not _agent.is_multiplayer_authority():
		return
	if direction.is_zero_approx():
		return
	var previous_tween := _agent.get("damage_indicator_tween") as Tween
	if previous_tween and previous_tween.is_running():
		previous_tween.kill()
	var local_direction := direction.rotated(-float(_agent.get("global_rotation")))
	var damage_indicator := _agent.get("damage_indicator") as Sprite2D
	damage_indicator.position = local_direction * float(_agent.get("damage_indicator_radius"))
	damage_indicator.rotation = local_direction.angle() + PI / 2.0
	damage_indicator.modulate.a = 1.0
	damage_indicator.visible = true
	var tween := _agent.create_tween()
	_agent.set("damage_indicator_tween", tween)
	tween.tween_property(damage_indicator, "modulate:a", 0.0, 0.7)
	tween.tween_callback(func() -> void:
		damage_indicator.visible = false
	)

func on_died() -> void:
	var components := _agent.get_node("Components")
	for component in components.get_children():
		if component.has_method("handle_agent_death") and component.call("handle_agent_death"):
			_agent.set("death_intercepted_by_ability", true)
			return
	_agent.call("_emit_death_signals", _agent.get("last_attacker"))
	if _agent.has_node("/root/NetworkManager"):
		NetworkManager.call(
			"handle_player_death",
			_agent,
			_agent.get("last_attacker"),
			str(_agent.get("last_attacker_weapon_name"))
		)
