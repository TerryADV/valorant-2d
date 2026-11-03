extends RefCounted

const SPAWN_PROTECTION_DURATION := 1.5
const AGENT_SWITCH_COMBAT_LOCK_SECONDS := 10.0

var _agent: Node

func setup(agent: Node) -> void:
	_agent = agent

func take_damage(
	amount: float,
	attacker: Node = null,
	weapon_name: String = "",
	reveal_damage_direction: bool = true
) -> void:
	if (
		bool(_agent.get("is_lobby_locked"))
		or bool(_agent.get("is_dead"))
		or bool(_agent.get("is_match_preparing"))
		or is_spawn_protected()
	):
		return
	var health_component := _agent.get("health_component") as HealthComponent
	if not health_component:
		return
	if attacker and attacker != _agent:
		if _agent.has_method("is_invulnerable") and _agent.call("is_invulnerable"):
			return
		var recorded_damage := minf(amount, health_component.current_health + health_component.current_shield)
		_agent.set("last_attacker", attacker)
		_agent.set(
			"last_attacker_life_id",
			_get_combat_life_id(attacker)
		)
		_agent.set("last_attacker_weapon_name", weapon_name)
		if _agent.has_method("record_combat_damage_received"):
			_agent.call("record_combat_damage_received", attacker, recorded_damage, weapon_name)
	_agent.set(
		"damage_source_for_current_hit",
		attacker as Node2D if reveal_damage_direction else null
	)
	health_component.take_damage(amount)
	_agent.set("damage_source_for_current_hit", null)

func _get_combat_life_id(actor: Node) -> int:
	for property_info in actor.get_property_list():
		if String(property_info.get("name", "")) == "combat_life_id":
			return int(actor.get("combat_life_id"))
	return 0

func mark_combat_activity() -> void:
	_agent.set("last_combat_activity_msec", Time.get_ticks_msec())

func get_agent_switch_lock_remaining() -> float:
	var last_activity := int(_agent.get("last_combat_activity_msec"))
	if last_activity < 0:
		return 0.0
	var elapsed_seconds := (Time.get_ticks_msec() - last_activity) / 1000.0
	return maxf(AGENT_SWITCH_COMBAT_LOCK_SECONDS - elapsed_seconds, 0.0)

func heal(amount: float) -> void:
	if bool(_agent.get("is_dead")):
		return
	var health_component := _agent.get("health_component") as HealthComponent
	health_component.heal(amount)

func handle_death() -> void:
	if bool(_agent.get("death_intercepted_by_ability")):
		_agent.set("death_intercepted_by_ability", false)
		return
	if bool(_agent.get("is_dead")):
		return
	var health_component := _agent.get("health_component") as HealthComponent
	if health_component.current_health > 0.0:
		return
	_agent.set("is_dead", true)
	_agent.set("last_combat_activity_msec", -1)
	_agent.set("shop_open", false)
	_agent.set("is_movement_locked", false)
	var weapon_controller: Node = _agent.get("weapon_controller")
	weapon_controller.set("aiming", false)
	weapon_controller.set("aim_level", 0)
	_agent.call("_apply_active_ability", "")
	_set_dead_visuals()
	_agent.set("collision_layer", 0)
	_agent.set("collision_mask", 0)
	_agent.set("velocity", Vector2.ZERO)
	var multiplayer_api := _agent.get_multiplayer()
	if multiplayer_api.has_multiplayer_peer() and not multiplayer_api.is_server():
		_agent.call("_emit_died_signal")

func respawn_at(spawn_position: Vector2) -> void:
	_agent.call("set_lobby_locked", false)
	_agent.call("reset_skirmish_round_abilities")
	_agent.set("global_position", spawn_position)
	_agent.set("velocity", Vector2.ZERO)
	_agent.set("is_dead", false)
	_agent.set("shop_open", false)
	_agent.set("is_movement_locked", false)
	_agent.set("last_attacker", null)
	_agent.set("combat_life_id", int(_agent.get("combat_life_id")) + 1)
	_agent.set("last_attacker_life_id", -1)
	_agent.set("last_attacker_weapon_name", "")
	(_agent.get("combat_damage_received_by_actor") as Dictionary).clear()
	(_agent.get("combat_damage_received_weapon_by_actor") as Dictionary).clear()
	(_agent.get("combat_damage_dealt_to_actor") as Dictionary).clear()
	(_agent.get("combat_damage_dealt_weapon_by_actor") as Dictionary).clear()
	(_agent.get("combat_damage_received_by_life") as Dictionary).clear()
	(_agent.get("combat_damage_received_weapon_by_life") as Dictionary).clear()
	(_agent.get("combat_damage_dealt_to_actor_by_life") as Dictionary).clear()
	_restore_alive_visuals()
	_agent.set("collision_layer", 16)
	_agent.set("collision_mask", 31)
	var health_component := _agent.get("health_component") as HealthComponent
	health_component.reset_health()
	grant_spawn_protection()
	_agent.call("_apply_active_ability", "")
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer() or multiplayer_api.is_server():
		var ability_charges: Node = _agent.get("ability_charges")
		if ability_charges and ability_charges.has_method("reset_life_ability_charges"):
			ability_charges.call("reset_life_ability_charges")
	var weapon_controller: Node = _agent.get("weapon_controller")
	weapon_controller.call("reset_after_respawn")
	if not multiplayer_api.has_multiplayer_peer() or _agent.is_multiplayer_authority():
		_agent.call("focus_local_camera")
	_agent.call(
		"configure_network_visuals",
		not multiplayer_api.has_multiplayer_peer() or _agent.is_multiplayer_authority()
	)
	_agent.emit_signal("respawned")

func begin_sage_revival(update_health: bool) -> void:
	if not bool(_agent.get("is_dead")):
		return
	_agent.set("is_dead", false)
	_agent.set("is_movement_locked", true)
	_agent.set("last_attacker", null)
	_agent.set("last_attacker_weapon_name", "")
	_agent.set("velocity", Vector2.ZERO)
	_agent.set("collision_layer", 16)
	_agent.set("collision_mask", 31)
	_restore_alive_visuals()
	var player_camera := _agent.get("player_camera") as Camera2D
	var lights := _agent.get_node_or_null("Visuals/Lights") as CanvasItem
	if lights:
		lights.visible = player_camera != null and player_camera.enabled
	var gradient := _agent.get_node_or_null("Visuals/BodySprite/ResurrectionGradient") as Sprite2D
	if gradient:
		var body_sprite := _agent.get_node_or_null("Visuals/BodySprite") as Sprite2D
		if (
			body_sprite
			and gradient.material is ShaderMaterial
			and body_sprite.texture
		):
			(gradient.material as ShaderMaterial).set_shader_parameter(
				"agent_texture", body_sprite.texture
			)
		var base_modulate: Color = _agent.get("resurrection_gradient_base_modulate")
		gradient.modulate = base_modulate
		gradient.modulate.a = base_modulate.a
		gradient.visible = true
		var tween := _agent.create_tween()
		tween.tween_property(gradient, "modulate:a", 0.0, 2.5)
	if update_health:
		var health_component := _agent.get("health_component") as HealthComponent
		health_component.restore_state(100.0, 0.0)

func finish_sage_revival() -> void:
	var gradient := _agent.get_node_or_null("Visuals/BodySprite/ResurrectionGradient") as Sprite2D
	if gradient:
		var tween := gradient.create_tween()
		tween.tween_property(gradient, "modulate:a", 0.0, 0.1)
		tween.tween_callback(func() -> void:
			gradient.visible = false
			gradient.modulate = _agent.get("resurrection_gradient_base_modulate")
		)
	if bool(_agent.get("is_dead")):
		return
	_agent.set("is_movement_locked", false)

func _set_dead_visuals() -> void:
	_agent.call("clear_healing_statuses")
	_agent.set("visible", true)
	var visuals := _agent.get_node_or_null("Visuals") as CanvasItem
	var circle := _agent.get_node_or_null("Visuals/AgentCircle") as CanvasItem
	var direction_marker := _agent.get_node_or_null("Visuals/Polygon2D") as CanvasItem
	var body_sprite := _agent.get_node_or_null("Visuals/BodySprite") as Sprite2D
	var weapon_pivot := _agent.get_node_or_null("Visuals/BodySprite/WeaponPivot") as CanvasItem
	var healing_sprite := _agent.get_node_or_null("Visuals/AbilityIndicator") as Sprite2D
	var resurrection_gradient := _agent.get_node_or_null("Visuals/BodySprite/ResurrectionGradient") as Sprite2D
	var lights := _agent.get_node_or_null("Visuals/Lights") as CanvasItem
	var flashed := _agent.get_node_or_null("Visuals/Flashed") as CanvasItem
	var damage_indicator := _agent.get_node_or_null("DamageIndicator") as Sprite2D
	if visuals:
		visuals.visible = true
	if circle:
		circle.visible = false
	if direction_marker:
		direction_marker.visible = false
	if body_sprite:
		var base_modulate: Color = _agent.get("body_sprite_base_modulate")
		base_modulate.a *= 0.4
		body_sprite.modulate = base_modulate
		body_sprite.visible = true
	if weapon_pivot:
		weapon_pivot.visible = false
	if healing_sprite:
		healing_sprite.visible = false
	(_agent.get("sage_healing_visual_effects") as Dictionary).clear()
	(_agent.get("sage_healing_preview_effects") as Dictionary).clear()
	(_agent.get("sage_resurrection_visual_effects") as Dictionary).clear()
	_agent.call("_update_ability_indicator")
	if resurrection_gradient:
		resurrection_gradient.visible = false
	if lights:
		lights.visible = false
	if flashed:
		flashed.visible = false
	if damage_indicator:
		damage_indicator.visible = false

func _restore_alive_visuals() -> void:
	_agent.set("visible", true)
	var visuals := _agent.get_node_or_null("Visuals") as CanvasItem
	var circle := _agent.get_node_or_null("Visuals/AgentCircle") as CanvasItem
	var direction_marker := _agent.get_node_or_null("Visuals/Polygon2D") as CanvasItem
	var body_sprite := _agent.get_node_or_null("Visuals/BodySprite") as Sprite2D
	var weapon_pivot := _agent.get_node_or_null("Visuals/BodySprite/WeaponPivot") as CanvasItem
	var healing_sprite := _agent.get_node_or_null("Visuals/AbilityIndicator") as Sprite2D
	var resurrection_gradient := _agent.get_node_or_null("Visuals/BodySprite/ResurrectionGradient") as Sprite2D
	var lights := _agent.get_node_or_null("Visuals/Lights") as CanvasItem
	var flashed := _agent.get_node_or_null("Visuals/Flashed") as CanvasItem
	var damage_indicator := _agent.get_node_or_null("DamageIndicator") as Sprite2D
	if visuals:
		visuals.visible = true
	if circle:
		circle.visible = true
	if direction_marker:
		direction_marker.visible = true
	if body_sprite:
		body_sprite.modulate = _agent.get("body_sprite_base_modulate")
		body_sprite.visible = true
	if weapon_pivot:
		weapon_pivot.visible = true
	if healing_sprite:
		healing_sprite.visible = false
		(_agent.get("sage_healing_visual_effects") as Dictionary).clear()
		(_agent.get("sage_healing_preview_effects") as Dictionary).clear()
	(_agent.get("sage_resurrection_visual_effects") as Dictionary).clear()
	_agent.call("_update_ability_indicator")
	if resurrection_gradient:
		resurrection_gradient.visible = false
		resurrection_gradient.modulate = _agent.get("resurrection_gradient_base_modulate")
	if lights:
		lights.visible = true
	if flashed:
		flashed.visible = false
	if damage_indicator:
		damage_indicator.visible = false

func grant_spawn_protection() -> void:
	_agent.set("spawn_protection_time_remaining", SPAWN_PROTECTION_DURATION)
	var current_tween := _agent.get("spawn_protection_tween") as Tween
	if current_tween and current_tween.is_running():
		current_tween.kill()
	var visuals := _agent.get("visuals") as CanvasItem
	var base_alpha := float(_agent.get("visuals_base_alpha"))
	visuals.modulate.a = base_alpha
	var tween := _agent.create_tween()
	_agent.set("spawn_protection_tween", tween)
	for _flash_index in range(7):
		tween.tween_property(visuals, "modulate:a", base_alpha * 0.2, 0.1)
		tween.tween_property(visuals, "modulate:a", base_alpha, 0.1)

func is_spawn_protected() -> bool:
	return float(_agent.get("spawn_protection_time_remaining")) > 0.0

func process(delta: float) -> void:
	var remaining := float(_agent.get("spawn_protection_time_remaining"))
	if remaining <= 0.0:
		return
	remaining = maxf(0.0, remaining - delta)
	_agent.set("spawn_protection_time_remaining", remaining)
	if remaining == 0.0:
		var tween := _agent.get("spawn_protection_tween") as Tween
		if tween and tween.is_running():
			tween.kill()
		var visuals := _agent.get("visuals") as CanvasItem
		visuals.modulate.a = float(_agent.get("visuals_base_alpha"))
