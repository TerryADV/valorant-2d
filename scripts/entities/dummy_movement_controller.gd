extends RefCounted

var _dummy: Node
var _available_weapons: Array[WeaponData] = []

func setup(dummy: Node, available_weapons: Array[WeaponData]) -> void:
	_dummy = dummy
	_available_weapons = available_weapons

func process_authoritative_movement(delta: float) -> void:
	if bool(_dummy.get("is_dead")):
		return
	var body := _dummy as CharacterBody2D
	if bool(_dummy.get("is_match_preparing")):
		body.velocity = Vector2.ZERO
		body.move_and_slide()
		return
	var visuals := _dummy.get("visuals") as Node2D
	if float(_dummy.get("flash_time_remaining")) > 0.0:
		body.velocity = Vector2.ZERO
		body.move_and_slide()
		return
	var multiplayer_api := _dummy.get_multiplayer()
	if multiplayer_api.has_multiplayer_peer() and not bool(_dummy.get("network_weapon_synced")):
		_dummy.set("network_weapon_synced", true)
		var initial_dummy_controller := _dummy.get("_dummy_controller") as RefCounted
		initial_dummy_controller.call_weapon("play_weapon_cue", [0, body.global_position])
		var weapon_to_sync := _dummy.get("current_weapon") as WeaponData
		_dummy.rpc("sync_weapon_selection", _available_weapons.find(weapon_to_sync))
	var dummy_controller := _dummy.get("_dummy_controller") as RefCounted
	dummy_controller.call_combat("process_combat", [delta])
	dummy_controller.call_movement("process_footsteps", [delta])
	var navigation_agent := _dummy.get("navigation_agent") as NavigationAgent2D
	var navigation_map := navigation_agent.get_navigation_map()
	if not navigation_map.is_valid():
		body.velocity = Vector2.ZERO
		if not bool(_dummy.get("navigation_error_reported")):
			push_error("Dummy cannot wander because it has no valid navigation map.")
			_dummy.set("navigation_error_reported", true)
		return
	if not NavigationServer2D.map_is_active(navigation_map):
		body.velocity = Vector2.ZERO
		return
	if NavigationServer2D.map_get_iteration_id(navigation_map) == 0:
		body.velocity = Vector2.ZERO
		return

	var target_actor := _dummy.get("target_actor") as Node2D
	var target_is_known := (
		bool(dummy_controller.call_combat("is_combat_target_valid", [target_actor]))
		and bool(_dummy.get("has_last_known_target_position"))
	)
	var has_wander_target := bool(_dummy.get("has_wander_target"))
	if target_is_known:
		_dummy.set("wait_time_remaining", 0.0)
		var last_known_position := Vector2(_dummy.get("last_known_target_position"))
		if (
			not has_wander_target
			or navigation_agent.target_position.distance_to(last_known_position) > 12.0
		):
			navigation_agent.target_position = last_known_position
			_dummy.set("has_wander_target", true)
	elif float(_dummy.get("wait_time_remaining")) > 0.0:
		_dummy.set(
			"wait_time_remaining",
			maxf(0.0, float(_dummy.get("wait_time_remaining")) - delta)
		)
		body.velocity = body.velocity.move_toward(Vector2.ZERO, float(_dummy.get("friction")) * delta)
		body.move_and_slide()
		return
	elif bool(dummy_controller.call_combat("is_combat_target_valid", [target_actor])):
		if (
			not has_wander_target
			or navigation_agent.target_position.distance_to(target_actor.global_position) > 12.0
		):
			navigation_agent.target_position = target_actor.global_position
			_dummy.set("has_wander_target", true)
	elif not has_wander_target and not choose_wander_target(navigation_map):
		body.velocity = Vector2.ZERO
		return

	var next_path_position := navigation_agent.get_next_path_position()
	var hazard_avoidance := Vector2.ZERO
	for hazard in _dummy.get_tree().get_nodes_in_group("dummy_hazards"):
		if (
			not is_instance_valid(hazard)
			or not hazard.has_method("get_dummy_avoidance_direction")
		):
			continue
		var hazard_direction: Vector2 = hazard.call(
			"get_dummy_avoidance_direction",
			body,
			body.global_position,
			next_path_position
		)
		hazard_avoidance += hazard_direction
	var is_avoiding_hazard := hazard_avoidance.length_squared() > 0.001
	if navigation_agent.is_navigation_finished() and not is_avoiding_hazard:
		body.velocity = Vector2.ZERO
		body.move_and_slide()
		if bool(dummy_controller.call_combat("can_attack_target")):
			return
		if target_is_known:
			visuals.rotation += delta * 0.8
			return
		_dummy.set("has_wander_target", false)
		_dummy.set(
			"wait_time_remaining",
			randf_range(
				float(_dummy.get("min_wait_time")),
				maxf(float(_dummy.get("min_wait_time")), float(_dummy.get("max_wait_time")))
			)
		)
		return

	var can_attack_target := bool(dummy_controller.call_combat("can_attack_target"))
	if can_attack_target and not is_avoiding_hazard:
		body.velocity = body.velocity.move_toward(Vector2.ZERO, float(_dummy.get("friction")) * delta)
		body.move_and_slide()
		return
	var direction := (
		hazard_avoidance.normalized()
		if is_avoiding_hazard
		else body.global_position.direction_to(next_path_position)
	)
	var current_weapon := _dummy.get("current_weapon") as WeaponData
	var weapon_speed_multiplier := current_weapon.run_speed_multiplier if current_weapon else 1.0
	var slow_zone_sources: Dictionary = _dummy.get("slow_zone_sources")
	if not slow_zone_sources.is_empty():
		weapon_speed_multiplier *= 0.5
	body.velocity = body.velocity.move_toward(
		direction * float(_dummy.get("run_speed")) * weapon_speed_multiplier,
		float(_dummy.get("acceleration")) * delta
	)
	if not bool(dummy_controller.call_combat("can_attack_target")):
		visuals.rotation = body.velocity.angle() + PI / 2.0
	body.move_and_slide()

func process_footsteps(delta: float) -> void:
	var multiplayer_api := _dummy.get_multiplayer()
	if multiplayer_api.has_multiplayer_peer() and not multiplayer_api.is_server():
		return
	var body := _dummy as CharacterBody2D
	var remaining := float(_dummy.get("footstep_time_remaining"))
	if body.velocity.length() < 8.0:
		_dummy.set("footstep_time_remaining", 0.0)
		return
	remaining -= delta
	if remaining > 0.0:
		_dummy.set("footstep_time_remaining", remaining)
		return
	_dummy.set("footstep_time_remaining", float(_dummy.get("footstep_interval")))
	var slow_zone_sources: Dictionary = _dummy.get("slow_zone_sources")
	var footstep_cue: StringName = &"slow_orb_step" if not slow_zone_sources.is_empty() else &"steps"
	AudioManager.play_event_world(footstep_cue, body.global_position)
	if multiplayer_api.has_multiplayer_peer():
		_dummy.rpc("sync_dummy_footstep", body.global_position)

func sync_state(
	world_position: Vector2,
	movement_velocity: Vector2,
	visual_rotation: float
) -> void:
	if not bool((_dummy.get("_dummy_controller") as RefCounted).is_server_rpc_sender()):
		return
	if (
		not world_position.is_finite()
		or not movement_velocity.is_finite()
		or not is_finite(visual_rotation)
	):
		push_warning("Rejected a dummy state update with invalid values.")
		return
	_dummy.call("apply_network_transform", world_position, movement_velocity, visual_rotation)

func sync_footstep(world_position: Vector2) -> void:
	if not bool((_dummy.get("_dummy_controller") as RefCounted).is_server_rpc_sender()):
		return
	if not world_position.is_finite():
		push_warning("Rejected a dummy footstep at a non-finite position.")
		return
	var slow_zone_sources: Dictionary = _dummy.get("slow_zone_sources")
	var footstep_cue: StringName = &"slow_orb_step" if not slow_zone_sources.is_empty() else &"steps"
	AudioManager.play_event_world(footstep_cue, world_position)

func choose_wander_target(navigation_map: RID) -> bool:
	if NavigationServer2D.map_get_regions(navigation_map).is_empty():
		if not bool(_dummy.get("navigation_error_reported")):
			push_error("Dummy cannot wander because its navigation map has no regions.")
			_dummy.set("navigation_error_reported", true)
		return false
	var navigation_agent := _dummy.get("navigation_agent") as NavigationAgent2D
	navigation_agent.target_position = NavigationServer2D.map_get_random_point(
		navigation_map,
		navigation_agent.navigation_layers,
		true
	)
	_dummy.set("has_wander_target", true)
	return true
