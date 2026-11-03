extends RefCounted

var _manager: Node
var _port := 7000
var _max_players := 11
var _max_participants := 12

func setup(manager: Node, port: int, max_players: int, max_participants: int) -> void:
	_manager = manager
	_port = port
	_max_players = max_players
	_max_participants = max_participants

func sanitize_player_name(player_name: String) -> String:
	var sanitized := player_name.strip_edges().substr(0, 24)
	return sanitized if not sanitized.is_empty() else "Player"

func set_local_player_name(player_name: String) -> void:
	var sanitized := sanitize_player_name(player_name)
	_manager.set("player_display_name", sanitized)
	if not _manager.call("is_networked"):
		return
	if _manager.get_multiplayer().is_server():
		var player_names: Dictionary = _manager.get("lobby_player_names")
		player_names[1] = sanitized
		broadcast_player_names()
	else:
		_manager.rpc_id(1, "request_player_name", sanitized)

func get_player_display_name(peer_id: int) -> String:
	var player_names: Dictionary = _manager.get("lobby_player_names")
	if player_names.has(peer_id):
		return str(player_names[peer_id])
	var local_name := str(_manager.get("player_display_name"))
	if peer_id == 1 and not local_name.strip_edges().is_empty():
		return local_name
	return "Player %d" % peer_id

func broadcast_player_names() -> void:
	var player_names: Dictionary = _manager.get("lobby_player_names")
	_manager.emit_signal("lobby_players_updated", player_names.duplicate(true))
	if _manager.call("is_networked"):
		_manager.rpc("sync_lobby_players", player_names.duplicate(true))

func receive_player_name(player_name: String, peer_id: int) -> void:
	if not _manager.get_multiplayer().is_server():
		return
	if peer_id <= 1 or not _manager.get_multiplayer().get_peers().has(peer_id):
		return
	var player_names: Dictionary = _manager.get("lobby_player_names")
	player_names[peer_id] = sanitize_player_name(player_name)
	broadcast_player_names()
	var human_count := get_connected_peer_ids().size()
	_manager.rpc_id(peer_id, "sync_lobby_state", human_count, bool(_manager.get("match_started")))

func apply_player_names(player_names: Dictionary) -> void:
	if not _manager.get("_peer_lifecycle").is_server_rpc_sender():
		return
	_manager.set("lobby_player_names", player_names.duplicate(true))
	_manager.emit_signal("lobby_players_updated", _manager.get("lobby_player_names").duplicate(true))

func create_skirmish_room(port: int) -> Error:
	if _manager.get("peer") != null or _manager.get("connection_pending"):
		return ERR_BUSY
	var error: Error = _manager.get("_network_session").host(
		port, 3, _manager.get_multiplayer()
	) as Error
	if error != OK:
		return error
	_manager.set("match_started", false)
	_manager.get("lobby_player_names").clear()
	_manager.get("skirmish_team_assignments").clear()
	_manager.get("skirmish_position_assignments").clear()
	_manager.emit_signal("skirmish_teams_changed", _manager.get("skirmish_team_assignments").duplicate(true))
	set_local_player_name(str(_manager.get("player_display_name")))
	publish_lobby_state()
	return OK

func create_deathmatch_room(port: int) -> Error:
	if _manager.get("peer") != null or _manager.get("connection_pending"):
		return ERR_BUSY
	var error: Error = _manager.get("_network_session").host(
		port, _max_players, _manager.get_multiplayer()
	) as Error
	if error != OK:
		return error
	_manager.get("_match_flow").mark_deathmatch_room_ready(true)
	_manager.set("match_started", false)
	_manager.set("deathmatch_room_dummy_count", _max_participants - 1)
	_manager.set("deathmatch_room_dummy_difficulty", BaseAgent.Difficulty.HARD)
	_ensure_local_agent_selection()
	_manager.get("lobby_player_names").clear()
	_manager.get("deathmatch_scores").clear()
	_manager.get("deathmatch_deaths").clear()
	set_local_player_name(str(_manager.get("player_display_name")))
	publish_lobby_state()
	return OK

func leave_deathmatch_room() -> void:
	if not _manager.call("is_networked"):
		return
	_manager.call("disconnect_game")
	_manager.get("_match_flow").on_menu_deathmatch_room_closed()
	_manager.get("lobby_player_names").clear()
	_manager.set("match_started", false)

func refresh_deathmatch_room_bot_count() -> void:
	if not _manager.get_multiplayer().has_multiplayer_peer() or not _manager.get_multiplayer().is_server():
		return
	var maximum_bots := maxi(0, _max_participants - get_connected_peer_ids().size())
	var room_bot_count := mini(int(_manager.get("deathmatch_room_dummy_count")), maximum_bots)
	_manager.set("deathmatch_room_dummy_count", room_bot_count)
	if _manager.get_multiplayer().get_peers().size() > 0:
		_manager.rpc(
			"sync_deathmatch_room_settings",
			room_bot_count,
			int(_manager.get("deathmatch_room_dummy_difficulty"))
		)

func host_game() -> Error:
	if _manager.get("peer") != null or _manager.get("connection_pending"):
		return ERR_BUSY
	if not _manager.call("get_spawn_marker"):
		return ERR_DOES_NOT_EXIST
	var error := _manager.get("_network_session").host(_port, _max_players, _manager.get_multiplayer()) as Error
	if error != OK:
		return error

	_manager.set("match_started", false)
	var scores: Dictionary = _manager.get("deathmatch_scores")
	var deaths: Dictionary = _manager.get("deathmatch_deaths")
	scores.clear()
	deaths.clear()
	_manager.get("_player_service").prepare_current_scene()
	var current_scene := _manager.get_tree().current_scene
	var host_agent: BaseAgent = null
	if current_scene:
		host_agent = _manager.call("get_local_agent", current_scene) as BaseAgent
	if host_agent and host_agent.agent_data:
		_manager.set("selected_agent_id", host_agent.agent_data.agent_id)
	if host_agent:
		host_agent.set_lobby_locked(true)
		host_agent.visible = false
	var hud := current_scene.get_node_or_null("HUD") as CanvasLayer if current_scene else null
	if hud:
		hud.visible = false
	publish_lobby_state()
	_manager.emit_signal("connected")
	return OK

func start_lan_match(dummy_count: int, dummy_difficulty: int) -> Error:
	var multiplayer_api := _manager.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer() or not multiplayer_api.is_server():
		return ERR_UNAUTHORIZED
	if _manager.get("match_started"):
		return ERR_BUSY
	if _manager.get("_match_flow").is_transition_pending():
		return ERR_BUSY
	if dummy_difficulty < BaseAgent.Difficulty.EASY or dummy_difficulty > BaseAgent.Difficulty.HARD:
		return ERR_INVALID_PARAMETER
	var peer_ids := get_connected_peer_ids()
	var maximum_room_bots := maxi(0, _max_participants - peer_ids.size())
	if dummy_count < 0 or dummy_count > maximum_room_bots:
		return ERR_INVALID_PARAMETER
	_ensure_local_agent_selection()
	_manager.set("lan_dummy_count", dummy_count)
	_manager.set("lan_dummy_difficulty", dummy_difficulty)
	_manager.set("deathmatch_room_dummy_count", dummy_count)
	_manager.set("deathmatch_room_dummy_difficulty", dummy_difficulty)
	_manager.set("match_started", true)
	# Use the same authoritative transition RPC for host and clients, as Skirmish does.
	_manager.rpc("begin_deathmatch_map_start", dummy_count, dummy_difficulty)
	return OK

func request_deathmatch_match_start(peer_id: int) -> void:
	if not _manager.get_multiplayer().is_server() or peer_id <= 1:
		return
	if not _manager.get_multiplayer().get_peers().has(peer_id):
		return
	if not _manager.get("match_started"):
		return
	_manager.rpc_id(
		peer_id,
		"begin_deathmatch_map_start",
		int(_manager.get("lan_dummy_count")),
		int(_manager.get("lan_dummy_difficulty"))
	)

func complete_lan_match_start() -> void:
	if not _manager.get_multiplayer().is_server() or not _manager.get("match_started"):
		return
	var match_loading_service: Node = _manager.get("_match_loading_service")
	if match_loading_service.is_initializing_match():
		return
	match_loading_service.set_initializing_match(true)
	var peer_ids := get_connected_peer_ids()
	var human_count := peer_ids.size()
	var dummy_count := int(_manager.get("lan_dummy_count"))
	var dummy_difficulty := int(_manager.get("lan_dummy_difficulty"))
	var match_agent_id := _ensure_local_agent_selection()
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		match_loading_service.set_initializing_match(false)
		return
	var spawn_positions: Dictionary = {}
	var scene_agent := _manager.call("get_local_agent", current_scene) as BaseAgent
	for peer_id in peer_ids:
		var spawn_marker := _manager.call("get_spawn_marker") as Marker2D
		if not spawn_marker:
			_manager.set("match_started", false)
			match_loading_service.set_initializing_match(false)
			push_error("[MatchStart] Could not find a unique spawn for peer %d." % peer_id)
			_manager.get("_match_loading_service").rpc("finish_match_loading")
			return
		spawn_positions[peer_id] = spawn_marker.global_position
		if int(peer_id) == 1 and scene_agent:
			scene_agent.set_lobby_locked(false)
			scene_agent.skirmish_team = int(_manager.call("get_skirmish_team_for_peer", peer_id))
			scene_agent.configure_agent(_manager.call("get_agent_data", match_agent_id))
			scene_agent.set_multiplayer_authority(peer_id)
			scene_agent.global_position = spawn_marker.global_position
			scene_agent.velocity = Vector2.ZERO
			scene_agent.visible = true
			scene_agent.configure_network_visuals(true)
			scene_agent.focus_local_camera()
			_manager.get("_weapon_service").apply_weapon_slot(
				scene_agent, _manager.call("get_player_weapon_slot", peer_id)
			)
			scene_agent.grant_spawn_protection()
		else:
			_manager.rpc(
				"spawn_player", peer_id, spawn_marker.global_position,
				_manager.call("get_player_weapon_slot", peer_id),
				match_agent_id
			)
		await _manager.get_tree().process_frame
		if not _manager.get("match_started"):
			match_loading_service.set_initializing_match(false)
			return
	await _manager.get("_match_services").get_preparation_service().update_dummy_population_async(
		human_count, dummy_count, dummy_difficulty
	)
	if not _manager.get("match_started"):
		match_loading_service.set_initializing_match(false)
		return
	var current_peer_ids: Array = get_connected_peer_ids()
	for peer_id in current_peer_ids:
		if not spawn_positions.has(peer_id):
			var spawn_marker := _manager.call("get_spawn_marker") as Marker2D
			if spawn_marker:
				spawn_positions[peer_id] = spawn_marker.global_position
	_manager.get("_deathmatch_service").publish_scores()
	_manager.get("_match_flow").show_match_hud()
	match_loading_service.set_initializing_match(false)
	_manager.get("_match_loading_service").rpc("finish_match_loading")
	_manager.rpc("notify_match_started")
	publish_lobby_state()

func _ensure_local_agent_selection() -> String:
	var selected_id := str(_manager.get("selected_agent_id"))
	if _manager.call("get_agent_data", selected_id) != null:
		return selected_id
	var current_scene := _manager.get_tree().current_scene
	var local_agent := _manager.call("get_local_agent", current_scene) as BaseAgent if current_scene else null
	if local_agent and local_agent.agent_data:
		selected_id = local_agent.agent_data.agent_id
	else:
		selected_id = "phoenix"
	if _manager.call("get_agent_data", selected_id) == null:
		push_error("[MatchStart] No valid agent is available for the local player.")
		return ""
	_manager.set("selected_agent_id", selected_id)
	return selected_id

func request_lobby_state(peer_id: int) -> void:
	_manager.rpc_id(peer_id, "sync_lobby_state", get_connected_peer_ids().size(), bool(_manager.get("match_started")))

func handle_lobby_state_request(peer_id: int) -> void:
	var multiplayer_api := _manager.get_multiplayer()
	if multiplayer_api.has_multiplayer_peer() and multiplayer_api.is_server():
		request_lobby_state(peer_id)

func apply_lobby_state(human_count: int, host_started: bool) -> void:
	_manager.set("match_started", host_started)
	_manager.emit_signal("lobby_state_changed", human_count, host_started)

func apply_match_started() -> void:
	_manager.set("match_started", true)
	_manager.get("_match_flow").show_match_hud()

func publish_lobby_state() -> void:
	var human_count := get_connected_peer_ids().size()
	var host_started: bool = _manager.get("match_started")
	_manager.emit_signal("lobby_state_changed", human_count, host_started)
	var multiplayer_api := _manager.get_multiplayer()
	if multiplayer_api.has_multiplayer_peer() and multiplayer_api.is_server():
		_manager.rpc("sync_lobby_state", human_count, host_started)

func publish_local_lobby_state() -> void:
	var human_count := get_connected_peer_ids().size()
	_manager.emit_signal("lobby_state_changed", human_count, bool(_manager.get("match_started")))

func get_connected_peer_ids() -> Array[int]:
	var ids: Array[int] = [1]
	var multiplayer_api := _manager.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer():
		return ids
	for peer_id in multiplayer_api.get_peers():
		ids.append(peer_id)
	return ids
