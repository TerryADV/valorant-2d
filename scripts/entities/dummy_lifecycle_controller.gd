extends RefCounted

const SPAWN_PROTECTION_DURATION := 1.5

var _dummy: Node
var _available_weapons: Array[WeaponData] = []
var _available_agents: Array[AgentData] = []

func setup(
	dummy: Node,
	available_weapons: Array[WeaponData],
	available_agents: Array[AgentData]
) -> void:
	_dummy = dummy
	_available_weapons = available_weapons
	_available_agents = available_agents

func handle_death() -> void:
	if bool(_dummy.get("is_dead")):
		return
	set_dead_state()
	var network_manager := _dummy.get_node_or_null("/root/NetworkManager")
	if not network_manager:
		return
	network_manager.call(
		"handle_dummy_death",
		_dummy,
		_dummy.get("last_attacker"),
		str(_dummy.get("last_attacker_weapon_name"))
	)

func set_dead_state(show_dead_sprite: bool = true) -> void:
	_dummy.set("is_dead", true)
	_dummy.set("visible", show_dead_sprite)
	_dummy.set("collision_layer", 0)
	_dummy.set("collision_mask", 0)
	_dummy.set("velocity", Vector2.ZERO)
	var slow_zone_sources: Dictionary = _dummy.get("slow_zone_sources")
	slow_zone_sources.clear()
	_dummy.set("spawn_protection_time_remaining", 0.0)
	var protection_tween := _dummy.get("spawn_protection_tween") as Tween
	if protection_tween and protection_tween.is_running():
		protection_tween.kill()
	var visuals := _dummy.get("visuals") as Node2D
	visuals.modulate.a = float(_dummy.get("visuals_base_alpha"))
	var circle := _dummy.get_node_or_null("Visuals/AgentCircle") as CanvasItem
	var direction_marker := _dummy.get_node_or_null("Visuals/Polygon2D") as CanvasItem
	var body_sprite := _dummy.get_node_or_null("Visuals/BodySprite") as Sprite2D
	var weapon_pivot := _dummy.get_node_or_null("Visuals/BodySprite/WeaponPivot") as CanvasItem
	var healing_sprite := _dummy.get_node_or_null("Visuals/AbilityIndicator") as Sprite2D
	var resurrection_gradient := _dummy.get_node_or_null(
		"Visuals/BodySprite/ResurrectionGradient"
	) as Sprite2D
	var flashed_sprite := _dummy.get("flashed_indicator") as Sprite2D
	if show_dead_sprite:
		visuals.visible = true
		if circle:
			circle.visible = false
		if direction_marker:
			direction_marker.visible = false
		if body_sprite:
			var base_modulate: Color = _dummy.get("body_sprite_base_modulate")
			base_modulate.a *= 0.4
			body_sprite.modulate = base_modulate
			body_sprite.visible = true
		if weapon_pivot:
			weapon_pivot.visible = false
		if healing_sprite:
			healing_sprite.visible = false
	else:
		visuals.visible = false
	if healing_sprite:
		healing_sprite.visible = false
	(_dummy.get("sage_healing_visual_effects") as Dictionary).clear()
	(_dummy.get("sage_resurrection_visual_effects") as Dictionary).clear()
	(_dummy.get("_dummy_controller") as RefCounted).update_ability_indicator()
	if resurrection_gradient:
		resurrection_gradient.visible = false
		resurrection_gradient.modulate.a = 1.0
	_dummy.set("target_actor", null)
	_dummy.set("has_last_known_target_position", false)
	(_dummy.get("_dummy_controller") as RefCounted).reset_aim()
	_dummy.set("flash_time_remaining", 0.0)
	if flashed_sprite:
		flashed_sprite.visible = false

func begin_sage_revival() -> void:
	if not _dummy.get("is_dead"):
		return
	_dummy.set("is_dead", false)
	_dummy.set("is_movement_locked", true)
	_dummy.set("last_attacker", null)
	_dummy.set("last_attacker_weapon_name", "")
	_dummy.set("velocity", Vector2.ZERO)
	_dummy.set("collision_layer", int(_dummy.get("initial_collision_layer")))
	_dummy.set("collision_mask", int(_dummy.get("initial_collision_mask")))
	var visuals := _dummy.get("visuals") as Node2D
	visuals.visible = true
	visuals.modulate.a = float(_dummy.get("visuals_base_alpha"))
	var body_sprite := _dummy.get("body_sprite") as Sprite2D
	if body_sprite:
		body_sprite.modulate = _dummy.get("body_sprite_base_modulate")
		body_sprite.visible = true
	var circle := _dummy.get("agent_circle") as CanvasItem
	if circle:
		circle.visible = true
	var direction_marker := _dummy.get_node_or_null("Visuals/Polygon2D") as CanvasItem
	if direction_marker:
		direction_marker.visible = true
	var weapon_pivot := _dummy.get_node_or_null("Visuals/BodySprite/WeaponPivot") as CanvasItem
	if weapon_pivot:
		weapon_pivot.visible = true
	var resurrection_gradient := _dummy.get_node_or_null(
		"Visuals/BodySprite/ResurrectionGradient"
	) as Sprite2D
	if resurrection_gradient:
		resurrection_gradient.modulate.a = 1.0
		resurrection_gradient.visible = true
		var tween := _dummy.create_tween()
		tween.tween_property(resurrection_gradient, "modulate:a", 0.0, 2.5)
	(_dummy.get("health_component") as HealthComponent).restore_state(100.0, 0.0)

func finish_sage_revival() -> void:
	if _dummy.get("is_dead"):
		return
	var resurrection_gradient := _dummy.get_node_or_null(
		"Visuals/BodySprite/ResurrectionGradient"
	) as Sprite2D
	if resurrection_gradient:
		var tween := _dummy.create_tween()
		tween.tween_property(resurrection_gradient, "modulate:a", 0.0, 0.1)
		tween.tween_callback(func() -> void: resurrection_gradient.visible = false)
	_dummy.set("is_movement_locked", false)

func initialize_for_match(
	spawn_position: Vector2,
	weapon: WeaponData,
	difficulty: int,
	minimum_difficulty: int,
	maximum_difficulty: int,
	agent_index: int = -1
) -> void:
	if (
		not weapon
		or not spawn_position.is_finite()
		or difficulty < minimum_difficulty
		or difficulty > maximum_difficulty
	):
		push_error("Cannot initialize a dummy with an invalid spawn or weapon.")
		return
	_dummy.set("difficulty", difficulty)
	_dummy.set("combat_life_id", int(_dummy.get("combat_life_id")) + 1)
	_dummy.set("last_attacker_life_id", -1)
	(_dummy.get("combat_damage_received_by_actor") as Dictionary).clear()
	(_dummy.get("combat_damage_received_weapon_by_actor") as Dictionary).clear()
	(_dummy.get("combat_damage_dealt_to_actor") as Dictionary).clear()
	(_dummy.get("combat_damage_dealt_weapon_by_actor") as Dictionary).clear()
	(_dummy.get("combat_damage_received_by_life") as Dictionary).clear()
	(_dummy.get("combat_damage_received_weapon_by_life") as Dictionary).clear()
	(_dummy.get("combat_damage_dealt_to_actor_by_life") as Dictionary).clear()
	if agent_index < 0 or agent_index >= _available_agents.size():
		agent_index = randi_range(0, _available_agents.size() - 1)
	_dummy.set("agent_index", agent_index)
	(_dummy.get("_dummy_controller") as RefCounted).apply_agent_appearance(agent_index)
	_dummy.set("current_weapon", weapon)
	(_dummy.get("_dummy_controller") as RefCounted).call_weapon("apply_weapon", [weapon])
	var health_component := _dummy.get("health_component") as HealthComponent
	health_component.reset_health()
	_dummy.set("global_position", spawn_position)
	_dummy.set("visible", true)
	var visuals := _dummy.get("visuals") as Node2D
	visuals.visible = true
	var circle := _dummy.get_node_or_null("Visuals/AgentCircle") as CanvasItem
	var direction_marker := _dummy.get_node_or_null("Visuals/Polygon2D") as CanvasItem
	var body_sprite := _dummy.get_node_or_null("Visuals/BodySprite") as Sprite2D
	var weapon_pivot := _dummy.get_node_or_null("Visuals/BodySprite/WeaponPivot") as CanvasItem
	var healing_sprite := _dummy.get_node_or_null("Visuals/AbilityIndicator") as Sprite2D
	if circle:
		circle.visible = true
	if direction_marker:
		direction_marker.visible = true
	if body_sprite:
		body_sprite.modulate = _dummy.get("body_sprite_base_modulate")
		body_sprite.visible = true
	if weapon_pivot:
		weapon_pivot.visible = true
	if healing_sprite:
		healing_sprite.visible = false
		(_dummy.get("sage_healing_visual_effects") as Dictionary).clear()
		(_dummy.get("_dummy_controller") as RefCounted).update_ability_indicator()
	_dummy.set("is_in_match", true)
	_dummy.set("collision_layer", int(_dummy.get("initial_collision_layer")))
	_dummy.set("collision_mask", int(_dummy.get("initial_collision_mask")))
	_dummy.set("velocity", Vector2.ZERO)
	_dummy.set("is_dead", false)
	_dummy.set("target_actor", null)
	_dummy.set("has_last_known_target_position", false)
	_dummy.set("last_attacker", null)
	_dummy.set("last_attacker_weapon_name", "")
	_dummy.set("flash_time_remaining", 0.0)
	var flashed_indicator := _dummy.get("flashed_indicator") as Sprite2D
	if flashed_indicator:
		flashed_indicator.visible = false
	_dummy.set("has_wander_target", false)
	var slow_zone_sources: Dictionary = _dummy.get("slow_zone_sources")
	slow_zone_sources.clear()
	_dummy.set("wait_time_remaining", 0.0)
	_dummy.set("shoot_cooldown", 0.0)
	_dummy.set("recoil_degrees", 0.0)
	_dummy.set("reload_time_remaining", 0.0)
	_dummy.set("aim_time_remaining", 0.0)
	_dummy.set("footstep_time_remaining", 0.0)
	_dummy.set("ammo_in_magazine", weapon.magazine_size if not weapon.is_melee else 0)
	_dummy.set("network_weapon_synced", true)
	(_dummy.get("_dummy_controller") as RefCounted).reset_aim()
	grant_spawn_protection()

func set_inactive_for_match() -> void:
	_dummy.set("is_in_match", false)
	set_dead_state(false)

func grant_spawn_protection() -> void:
	_dummy.set("spawn_protection_time_remaining", SPAWN_PROTECTION_DURATION)
	var previous_tween := _dummy.get("spawn_protection_tween") as Tween
	if previous_tween and previous_tween.is_running():
		previous_tween.kill()
	var visuals := _dummy.get("visuals") as Node2D
	var base_alpha := float(_dummy.get("visuals_base_alpha"))
	visuals.modulate.a = base_alpha
	var tween := _dummy.create_tween()
	_dummy.set("spawn_protection_tween", tween)
	for _flash_index in range(7):
		tween.tween_property(visuals, "modulate:a", base_alpha * 0.2, 0.1)
		tween.tween_property(visuals, "modulate:a", base_alpha, 0.1)

func is_spawn_protected() -> bool:
	return float(_dummy.get("spawn_protection_time_remaining")) > 0.0

func respawn_dummy() -> void:
	var dummy_id := int(_dummy.call("get_deathmatch_id"))
	var network_manager := _dummy.get_node_or_null("/root/NetworkManager")
	if not network_manager:
		return
	var spawn_marker := network_manager.call(
		"get_spawn_marker",
		_dummy,
		absi(dummy_id) - 1
	) as Node2D
	if not spawn_marker:
		return
	var spawn_position := spawn_marker.global_position
	var weapon_index := randi_range(0, _available_weapons.size() - 1)
	var agent_index := int(_dummy.get("agent_index"))
	if _dummy.get_multiplayer().has_multiplayer_peer():
		_dummy.rpc("sync_dummy_lifecycle", true, spawn_position, weapon_index, agent_index)
	else:
		_dummy.call("sync_dummy_lifecycle", true, spawn_position, weapon_index, agent_index)

func sync_lifecycle(
	is_alive: bool,
	spawn_position: Vector2,
	weapon_index: int,
	difficulty: int,
	minimum_difficulty: int,
	maximum_difficulty: int,
	agent_index: int
) -> void:
	if not bool((_dummy.get("_dummy_controller") as RefCounted).is_server_rpc_sender()):
		return
	if is_alive:
		if weapon_index < 0 or weapon_index >= _available_weapons.size():
			push_warning("Rejected dummy respawn with an invalid weapon index.")
			return
		if agent_index < 0 or agent_index >= _available_agents.size():
			push_warning("Rejected dummy respawn with an invalid agent index.")
			return
		initialize_for_match(
			spawn_position,
			_available_weapons[weapon_index],
			difficulty,
			minimum_difficulty,
			maximum_difficulty,
			agent_index
		)
	else:
		set_dead_state()

func apply_flash(duration: float) -> void:
	if duration <= 0.0 or not is_finite(duration) or bool(_dummy.get("is_dead")):
		return
	var multiplayer_api := _dummy.get_multiplayer()
	if multiplayer_api.has_multiplayer_peer() and not multiplayer_api.is_server():
		return
	if multiplayer_api.has_multiplayer_peer():
		_dummy.rpc("sync_dummy_flash", duration)
	else:
		_dummy.call("sync_dummy_flash", duration)

func sync_flash(duration: float) -> void:
	if not bool((_dummy.get("_dummy_controller") as RefCounted).is_server_rpc_sender()):
		return
	if duration <= 0.0 or not is_finite(duration) or bool(_dummy.get("is_dead")):
		return
	_dummy.set("flash_time_remaining", maxf(float(_dummy.get("flash_time_remaining")), duration))
	var flashed_indicator := _dummy.get("flashed_indicator") as Sprite2D
	if flashed_indicator:
		flashed_indicator.visible = true

func take_damage(amount: float, attacker: Node, weapon_name: String) -> void:
	var health_component := _dummy.get("health_component") as HealthComponent
	if (
		health_component
		and not bool(_dummy.get("is_dead"))
		and not bool(_dummy.get("is_match_preparing"))
		and not is_spawn_protected()
	):
		if attacker:
			if bool(_dummy.call("is_invulnerable")):
				return
			var recorded_damage := minf(
				amount,
				health_component.current_health + health_component.current_shield
			)
			_dummy.set("last_attacker", attacker)
			var attacker_life_id := 0
			for property_info in attacker.get_property_list():
				if String(property_info.get("name", "")) == "combat_life_id":
					attacker_life_id = int(attacker.get("combat_life_id"))
					break
			_dummy.set("last_attacker_life_id", attacker_life_id)
			_dummy.set("last_attacker_weapon_name", weapon_name)
			if attacker.has_method("record_combat_damage_received"):
				_dummy.call("record_combat_damage_received", attacker, recorded_damage, weapon_name)
		health_component.take_damage(amount)

func process(delta: float) -> void:
	var flash_remaining := float(_dummy.get("flash_time_remaining"))
	if flash_remaining > 0.0:
		flash_remaining = maxf(0.0, flash_remaining - delta)
		_dummy.set("flash_time_remaining", flash_remaining)
		var flashed_indicator := _dummy.get("flashed_indicator") as Sprite2D
		if flash_remaining == 0.0 and flashed_indicator:
			flashed_indicator.visible = false

	var protection_remaining := float(_dummy.get("spawn_protection_time_remaining"))
	if protection_remaining <= 0.0:
		return
	protection_remaining = maxf(0.0, protection_remaining - delta)
	_dummy.set("spawn_protection_time_remaining", protection_remaining)
	if protection_remaining == 0.0:
		var tween := _dummy.get("spawn_protection_tween") as Tween
		if tween and tween.is_running():
			tween.kill()
		var visuals := _dummy.get("visuals") as Node2D
		visuals.modulate.a = float(_dummy.get("visuals_base_alpha"))
