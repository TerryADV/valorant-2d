class_name BaseAgent
extends BaseAgentCore

const AgentDummyControllerScript = preload("res://scripts/entities/agent_dummy_controller.gd")
const AVAILABLE_WEAPONS: Array[WeaponData] = [
	preload("res://resources/weapons/vandal.tres"),
	preload("res://resources/weapons/classic.tres"),
	preload("res://resources/weapons/knife.tres"),
	preload("res://resources/weapons/spectre.tres"),
	preload("res://resources/weapons/operator.tres"),
	preload("res://resources/weapons/judge.tres"),
	preload("res://resources/weapons/odin.tres"),
]
const AVAILABLE_AGENTS: Array[AgentData] = [
	preload("res://resources/agents/phoenix.tres"),
	preload("res://resources/agents/jett.tres"),
	preload("res://resources/agents/sage.tres"),
]

enum Difficulty { EASY, MEDIUM, HARD }

signal ultimate_state_changed(ready: bool, active: bool)

func _setup_dummy_controllers() -> void:
	_dummy_controller = AgentDummyControllerScript.new()

@rpc("any_peer", "reliable")
func request_network_bullet(
	start_position: Vector2,
	direction: Vector2,
	wall_penetration: String,
	tracer_enabled: bool,
	weapon_name: String,
	short_range: float,
	medium_range: float,
	short_damage: float,
	medium_damage: float,
	long_damage: float,
	play_shot_sound: bool,
	is_secondary_fire: bool
) -> void:
	_projectile_controller.handle_bullet_request(
		start_position, direction, wall_penetration, tracer_enabled, weapon_name,
		short_range, medium_range, short_damage, medium_damage, long_damage,
		play_shot_sound, is_secondary_fire
	)

@rpc("any_peer", "call_local", "reliable")
func spawn_network_bullet(
	start_position: Vector2,
	direction: Vector2,
	wall_penetration: String,
	tracer_enabled: bool,
	weapon_name: String,
	short_range: float,
	medium_range: float,
	short_damage: float,
	medium_damage: float,
	long_damage: float,
	play_shot_sound: bool,
	is_secondary_fire: bool
) -> void:
	_projectile_controller.spawn_bullet(
		start_position, direction, wall_penetration, tracer_enabled, weapon_name,
		short_range, medium_range, short_damage, medium_damage, long_damage,
		play_shot_sound, is_secondary_fire
	)

func play_reload_sfx(weapon_slot: int) -> void:
	_audio_controller.play_reload(weapon_slot)

func play_footstep_sfx() -> void:
	_audio_controller.play_footstep()

func play_melee_sfx(heavy_attack: bool) -> void:
	_audio_controller.play_melee(heavy_attack)

@rpc("any_peer", "reliable")
func request_melee_sfx_rpc(weapon_name: String, heavy_attack: bool) -> void:
	_audio_controller.handle_melee_request(weapon_name, heavy_attack)

@rpc("any_peer", "call_local", "reliable")
func sync_melee_sfx_rpc(
	weapon_name: String,
	heavy_attack: bool,
	world_position: Vector2
) -> void:
	_audio_controller.sync_melee(weapon_name, heavy_attack, world_position)

@rpc("any_peer", "reliable")
func request_footstep_sfx_rpc(allow_footstep_audio: bool) -> void:
	_audio_controller.handle_footstep_request(allow_footstep_audio)

@rpc("any_peer", "call_local", "reliable")
func sync_footstep_sfx_rpc(world_position: Vector2) -> void:
	_audio_controller.sync_footstep(world_position)

@rpc("any_peer", "reliable")
func request_reload_sfx_rpc(weapon_slot: int) -> void:
	_audio_controller.handle_reload_request(weapon_slot)

@rpc("any_peer", "call_local", "reliable")
func sync_reload_sfx_rpc(weapon_slot: int, world_position: Vector2) -> void:
	_audio_controller.sync_reload(weapon_slot, world_position)

func take_damage(
	amount: float,
	attacker: Node = null,
	weapon_name: String = "",
	reveal_damage_direction: bool = true
) -> void:
	if is_ai_dummy:
		_dummy_controller.call_lifecycle("take_damage", [amount, attacker, weapon_name])
		return
	_lifecycle_controller.take_damage(amount, attacker, weapon_name, reveal_damage_direction)

@rpc("any_peer", "call_remote", "reliable")
func show_healing_status_rpc(effect_id: int, duration: float) -> void:
	_healing_state.call("add_healing_status", effect_id, duration)

@rpc("any_peer", "call_remote", "unreliable")
func update_healing_status_rpc(effect_id: int, remaining: float) -> void:
	_healing_state.call("update_healing_status", effect_id, remaining)

@rpc("any_peer", "call_remote", "reliable")
func remove_healing_status_rpc(effect_id: int) -> void:
	_healing_state.call("remove_healing_status", effect_id)

func _get_local_game_hud() -> GameHud:
	return _healing_state.call("_get_local_game_hud") as GameHud

func clear_healing_statuses() -> void:
	_healing_state.call("clear_healing_statuses")

func set_local_healing_audio_status(effect_id: int, active: bool) -> void:
	_healing_state.call("set_local_healing_audio_status", effect_id, active)

func set_sage_healing_visual(effect_id: int, active: bool) -> void:
	_healing_state.call("set_healing_visual", effect_id, active)

func set_sage_healing_preview(effect_id: int, active: bool) -> void:
	_healing_state.call("set_healing_preview", effect_id, active)

func set_slow_zone_active(source_id: int, active: bool) -> void:
	if source_id <= 0:
		return
	if active:
		slow_zone_sources[source_id] = true
	else:
		slow_zone_sources.erase(source_id)

@rpc("authority", "call_remote", "unreliable")
func sync_dummy_state(
	world_position: Vector2,
	movement_velocity: Vector2,
	visual_rotation: float,
	weapon_index: int
) -> void:
	_dummy_controller.call_weapon("sync_weapon_selection", [weapon_index])
	_dummy_controller.call_movement("sync_state", [world_position, movement_velocity, visual_rotation])

@rpc("authority", "call_remote", "unreliable_ordered")
func sync_dummy_health(
	dummy_id: int,
	current_health_value: float,
	current_shield_value: float,
	max_health_value: float,
	max_shield_value: float
) -> void:
	if not _dummy_controller.is_server_rpc_sender() or dummy_id != get_deathmatch_id():
		return
	if not is_equal_approx(health_component.max_health, max_health_value) or not is_equal_approx(
		health_component.max_shield, max_shield_value
	):
		health_component.configure_health(max_health_value, max_shield_value)
	health_component.restore_state(current_health_value, current_shield_value)

@rpc("authority", "call_remote", "unreliable")
func sync_dummy_footstep(world_position: Vector2) -> void:
	_dummy_controller.call_movement("sync_footstep", [world_position])

@rpc("authority", "call_local", "reliable")
func sync_weapon_selection(weapon_index: int) -> void:
	_dummy_controller.call_weapon("sync_weapon_selection", [weapon_index])

@rpc("authority", "call_local", "reliable")
func sync_dummy_bullet(weapon_index: int, start_position: Vector2, direction: Vector2, play_shot_sound: bool) -> void:
	_dummy_controller.call_weapon("sync_bullet", [weapon_index, start_position, direction, play_shot_sound])

@rpc("authority", "call_remote", "reliable")
func sync_dummy_weapon_sound(sound: int, weapon_index: int, world_position: Vector2) -> void:
	_dummy_controller.call_weapon("sync_weapon_sound", [sound, weapon_index, world_position])

func get_deathmatch_id() -> int:
	if not is_ai_dummy:
		return get_multiplayer_authority()
	var current_scene := get_tree().current_scene
	if not current_scene:
		return -1
	var dummy_index := 0
	for sibling in current_scene.get_children():
		if sibling is BaseAgent and sibling.is_ai_dummy:
			if sibling == self:
				return -(dummy_index + 1)
			dummy_index += 1
	return -1

func get_agent_sprite() -> Texture2D:
	return body_sprite.texture if body_sprite else null

func initialize_for_match(spawn_position: Vector2, weapon: WeaponData, p_difficulty: int = Difficulty.HARD, p_agent_index: int = -1) -> void:
	_dummy_controller.call_lifecycle("initialize_for_match", [spawn_position, weapon, p_difficulty, Difficulty.EASY, Difficulty.HARD, p_agent_index])

func set_inactive_for_match() -> void:
	_dummy_controller.call_lifecycle("set_inactive_for_match")

func respawn_dummy() -> void:
	_dummy_controller.call_lifecycle("respawn_dummy")

@rpc("authority", "call_local", "reliable")
func sync_dummy_lifecycle(is_alive: bool, spawn_position: Vector2, weapon_index: int = -1, p_agent_index: int = -1) -> void:
	_dummy_controller.call_lifecycle("sync_lifecycle", [is_alive, spawn_position, weapon_index, difficulty, Difficulty.EASY, Difficulty.HARD, p_agent_index])

func apply_flash(duration: float) -> void:
	_dummy_controller.call_lifecycle("apply_flash", [duration])

@rpc("authority", "call_local", "reliable")
func sync_dummy_flash(duration: float) -> void:
	_dummy_controller.call_lifecycle("sync_flash", [duration])

func set_sage_resurrection_indicator(effect_id: int, active: bool) -> void:
	_healing_state.call("set_resurrection_indicator", effect_id, active)

func _update_ability_indicator() -> void:
	_healing_state.call("_update_ability_indicator")

@rpc("any_peer", "call_local", "reliable")
func sync_sage_healing_visual(effect_id: int, active: bool) -> void:
	_healing_state.call("sync_healing_visual", effect_id, active)

func is_invulnerable() -> bool:
	return invulnerable_enabled

func set_ultimate_state(is_ready: bool, active: bool) -> void:
	ultimate_state_changed.emit(is_ready, active)

func set_infinite_credits_enabled(enabled: bool) -> void:
	_set_training_option("credits", enabled)

func set_invulnerable_enabled(enabled: bool) -> void:
	_set_training_option("invulnerable", enabled)

func set_infinite_ammo_enabled(enabled: bool) -> void:
	_set_training_option("ammo", enabled)

func _set_training_option(option: String, enabled: bool) -> void:
	_training_controller.call("set_option", option, enabled)

func _is_training_option_valid(option: String) -> bool:
	return bool(_training_controller.call("is_valid_option", option))

func _apply_training_option(option: String, enabled: bool) -> void:
	_training_controller.call("apply_option", option, enabled)

func request_training_charge_refill_rpc() -> void:
	_training_controller.call("request_charge_refill")

@rpc("any_peer", "call_remote", "reliable")
func request_training_charge_refill_server() -> void:
	_training_controller.call("handle_charge_refill_request")

func _refill_training_charges() -> void:
	_training_controller.call("refill_charges")

func _apply_training_charge_state(charge_state: Dictionary) -> void:
	_training_controller.call("apply_charge_state", charge_state)

@rpc("any_peer", "call_local", "reliable")
func sync_training_charge_state_rpc(peer_id: int, charge_state: Dictionary) -> void:
	if not bool(_training_controller.call("validate_charge_state", peer_id)):
		return
	_apply_training_charge_state(charge_state)

@rpc("any_peer", "call_remote", "reliable")
func request_training_option_rpc(option: String, enabled: bool) -> void:
	if not bool(_training_controller.call("validate_option_request", option)):
		return
	_apply_training_option(option, enabled)
	sync_training_option_rpc.rpc(get_multiplayer_authority(), option, enabled)

@rpc("any_peer", "call_local", "reliable")
func sync_training_option_rpc(peer_id: int, option: String, enabled: bool) -> void:
	if not bool(_training_controller.call("validate_option_sync", peer_id, option)):
		return
	_apply_training_option(option, enabled)

func set_training_ammo_state(enabled: bool) -> void:
	_training_controller.call("set_ammo_state", enabled)

func set_training_credits_state(enabled: bool) -> void:
	_training_controller.call("set_credits_state", enabled)

func set_training_menu_open(is_open: bool) -> void:
	_training_controller.call("set_menu_open", is_open)

@rpc("any_peer", "call_remote", "reliable")
func request_training_menu_state_rpc(is_open: bool) -> void:
	if not bool(_training_controller.call("validate_menu_request")):
		return
	_sync_training_menu_state(is_open)
	sync_training_menu_state_rpc.rpc(get_multiplayer_authority(), is_open)

@rpc("any_peer", "call_local", "reliable")
func sync_training_menu_state_rpc(peer_id: int, is_open: bool) -> void:
	if not bool(_training_controller.call("validate_menu_sync", peer_id)):
		return
	_sync_training_menu_state(is_open)

func _sync_training_menu_state(is_open: bool) -> void:
	_training_controller.call("sync_menu_state", is_open)

func update_local_weapon_hud() -> void:
	if not has_local_authority():
		return
	var hud := get_parent().get_node_or_null("HUD")
	if hud and hud.has_method("update_weapon_info"):
		hud.call("update_weapon_info")

@rpc("any_peer", "call_remote", "reliable")
func sync_incoming_healing_status_rpc(status_id: int, active: bool) -> void:
	_healing_state.call("sync_incoming_status", status_id, active)

func record_combat_damage_received(actor: Node, amount: float, weapon_name: String = "") -> void:
	_combat_stats.call("record_damage_received", actor, amount, weapon_name)

func record_combat_damage_dealt(actor: Node, amount: float, weapon_name: String = "") -> void:
	_combat_stats.call("record_damage_dealt", actor, amount, weapon_name)

func get_combat_damage_received_from(actor: Node) -> float:
	return float(_combat_stats.call("get_damage_received_from", actor))

func get_combat_damage_received_total() -> float:
	return float(_combat_stats.call("get_damage_received_total"))

func get_combat_damage_dealt_to(actor: Node) -> float:
	return float(_combat_stats.call("get_damage_dealt_to", actor))

func get_combat_damage_dealt_total() -> float:
	return float(_combat_stats.call("get_damage_dealt_total"))

func mark_combat_activity() -> void:
	_lifecycle_controller.mark_combat_activity()

func get_agent_switch_lock_remaining() -> float:
	return _lifecycle_controller.get_agent_switch_lock_remaining()

func heal(amount: float) -> void:
	_lifecycle_controller.heal(amount)

func handle_death() -> void:
	if is_ai_dummy:
		_dummy_controller.call_lifecycle("handle_death")
		return
	_lifecycle_controller.handle_death()
	if is_dead and _spectator_controller:
		_spectator_controller.enter()

func respawn_at(spawn_position: Vector2) -> void:
	if _spectator_controller:
		_spectator_controller.exit()
	_lifecycle_controller.respawn_at(spawn_position)

func begin_sage_revival() -> void:
	_lifecycle_controller.begin_sage_revival(
		not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	)

func finish_sage_revival() -> void:
	_lifecycle_controller.finish_sage_revival()

@rpc("any_peer", "call_local", "reliable")
func begin_sage_revival_rpc() -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if (multiplayer.is_server() and sender_id not in [0, 1]) or (
			not multiplayer.is_server() and sender_id != 1
		):
			return
	_lifecycle_controller.begin_sage_revival(multiplayer.is_server())

@rpc("any_peer", "call_local", "reliable")
func finish_sage_revival_rpc() -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if (multiplayer.is_server() and sender_id not in [0, 1]) or (
			not multiplayer.is_server() and sender_id != 1
		):
			return
	_lifecycle_controller.finish_sage_revival()

func grant_spawn_protection() -> void:
	_lifecycle_controller.grant_spawn_protection()

func is_spawn_protected() -> bool:
	return _lifecycle_controller.is_spawn_protected()

func _process(delta: float) -> void:
	if is_ai_dummy:
		_dummy_controller.call_lifecycle("process", [delta])
		_team_visibility_controller.process(delta)
		return
	_lifecycle_controller.process(delta)
	_team_visibility_controller.process(delta)

func get_current_health() -> float:
	return health_component.current_health

func get_max_health() -> float:
	return health_component.max_health

func get_current_shield() -> float:
	return health_component.current_shield

func get_max_shield() -> float:
	return health_component.max_shield

func _emit_health_and_shield_changed(
	current_health: float,
	max_health: float,
	current_shield: float,
	max_shield: float
) -> void:
	health_changed.emit(current_health, max_health)
	shield_changed.emit(current_shield, max_shield)

func _emit_damage_taken(amount: float) -> void:
	damage_taken.emit(amount)

func _emit_damage_direction(direction: Vector2) -> void:
	damage_direction_received.emit(direction)

func _emit_died_signal() -> void:
	died.emit()

func _emit_death_signals(killer: Node) -> void:
	died.emit()
	death_reported.emit(killer, self)

func _on_health_changed(current_health: float, max_health: float) -> void:
	_damage_controller.on_health_changed(current_health, max_health)

func _on_damage_taken(amount: float) -> void:
	_damage_controller.on_damage_taken(amount)

func _play_damage_flash() -> void:
	_damage_controller.play_damage_flash()

func _play_local_hurt_audio() -> void:
	_damage_controller.play_local_hurt_audio()

@rpc("any_peer", "call_remote", "reliable")
func sync_local_hurt_audio_rpc() -> void:
	_damage_controller.sync_local_hurt_audio()

@rpc("any_peer", "call_local", "reliable")
func sync_damage_flash_rpc() -> void:
	_damage_controller.sync_damage_flash()

func _show_damage_indicator(direction: Vector2) -> void:
	_damage_controller.show_damage_indicator(direction)

func _on_died() -> void:
	if is_ai_dummy:
		return
	_damage_controller.on_died()

func _on_weapon_changed(_weapon: WeaponData, _slot: int) -> void:
	weapon_changed.emit(_weapon, _slot)
	visuals.queue_redraw()

func equip_dropped_weapon(dropped_weapon: DroppedWeapon) -> void:
	weapon_controller.equip_dropped_weapon(dropped_weapon)

func handle_movement(delta: float) -> void:
	movement_controller.process_movement(delta)

func handle_rotation() -> void:
	visuals.process_visuals()

func handle_camera_look_ahead() -> void:
	camera_controller.process_camera_look_ahead()
