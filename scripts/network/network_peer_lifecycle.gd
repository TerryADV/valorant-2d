extends RefCounted

var _manager: Node

func setup(manager: Node) -> void:
	_manager = manager

func on_connected_to_server() -> void:
	_manager.rpc_id(
		1,
		"request_room_mode",
		str(_manager.get("expected_room_mode")),
		bool(_manager.get("deathmatch_spectator_preference"))
	)

func on_connection_failed() -> void:
	_manager.get("_network_session").clear_connection_pending()
	_manager.emit_signal("connection_failed")
	_manager.call("disconnect_game")

func on_server_disconnected() -> void:
	_manager.get("_match_loading_service").reset_session()
	_manager.call("disconnect_game")
	_manager.get_tree().call_deferred(
		"change_scene_to_file",
		"res://scenes/ui/main_menu.tscn"
	)

func on_peer_connected(peer_id: int) -> void:
	var multiplayer_api := _manager.get_multiplayer()
	if not multiplayer_api.is_server():
		return
	await _manager.get_tree().create_timer(0.2).timeout
	if not multiplayer_api.get_peers().has(peer_id):
		return
	if not _manager.get("match_started"):
		_manager.get("_lobby_service").refresh_deathmatch_room_bot_count()
		_manager.get("_lobby_service").publish_lobby_state()
		_manager.emit_signal("peer_joined", peer_id)
		return

	_manager.get("_deathmatch_service").update_dummy_population(
		(_manager.call("get_deathmatch_active_peer_ids") as Array).size(),
		_manager.get("lan_dummy_count"),
		_manager.get("lan_dummy_difficulty")
	)
	_manager.get("_deathmatch_service").publish_scores()
	var dummies: Array[BaseAgent] = _manager.get("_deathmatch_service").get_room_dummies()
	for index in dummies.size():
		var dummy: BaseAgent = dummies[index]
		var weapon_index := BaseAgent.AVAILABLE_WEAPONS.find(dummy.current_weapon)
		var agent_index := dummy.agent_index
		_manager.rpc_id(
			peer_id, "sync_dummy_spawn",
			absi(dummy.get_deathmatch_id()) - 1,
			dummy.global_position,
			weapon_index,
			dummy.difficulty,
			agent_index
		)

	var spawn_marker := _manager.call("get_spawn_marker") as Marker2D
	if not spawn_marker:
		return
	var current_scores: Dictionary = _manager.get("deathmatch_scores")
	var current_deaths: Dictionary = _manager.get("deathmatch_deaths")
	_manager.rpc_id(
		peer_id, "sync_deathmatch_scores",
		current_scores.duplicate(true),
		current_deaths.duplicate(true)
	)
	for existing_id in _manager.call("get_deathmatch_active_peer_ids"):
		if existing_id == peer_id:
			continue
		var existing_agent := _manager.call("find_player", existing_id) as BaseAgent
		if not existing_agent:
			push_error("Cannot synchronize connected player %d because its agent is missing." % existing_id)
			continue
		var existing_agent_id := (
			existing_agent.agent_data.agent_id
			if existing_agent.agent_data
			else str(_manager.get("selected_agent_id"))
		)
		_manager.rpc_id(
			peer_id, "spawn_player",
			existing_id,
			existing_agent.global_position,
			_manager.call("get_player_weapon_slot", existing_id),
			existing_agent_id
		)
	if bool(_manager.call("is_deathmatch_spectator", peer_id)):
		_manager.rpc_id(
			peer_id,
			"sync_deathmatch_spectator_roles",
			(_manager.get("deathmatch_spectator_peers") as Dictionary).duplicate(true)
		)
		_manager.rpc_id(peer_id, "activate_local_deathmatch_spectator_rpc")
		_manager.get("_weapon_service").sync_dropped_weapons_to_peer(peer_id)
		_manager.emit_signal("peer_joined", peer_id)
		return
	_manager.rpc(
		"spawn_player",
		peer_id,
		spawn_marker.global_position,
		_manager.call("get_player_weapon_slot", peer_id),
		_manager.get("selected_agent_id")
	)
	_manager.get("_weapon_service").sync_dropped_weapons_to_peer(peer_id)
	_manager.emit_signal("peer_joined", peer_id)

func on_peer_disconnected(peer_id: int) -> void:
	if not _manager.get_multiplayer().is_server():
		return
	var was_loading_match: bool = _manager.get("_match_loading_service").is_deathmatch_loading()
	var player_names: Dictionary = _manager.get("lobby_player_names")
	player_names.erase(peer_id)
	_manager.get("deathmatch_spectator_peers").erase(peer_id)
	_manager.emit_signal(
		"deathmatch_spectators_updated",
		(_manager.get("deathmatch_spectator_peers") as Dictionary).duplicate(true)
	)
	_manager.rpc(
		"sync_deathmatch_spectator_roles",
		(_manager.get("deathmatch_spectator_peers") as Dictionary).duplicate(true)
	)
	_manager.get("_lobby_service").broadcast_player_names()
	var team_assignments: Dictionary = _manager.get("skirmish_team_assignments")
	team_assignments.erase(peer_id)
	_manager.get("skirmish_position_assignments").erase(peer_id)
	_manager.get("_skirmish_service").broadcast_teams()
	_manager.rpc("remove_player", peer_id)
	_manager.get("_match_loading_service").on_peer_disconnected(peer_id)
	_manager.get("_skirmish_service").on_peer_disconnected(peer_id)
	if was_loading_match:
		_manager.emit_signal("peer_left", peer_id)
		return
	if _manager.get("match_started"):
		_manager.get("_deathmatch_service").update_dummy_population(
			(_manager.call("get_deathmatch_active_peer_ids") as Array).size(),
			_manager.get("lan_dummy_count"),
			_manager.get("lan_dummy_difficulty")
		)
		_manager.get("_deathmatch_service").publish_scores()
	else:
		_manager.get("_lobby_service").publish_lobby_state()
	_manager.emit_signal("peer_left", peer_id)

func is_server_rpc_sender() -> bool:
	if not _manager.call("is_networked"):
		return true
	var multiplayer_api := _manager.get_multiplayer()
	var sender_id := multiplayer_api.get_remote_sender_id()
	return (
		(multiplayer_api.is_server() and (sender_id == 0 or sender_id == 1))
		or (not multiplayer_api.is_server() and sender_id == 1)
	)
