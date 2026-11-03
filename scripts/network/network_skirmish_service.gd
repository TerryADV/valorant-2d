extends RefCounted

var _manager: Node

func setup(manager: Node) -> void:
	_manager = manager

func publish_config(team_size: int, dummy_difficulty: int) -> void:
	if team_size < 1 or team_size > 2:
		return
	if dummy_difficulty < BaseAgent.Difficulty.EASY or dummy_difficulty > BaseAgent.Difficulty.HARD:
		return
	var previous_team_size := int(_manager.get("skirmish_team_size"))
	_manager.set("skirmish_team_size", team_size)
	_manager.set("skirmish_dummy_difficulty", dummy_difficulty)
	_manager.emit_signal("skirmish_config_changed", team_size, dummy_difficulty)
	if previous_team_size == 2 and team_size == 1:
		trim_teams_to_one_player()
	if _manager.call("is_networked") and _manager.get_multiplayer().is_server():
		_manager.rpc("sync_skirmish_config", team_size, dummy_difficulty)

func trim_teams_to_one_player() -> void:
	var assignments: Dictionary = _manager.get("skirmish_team_assignments")
	for team in range(2):
		var team_peer_ids: Array[int] = []
		for peer_id_value in assignments:
			if int(assignments[peer_id_value]) == team:
				team_peer_ids.append(int(peer_id_value))
		team_peer_ids.sort()
		for index in range(1, team_peer_ids.size()):
			assignments.erase(team_peer_ids[index])
			_manager.get("skirmish_position_assignments").erase(team_peer_ids[index])
	broadcast_teams()

func request_config(peer_id: int) -> void:
	if not _manager.get_multiplayer().is_server() or peer_id <= 1:
		return
	if not _manager.get_multiplayer().get_peers().has(peer_id):
		return
	_manager.rpc_id(peer_id, "sync_skirmish_config", _manager.get("skirmish_team_size"), _manager.get("skirmish_dummy_difficulty"))
	var assignments: Dictionary = _manager.get("skirmish_team_assignments")
	var positions: Dictionary = _manager.get("skirmish_position_assignments")
	_manager.rpc_id(peer_id, "sync_skirmish_teams", assignments.duplicate(true), positions.duplicate(true))

func apply_config(team_size: int, dummy_difficulty: int) -> void:
	if not _manager.get("_peer_lifecycle").is_server_rpc_sender():
		return
	if team_size < 1 or team_size > 2:
		return
	if dummy_difficulty < BaseAgent.Difficulty.EASY or dummy_difficulty > BaseAgent.Difficulty.HARD:
		return
	_manager.set("skirmish_team_size", team_size)
	_manager.set("skirmish_dummy_difficulty", dummy_difficulty)
	_manager.emit_signal("skirmish_config_changed", team_size, dummy_difficulty)

func set_local_team(team: int) -> void:
	if team < 0 or team > 1:
		return
	if not _manager.call("is_networked") or _manager.get_multiplayer().is_server():
		apply_team(1, team)
	else:
		_manager.rpc_id(1, "request_skirmish_team", team)

func set_local_position(team: int, position: int) -> void:
	if team < 0 or team > 1 or position < 0 or position >= 5:
		return
	if not _manager.call("is_networked") or _manager.get_multiplayer().is_server():
		apply_position(1, team, position)
	else:
		_manager.rpc_id(1, "request_skirmish_position", team, position)

func request_team(team: int, peer_id: int) -> void:
	if not _manager.get_multiplayer().is_server() or team < 0 or team > 1:
		return
	if peer_id <= 1 or not _manager.get_multiplayer().get_peers().has(peer_id):
		return
	apply_team(peer_id, team)

func request_position(team: int, position: int, peer_id: int) -> void:
	if not _manager.get_multiplayer().is_server() or peer_id <= 1:
		return
	if not _manager.get_multiplayer().get_peers().has(peer_id):
		return
	apply_position(peer_id, team, position)

func apply_team(peer_id: int, team: int) -> void:
	var assignments: Dictionary = _manager.get("skirmish_team_assignments")
	var max_team_players := int(_manager.get("skirmish_team_size"))
	var current_team := int(assignments.get(peer_id, -1))
	if current_team != team:
		var team_player_count := 0
		for assigned_team in assignments.values():
			if int(assigned_team) == team:
				team_player_count += 1
		if team_player_count >= max_team_players:
			return
	assignments[peer_id] = team
	if not _manager.get("skirmish_position_assignments").has(peer_id):
		_manager.get("skirmish_position_assignments")[peer_id] = _first_available_position(team)
	_manager.emit_signal("skirmish_teams_changed", assignments.duplicate(true))
	if _manager.call("is_networked") and _manager.get_multiplayer().is_server():
		_sync_teams()

func apply_position(peer_id: int, team: int, position: int) -> void:
	if team < 0 or team > 1 or position < 0 or position >= 5:
		return
	var assignments: Dictionary = _manager.get("skirmish_team_assignments")
	if int(assignments.get(peer_id, -1)) != team:
		apply_team(peer_id, team)
		if int(assignments.get(peer_id, -1)) != team:
			return
	var positions: Dictionary = _manager.get("skirmish_position_assignments")
	for assigned_peer in positions:
		if int(assigned_peer) != peer_id and int(assignments.get(int(assigned_peer), -1)) == team:
			if int(positions[assigned_peer]) == position:
				return
	positions[peer_id] = position
	_manager.emit_signal("skirmish_teams_changed", assignments.duplicate(true))
	if _manager.call("is_networked") and _manager.get_multiplayer().is_server():
		_sync_teams()

func _first_available_position(team: int) -> int:
	var positions: Dictionary = _manager.get("skirmish_position_assignments")
	var assignments: Dictionary = _manager.get("skirmish_team_assignments")
	for position in range(5):
		var occupied := false
		for peer_id in positions:
			if int(assignments.get(int(peer_id), -1)) == team and int(positions[peer_id]) == position:
				occupied = true
				break
		if not occupied:
			return position
	return 0

func _sync_teams() -> void:
	_manager.rpc(
		"sync_skirmish_teams",
		_manager.get("skirmish_team_assignments").duplicate(true),
		_manager.get("skirmish_position_assignments").duplicate(true)
	)

func broadcast_teams() -> void:
	_manager.emit_signal("skirmish_teams_changed", _manager.get("skirmish_team_assignments").duplicate(true))
	if _manager.call("is_networked") and _manager.get_multiplayer().is_server():
		_sync_teams()

func apply_teams(team_assignments: Dictionary, position_assignments: Dictionary = {}) -> void:
	if not _manager.get("_peer_lifecycle").is_server_rpc_sender():
		return
	_manager.set("skirmish_team_assignments", team_assignments.duplicate(true))
	_manager.set("skirmish_position_assignments", position_assignments.duplicate(true))
	_manager.emit_signal("skirmish_teams_changed", team_assignments.duplicate(true))

func start_match(scene_path: String) -> Error:
	if _manager.get("_match_flow").is_transition_pending():
		return ERR_BUSY
	if _manager.call("is_networked") and not _manager.get_multiplayer().is_server():
		return ERR_UNAUTHORIZED
	if not are_all_players_assigned():
		return ERR_INVALID_DATA
	var assignments: Dictionary = _manager.get("skirmish_team_assignments")
	if assignments.size() > int(_manager.get("skirmish_team_size")) * 2:
		return ERR_INVALID_DATA
	_manager.get("_skirmish_ready_peers").clear()
	_manager.set("_skirmish_match_initializing", false)
	_manager.set("match_started", true)
	if _manager.call("is_networked"):
		_manager.rpc("begin_skirmish_scene")
		return OK
	return _manager.get("_match_flow").load_skirmish_scene(scene_path)

func are_all_players_assigned() -> bool:
	var peer_ids: Array[int] = []
	if _manager.call("is_networked"):
		peer_ids.append(1)
		for peer_id in _manager.get_multiplayer().get_peers():
			peer_ids.append(int(peer_id))
	else:
		peer_ids.append(1)
	if peer_ids.is_empty():
		return false
	var assignments: Dictionary = _manager.get("skirmish_team_assignments")
	for peer_id in peer_ids:
		var team := int(assignments.get(peer_id, -1))
		if team != 0 and team != 1:
			return false
	return true

func begin_scene() -> void:
	if not _manager.get("_peer_lifecycle").is_server_rpc_sender():
		return
	_manager.set("match_started", true)
	var error: int = _manager.get("_match_flow").load_skirmish_scene(
		"res://scenes/maps/skirmish/skirmish_a.tscn"
	)
	if error != OK:
		_manager.set("match_started", false)

func on_scene_loaded() -> void:
	_manager.get("_player_service").prepare_current_scene()
	_manager.get("_match_loading_service").show_skirmish(
		0, _manager.call("get_connected_peer_ids").size()
	)
	_manager.get("_match_loading_service").pause_after_scene_change()
	if not _manager.call("is_networked"):
		await _manager.get_tree().process_frame
		_manager.get("_match_loading_service").resume_game_for_loading()
		initialize_match()
	elif _manager.get_multiplayer().is_server():
		_manager.get("_skirmish_ready_peers")[1] = true
		await _manager.get_tree().process_frame
		_manager.get("_match_loading_service").resume_game_for_loading()
		try_initialize_match()
	else:
		await _manager.get_tree().process_frame
		_manager.get("_match_loading_service").resume_game_for_loading()
		_manager.rpc_id(1, "request_skirmish_scene_ready")

func mark_scene_ready(peer_id: int) -> void:
	if not _manager.get_multiplayer().is_server():
		return
	if peer_id <= 1 or not _manager.get_multiplayer().get_peers().has(peer_id):
		return
	_manager.get("_skirmish_ready_peers")[peer_id] = true
	try_initialize_match()

func on_peer_disconnected(peer_id: int) -> void:
	if not _manager.get_multiplayer().is_server():
		return
	var ready_peers: Dictionary = _manager.get("_skirmish_ready_peers")
	if ready_peers.erase(peer_id):
		try_initialize_match()

func try_initialize_match() -> void:
	if _manager.get("_skirmish_match_initializing"):
		return
	_manager.get("_match_loading_service").rpc(
		"sync_match_loading_progress",
		_manager.get("_skirmish_ready_peers").size(),
		_manager.call("get_connected_peer_ids").size()
	)
	for peer_id in _manager.call("get_connected_peer_ids"):
		if not _manager.get("_skirmish_ready_peers").has(peer_id):
			return
	_manager.set("_skirmish_match_initializing", true)
	initialize_match()

func initialize_match() -> void:
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return
	if str(_manager.get("selected_agent_id")).is_empty():
		_manager.set("selected_agent_id", "jett")
	var mode_selector := current_scene.get_node_or_null("GameModeSelector") as GameModeSelector
	if mode_selector:
		mode_selector.selected_mode = GameModeSelector.Mode.SKIRMISH
	var assignments: Dictionary = _manager.get("skirmish_team_assignments")
	var peer_ids: Array = assignments.keys()
	peer_ids.sort()
	var used_agents_by_team: Array[Dictionary] = [{}, {}]
	var dummy_index := 0
	for team in range(2):
		var team_peer_ids: Array[int] = []
		for peer_id_value in peer_ids:
			if int(assignments[peer_id_value]) == team:
				team_peer_ids.append(int(peer_id_value))
		var team_markers := get_team_markers(current_scene, team)
		for slot_index in team_peer_ids.size():
			var peer_id := team_peer_ids[slot_index]
			if slot_index >= team_markers.size():
				continue
			var marker := team_markers[slot_index]
			var agent_id := choose_agent_id(str(_manager.get("selected_agent_id")), used_agents_by_team[team])
			if agent_id.is_empty():
				push_error("No unique agent is available for Skirmish team %d." % team)
				continue
			used_agents_by_team[team][agent_id] = true
			if _manager.call("is_networked"):
				_manager.rpc("spawn_player", peer_id, marker.global_position, 1, agent_id)
			else:
				_manager.call("spawn_player", peer_id, marker.global_position, 1, agent_id)
		for slot_index in range(team_peer_ids.size(), int(_manager.get("skirmish_team_size"))):
			if slot_index >= team_markers.size():
				continue
			var dummy_marker := team_markers[slot_index]
			var weapon_index := randi_range(0, BaseAgent.AVAILABLE_WEAPONS.size() - 1)
			var agent_index := _choose_agent_index(used_agents_by_team[team])
			if agent_index < 0:
				push_error("No unique agent is available for Skirmish team %d." % team)
				continue
			used_agents_by_team[team][BaseAgent.AVAILABLE_AGENTS[agent_index].agent_id] = true
			_manager.get("_deathmatch_service").broadcast_dummy_spawn(
				dummy_index, dummy_marker.global_position,
				weapon_index, int(_manager.get("skirmish_dummy_difficulty")), agent_index
			)
			dummy_index += 1
	var deathmatch_service: Object = _manager.get("_deathmatch_service")
	deathmatch_service.get("deathmatch_scores").clear()
	deathmatch_service.get("deathmatch_deaths").clear()
	deathmatch_service.get("respawning_peers").clear()
	_manager.get("_deathmatch_service").publish_scores()
	_manager.get("_match_flow").show_match_hud()
	if _manager.call("is_networked"):
		_manager.get("_match_loading_service").rpc("finish_match_loading")
	else:
		_manager.get("_match_loading_service").finish_offline()
	_manager.get("_skirmish_round_service").start_match()

func choose_agent_id(preferred_id: String, used_ids: Dictionary) -> String:
	var candidates: Array[String] = []
	if not preferred_id.is_empty():
		candidates.append(preferred_id)
	for agent_id_value in _manager.get("agent_data_catalog").keys():
		var agent_id := str(agent_id_value)
		if not candidates.has(agent_id):
			candidates.append(agent_id)
	for agent_id in candidates:
		if not used_ids.has(agent_id) and _manager.call("get_agent_data", agent_id):
			return agent_id
	return ""

func _choose_agent_index(used_agent_ids: Dictionary) -> int:
	var available_indices: Array[int] = []
	for index in BaseAgent.AVAILABLE_AGENTS.size():
		var agent_id := BaseAgent.AVAILABLE_AGENTS[index].agent_id
		if not used_agent_ids.has(agent_id):
			available_indices.append(index)
	if available_indices.is_empty():
		return -1
	return available_indices[randi_range(0, available_indices.size() - 1)]

func reset_round() -> void:
	if _manager.call("is_networked") and not _manager.get_multiplayer().is_server():
		return
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return
	if _manager.call("is_networked"):
		_manager.rpc("clear_skirmish_round_effects")
	else:
		clear_round_effects()
	for team in range(2):
		var team_actors: Array[Node] = []
		for actor in current_scene.get_children():
			if not actor is BaseAgent or int(actor.get("skirmish_team")) != team:
				continue
			team_actors.append(actor)
		team_actors.sort_custom(func(first: Node, second: Node) -> bool:
			if (first as BaseAgent).is_ai_dummy != (second as BaseAgent).is_ai_dummy:
				return not (first as BaseAgent).is_ai_dummy
			return int(_manager.call("get_deathmatch_actor_id", first)) < int(_manager.call("get_deathmatch_actor_id", second))
		)
		var team_markers := get_team_markers(current_scene, team)
		for index in mini(team_actors.size(), team_markers.size()):
			var actor := team_actors[index] as BaseAgent
			var spawn_position := team_markers[index].global_position
			if actor.is_ai_dummy:
				var previous_weapon_index := BaseAgent.AVAILABLE_WEAPONS.find(actor.current_weapon)
				var weapon_options := BaseAgent.AVAILABLE_WEAPONS.size()
				var weapon_index := randi_range(0, weapon_options - 1)
				if weapon_options > 1 and weapon_index == previous_weapon_index:
					weapon_index = (weapon_index + randi_range(1, weapon_options - 1)) % weapon_options
				var agent_index := actor.agent_index
				if _manager.call("is_networked"):
					actor.sync_dummy_lifecycle.rpc(true, spawn_position, weapon_index, agent_index)
				else:
					actor.sync_dummy_lifecycle(true, spawn_position, weapon_index, agent_index)
			else:
				broadcast_player_respawn(actor.get_multiplayer_authority(), spawn_position)
		for actor in team_actors:
			var agent := actor as BaseAgent
			agent.combat_damage_received_by_actor.clear()
			agent.combat_damage_dealt_to_actor.clear()
			agent.combat_damage_dealt_weapon_by_actor.clear()

func broadcast_player_respawn(peer_id: int, spawn_position: Vector2) -> void:
	if _manager.call("is_networked"):
		_manager.rpc("respawn_player", peer_id, spawn_position)
	else:
		_manager.call("respawn_player", peer_id, spawn_position)

func clear_round_effects() -> void:
	if not _manager.get("_peer_lifecycle").is_server_rpc_sender():
		return
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return
	for effect in _manager.get_tree().get_nodes_in_group("skirmish_round_effects"):
		if is_instance_valid(effect) and effect.get_tree() == _manager.get_tree():
			effect.queue_free()
	for actor in current_scene.get_children():
		if actor is BaseAgent:
			actor.clear_healing_statuses()

func get_round_winner() -> int:
	if _manager.call("is_networked") and not _manager.get_multiplayer().is_server():
		return -1
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return -1
	var team_has_living_actor := [false, false]
	for actor in current_scene.get_children():
		if not actor is BaseAgent:
			continue
		var team := int(actor.get("skirmish_team"))
		if team < 0 or team > 1:
			continue
		if not actor.is_ai_dummy and not actor.is_dead:
			team_has_living_actor[team] = true
		elif actor.is_ai_dummy and actor.is_in_match and not actor.is_dead:
			team_has_living_actor[team] = true
	if team_has_living_actor[0] and not team_has_living_actor[1]:
		return 0
	if team_has_living_actor[1] and not team_has_living_actor[0]:
		return 1
	return -1

func broadcast_round_result(winner_team: int, team_wins: Array) -> void:
	var round_stats: Dictionary = {}
	_manager.set("_skirmish_round_stats", round_stats)
	var current_scene := _manager.get_tree().current_scene
	if current_scene:
		var hud := current_scene.get_node_or_null("HUD") as GameHud
		for actor in current_scene.get_children():
			if actor is BaseAgent and not actor.is_ai_dummy:
				var peer_id := actor.get_multiplayer_authority()
				if _manager.call("is_networked") and peer_id != 1:
					_manager.rpc_id(peer_id, "request_skirmish_round_stats")
				else:
					round_stats[peer_id] = hud.call("get_skirmish_local_round_stats") if hud else {}
	if _manager.call("is_networked"):
		_manager.get_tree().create_timer(0.15).timeout.connect(func() -> void:
			var submitted_stats: Dictionary = _manager.get("_skirmish_round_stats")
			for peer_id in submitted_stats:
				round_stats[peer_id] = (submitted_stats[peer_id] as Dictionary).duplicate(true)
			_manager.rpc("sync_skirmish_round_result", winner_team, team_wins, round_stats)
		, CONNECT_ONE_SHOT)
	else:
		_manager.call("sync_skirmish_round_result", winner_team, team_wins, round_stats)

func submit_round_stats(peer_id: int, round_stats: Dictionary) -> void:
	if not _manager.call("is_networked") or not _manager.get_multiplayer().is_server():
		return
	if peer_id <= 1 or not _manager.get_multiplayer().get_peers().has(peer_id):
		return
	var current_scene := _manager.get_tree().current_scene
	var reporting_player: BaseAgent
	if current_scene:
		for actor in current_scene.get_children():
			if actor is BaseAgent and not actor.is_ai_dummy and actor.get_multiplayer_authority() == peer_id:
				reporting_player = actor
				break
	if not reporting_player:
		return
	for key in ["damage_dealt", "damage_received"]:
		if not round_stats.has(key) or not is_finite(float(round_stats[key])):
			return
	var submitted_stats: Dictionary = _manager.get("_skirmish_round_stats")
	submitted_stats[peer_id] = round_stats.duplicate(true)
	submitted_stats[peer_id]["damage_dealt"] = clampf(float(round_stats["damage_dealt"]), 0.0, 1000000.0)
	submitted_stats[peer_id]["damage_received"] = clampf(float(round_stats["damage_received"]), 0.0, 1000000.0)
	var damage_by_target: Array = round_stats.get("damage_by_target", [])
	var sanitized_details: Array = []
	for detail in damage_by_target:
		if not detail is Dictionary:
			continue
		var target_actor := _manager.call("find_deathmatch_actor", int(detail.get("actor_id", 0))) as BaseAgent
		if (
			not target_actor
			or target_actor == reporting_player
			or target_actor.skirmish_team == reporting_player.skirmish_team
			or sanitized_details.size() >= 16
		):
			continue
		var target_sprite := target_actor.get_agent_sprite() if target_actor.is_ai_dummy else (
			target_actor.agent_data.agent_sprite if target_actor.agent_data else null
		)
		sanitized_details.append({
			"actor_id": target_actor.get_deathmatch_id(),
			"life_id": int(target_actor.get("combat_life_id")),
			"sprite_path": target_sprite.resource_path if target_sprite else "",
			"outgoing": clampf(float(detail.get("outgoing", 0.0)), 0.0, 1000000.0),
			"incoming": clampf(float(detail.get("incoming", 0.0)), 0.0, 1000000.0),
			"assist_damage": clampf(float(detail.get("assist_damage", detail.get("outgoing", 0.0))), 0.0, 1000000.0),
			"weapon": str(detail.get("weapon", "")),
			"is_killer": false,
		})
	submitted_stats[peer_id]["damage_by_target"] = sanitized_details

func apply_round_result(winner_team: int, team_wins: Array, round_stats: Dictionary) -> void:
	if not _manager.get("_peer_lifecycle").is_server_rpc_sender() or team_wins.size() != 2:
		return
	_manager.emit_signal(
		"skirmish_round_result_received", winner_team, team_wins.duplicate(), round_stats.duplicate(true)
	)

func return_to_lobby() -> void:
	if _manager.call("is_networked") and not _manager.get_multiplayer().is_server():
		return
	if _manager.call("is_networked"):
		_manager.rpc("return_skirmish_to_lobby_rpc")
	else:
		apply_return_to_lobby()

func apply_return_to_lobby() -> void:
	if not _manager.get("_peer_lifecycle").is_server_rpc_sender():
		return
	_manager.get("_skirmish_round_service").stop()
	_manager.get("_skirmish_ready_peers").clear()
	_manager.set("_skirmish_match_initializing", false)
	_manager.set("match_started", false)
	_manager.get("_lobby_service").publish_lobby_state()
	var error := _manager.get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	if error != OK:
		push_error("Could not return to the lobby after Skirmish: %s" % error_string(error))

func get_team_markers(current_scene: Node, team: int) -> Array[Marker2D]:
	var team_name := "EquipA" if team == 0 else "EquipB"
	var team_node := current_scene.get_node_or_null("Spawnpoint/%s" % team_name)
	var markers: Array[Marker2D] = []
	if team_node:
		for child in team_node.get_children():
			if child is Marker2D:
				markers.append(child)
	return markers

func broadcast_round_state(round_number: int, preparing: bool, duration: float, is_recess: bool) -> void:
	if _manager.call("is_networked"):
		_manager.rpc("sync_skirmish_round_state", round_number, preparing, duration, is_recess)
	else:
		apply_round_state(round_number, preparing, duration, is_recess)

func apply_round_state(round_number: int, preparing: bool, duration: float, is_recess: bool) -> void:
	if not _manager.get("_peer_lifecycle").is_server_rpc_sender() or round_number < 1 or duration <= 0.0:
		return
	_manager.get("_skirmish_round_service").apply_state(round_number, preparing, duration, is_recess)
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return
	for actor in current_scene.get_children():
		if actor is BaseAgent:
			actor.set_lobby_locked(false)
			actor.is_match_preparing = preparing and not is_recess
			if actor.is_ai_dummy and preparing and not is_recess:
				actor.velocity = Vector2.ZERO
	if not preparing or is_recess:
		var shop := current_scene.get_node_or_null("HUD/Control/Shop") as ShopController
		if shop and shop.visible:
			shop.call("_set_shop_open", false)
	var barriers := current_scene.get_node_or_null("Barriers")
	if barriers and barriers.has_method("set_barriers_enabled"):
		barriers.call("set_barriers_enabled", preparing and not is_recess, not preparing)
	var hud := current_scene.get_node_or_null("HUD") as GameHud
	if hud:
		hud.show_skirmish_round_state(round_number, preparing, duration)

func is_round_over() -> bool:
	if _manager.call("is_networked") and not _manager.get_multiplayer().is_server():
		return false
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return false
	var team_has_participants := [false, false]
	var team_has_living_actor := [false, false]
	for actor in current_scene.get_children():
		if not actor is BaseAgent:
			continue
		var team := int(actor.get("skirmish_team"))
		if team < 0 or team > 1:
			continue
		team_has_participants[team] = true
		if not actor.is_ai_dummy and not actor.is_dead:
			team_has_living_actor[team] = true
		elif actor.is_ai_dummy and actor.is_in_match and not actor.is_dead:
			team_has_living_actor[team] = true
	return team_has_participants[0] and team_has_participants[1] and (
		not team_has_living_actor[0] or not team_has_living_actor[1]
	)

func get_team_for_position(spawn_position: Vector2) -> int:
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return -1
	var nearest_team := -1
	var nearest_distance := INF
	for team in range(2):
		for marker in get_team_markers(current_scene, team):
			var distance := marker.global_position.distance_squared_to(spawn_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_team = team
	return nearest_team
