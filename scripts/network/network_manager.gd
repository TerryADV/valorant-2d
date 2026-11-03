extends Node

@warning_ignore("unused_signal")
signal connected
@warning_ignore("unused_signal")
signal connection_failed
@warning_ignore("unused_signal")
signal peer_joined(peer_id: int)
@warning_ignore("unused_signal")
signal peer_left(peer_id: int)
@warning_ignore("unused_signal")
signal lobby_state_changed(human_count: int, host_started: bool)
signal lobby_players_updated(player_names: Dictionary)
@warning_ignore("unused_signal")
signal skirmish_config_changed(team_size: int, dummy_difficulty: int)
signal skirmish_teams_changed(team_assignments: Dictionary)
@warning_ignore("unused_signal")
signal skirmish_round_result_received(winner_team: int, team_wins: Array, round_stats: Dictionary)
signal kill_feed_received(killer_peer_id: int, victim_peer_id: int, weapon_name: String)
signal combat_report_received(killer_name: String, killer_agent_id: String, killer_sprite_path: String, weapon_name: String, outgoing_damage: float, incoming_damage: float, damage_source_paths: Array, attacker_details: Array)
@warning_ignore("unused_signal")
signal skirmish_combat_outcome_received(
	outcome: String,
	outgoing_damage: float,
	target_actor_id: int,
	target_life_id: int
)
signal shop_purchase_rejected(item_id: String)
signal deathmatch_scores_updated(scores: Dictionary, deaths: Dictionary)
signal room_mode_mismatch(hosted_mode: String)
const PORT := 7000
const MAX_PLAYERS := 11
const MAX_DEATHMATCH_PARTICIPANTS := 12
const RESPAWN_DELAY := 3.0
const GAME_SCENE_PATH := "res://scenes/maps/ascent.tscn"
const SKIRMISH_SCENE_PATH := "res://scenes/maps/skirmish/skirmish_a.tscn"
const NETWORK_SESSION_SCRIPT := preload("res://scripts/network/network_session.gd")
var _network_session = NETWORK_SESSION_SCRIPT.new()
const MATCH_FLOW_SCRIPT := preload("res://scripts/network/network_match_flow.gd")
var _match_flow = MATCH_FLOW_SCRIPT.new()
const SHOP_SERVICE_SCRIPT := preload("res://scripts/network/network_shop_service.gd")
var _shop_service = SHOP_SERVICE_SCRIPT.new()
const DEATHMATCH_SERVICE_SCRIPT := preload("res://scripts/network/network_deathmatch_service.gd")
var _deathmatch_service = DEATHMATCH_SERVICE_SCRIPT.new()
const AGENT_CATALOG_SCRIPT := preload("res://scripts/network/network_agent_catalog.gd")
var _agent_catalog_service = AGENT_CATALOG_SCRIPT.new()
const AGENT_SELECTION_SCRIPT := preload("res://scripts/network/network_agent_selection_service.gd")
const LOBBY_SERVICE_SCRIPT := preload("res://scripts/network/network_lobby_service.gd")
var _lobby_service = LOBBY_SERVICE_SCRIPT.new()
const PEER_LIFECYCLE_SCRIPT := preload("res://scripts/network/network_peer_lifecycle.gd")
var _peer_lifecycle = PEER_LIFECYCLE_SCRIPT.new()
const AUDIO_SERVICE_SCRIPT := preload("res://scripts/network/network_audio_service.gd")
var _audio_service = AUDIO_SERVICE_SCRIPT.new()
const SKIRMISH_ROUND_SERVICE_SCRIPT := preload("res://scripts/network/network_skirmish_round_service.gd")
var _skirmish_round_service = SKIRMISH_ROUND_SERVICE_SCRIPT.new()
const SKIRMISH_SERVICE_SCRIPT := preload("res://scripts/network/network_skirmish_service.gd")
var _skirmish_service = SKIRMISH_SERVICE_SCRIPT.new()
const NETWORK_MATCH_SERVICES_SCRIPT := preload("res://scripts/network/network_match_services.gd")
var _match_services: Node
var _player_service: RefCounted:
	get:
		return _match_services.get_player_service() if _match_services else null
var _weapon_service: RefCounted:
	get:
		return _match_services.get_weapon_service() if _match_services else null
var _agent_selection_service: RefCounted:
	get:
		return _match_services.get_agent_selection_service() if _match_services else null

@warning_ignore("unused_private_class_variable")
var _match_loading_service: Node:
	get:
		return _match_services.get_loading_service() if _match_services else null
var peer: ENetMultiplayerPeer:
	get:
		return _network_session.peer
var connection_pending: bool:
	get:
		return _network_session.connection_pending
var expected_room_mode := "deathmatch"
var hosted_room_mode := ""
var match_started := false
var player_display_name := "Player"
var lobby_player_names: Dictionary = {}
var skirmish_team_size := 1
var skirmish_dummy_difficulty: int = BaseAgent.Difficulty.HARD
var skirmish_team_assignments: Dictionary = {}
@warning_ignore("unused_private_class_variable")
var _skirmish_ready_peers: Dictionary = {}
@warning_ignore("unused_private_class_variable")
var _skirmish_round_stats: Dictionary = {}
@warning_ignore("unused_private_class_variable")
var _skirmish_match_initializing := false
var lan_dummy_count := MAX_DEATHMATCH_PARTICIPANTS - 1
var lan_dummy_difficulty: int = BaseAgent.Difficulty.HARD
var deathmatch_room_dummy_count := MAX_DEATHMATCH_PARTICIPANTS - 1
var deathmatch_room_dummy_difficulty: int = BaseAgent.Difficulty.HARD
var selected_agent_id: String:
	get:
		return _agent_selection_service.selected_agent_id
	set(value):
		_agent_selection_service.selected_agent_id = value

var pending_weapon_slots: Dictionary:
	get:
		return _weapon_service.pending_weapon_slots
var deathmatch_scores: Dictionary:
	get:
		return _deathmatch_service.deathmatch_scores
var deathmatch_deaths: Dictionary:
	get:
		return _deathmatch_service.deathmatch_deaths
var respawning_peers: Dictionary:
	get:
		return _deathmatch_service.respawning_peers

var agent_data_catalog: Dictionary:
	get:
		return _agent_catalog_service.agent_data_catalog
func _ready() -> void:
	_agent_catalog_service.load_catalog()
	_shop_service.setup(self)
	_match_flow.setup(self)
	_deathmatch_service.setup(self, MAX_DEATHMATCH_PARTICIPANTS, RESPAWN_DELAY)
	_lobby_service.setup(self, PORT, MAX_PLAYERS, MAX_DEATHMATCH_PARTICIPANTS)
	_peer_lifecycle.setup(self)
	_audio_service.setup(self)
	_skirmish_round_service.setup(self)
	_skirmish_service.setup(self)
	_match_services = NETWORK_MATCH_SERVICES_SCRIPT.new()
	_match_services.name = "MatchServices"
	add_child(_match_services)
	_match_services.setup(self)
	_deathmatch_service.scores_updated.connect(func(scores: Dictionary, deaths: Dictionary) -> void:
		deathmatch_scores_updated.emit(scores, deaths)
	)
	multiplayer.peer_connected.connect(_peer_lifecycle.on_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_lifecycle.on_peer_disconnected)
	multiplayer.server_disconnected.connect(_peer_lifecycle.on_server_disconnected)
	multiplayer.connected_to_server.connect(_peer_lifecycle.on_connected_to_server)
	multiplayer.connection_failed.connect(_peer_lifecycle.on_connection_failed)
	get_tree().scene_changed.connect(_match_flow.on_scene_changed)

func set_local_player_name(player_name: String) -> void:
	_lobby_service.set_local_player_name(player_name)
func get_player_display_name(peer_id: int) -> String:
	return _lobby_service.get_player_display_name(peer_id)
func publish_skirmish_config(team_size: int, dummy_difficulty: int) -> void:
	_skirmish_service.publish_config(team_size, dummy_difficulty)
@rpc("any_peer", "reliable")
func request_skirmish_config() -> void:
	_skirmish_service.request_config(multiplayer.get_remote_sender_id())
@rpc("authority", "call_remote", "reliable")
func sync_skirmish_config(team_size: int, dummy_difficulty: int) -> void:
	_skirmish_service.apply_config(team_size, dummy_difficulty)
func set_local_skirmish_team(team: int) -> void:
	_skirmish_service.set_local_team(team)
@rpc("any_peer", "reliable")
func request_skirmish_team(team: int) -> void:
	_skirmish_service.request_team(team, multiplayer.get_remote_sender_id())
@rpc("authority", "call_remote", "reliable")
func sync_skirmish_teams(team_assignments: Dictionary) -> void:
	_skirmish_service.apply_teams(team_assignments)
@rpc("any_peer", "reliable")
func request_player_name(player_name: String) -> void:
	_lobby_service.receive_player_name(player_name, multiplayer.get_remote_sender_id())
@rpc("authority", "call_remote", "reliable")
func sync_lobby_players(player_names: Dictionary) -> void:
	_lobby_service.apply_player_names(player_names)
func get_agent_data(agent_id: String) -> AgentData:
	return _agent_catalog_service.get_agent_data(agent_id)

func set_selected_agent(agent_id: String) -> bool:
	return _agent_selection_service.set_selected_agent(agent_id)

@rpc("any_peer", "reliable")
func request_agent_selection(agent_id: String) -> void:
	_agent_selection_service.request_agent_selection(agent_id, multiplayer.get_remote_sender_id())

@rpc("authority", "call_local", "reliable")
func sync_agent_selection(peer_id: int, agent_id: String, spawn_position: Vector2) -> void:
	_agent_selection_service.sync_agent_selection(peer_id, agent_id, spawn_position)

func load_match_scene(open_local_lobby: bool) -> Error:
	return _match_flow.load_match_scene(
		GAME_SCENE_PATH,
		open_local_lobby,
		MAX_DEATHMATCH_PARTICIPANTS
	)

func load_solo_match_scene(
	solo_dummy_count: int,
	solo_dummy_difficulty: int = BaseAgent.Difficulty.HARD
) -> Error:
	return _match_flow.load_solo_match_scene(
		GAME_SCENE_PATH,
		MAX_DEATHMATCH_PARTICIPANTS,
		solo_dummy_count,
		solo_dummy_difficulty
	)

func host_game() -> Error:
	var error: Error = _lobby_service.host_game()
	if error == OK:
		hosted_room_mode = "deathmatch"
	return error

func create_skirmish_room() -> Error:
	var error: Error = _lobby_service.create_skirmish_room(PORT)
	if error == OK:
		hosted_room_mode = "skirmish"
	return error
func create_deathmatch_room() -> Error:
	var error: Error = _lobby_service.create_deathmatch_room(PORT)
	if error == OK:
		hosted_room_mode = "deathmatch"
	return error

func leave_deathmatch_room() -> void:
	_lobby_service.leave_deathmatch_room()

func set_deathmatch_room_bot_count(bot_count: int) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or match_started:
		return
	var human_count := get_connected_peer_ids().size()
	var maximum_bots := maxi(0, MAX_DEATHMATCH_PARTICIPANTS - human_count)
	deathmatch_room_dummy_count = clampi(bot_count, 0, maximum_bots)
	if multiplayer.get_peers().size() > 0:
		rpc("sync_deathmatch_room_settings", deathmatch_room_dummy_count, deathmatch_room_dummy_difficulty)
	else:
		_lobby_service.publish_local_lobby_state()

func set_deathmatch_room_dummy_difficulty(difficulty: int) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or match_started:
		return
	if difficulty < BaseAgent.Difficulty.EASY or difficulty > BaseAgent.Difficulty.HARD:
		return
	deathmatch_room_dummy_difficulty = difficulty
	if multiplayer.get_peers().size() > 0:
		rpc("sync_deathmatch_room_settings", deathmatch_room_dummy_count, deathmatch_room_dummy_difficulty)
	else:
		_lobby_service.publish_local_lobby_state()

@rpc("authority", "call_remote", "reliable")
func sync_deathmatch_room_settings(bot_count: int, difficulty: int) -> void:
	if not _peer_lifecycle.is_server_rpc_sender():
		return
	if difficulty < BaseAgent.Difficulty.EASY or difficulty > BaseAgent.Difficulty.HARD:
		return
	var maximum_bots := maxi(0, MAX_DEATHMATCH_PARTICIPANTS - multiplayer.get_peers().size() - 1)
	deathmatch_room_dummy_count = clampi(bot_count, 0, maximum_bots)
	deathmatch_room_dummy_difficulty = difficulty
	_lobby_service.publish_local_lobby_state()

func start_lan_match(dummy_count: int, dummy_difficulty: int) -> Error:
	return _lobby_service.start_lan_match(dummy_count, dummy_difficulty)

func start_skirmish_match() -> Error:
	return _skirmish_service.start_match(SKIRMISH_SCENE_PATH)
func are_all_skirmish_players_assigned() -> bool:
	return _skirmish_service.are_all_players_assigned()
@rpc("authority", "call_local", "reliable")
func begin_skirmish_scene() -> void:
	_skirmish_service.begin_scene()
@rpc("any_peer", "reliable")
func request_deathmatch_map_start() -> void:
	_lobby_service.request_deathmatch_match_start(multiplayer.get_remote_sender_id())
@rpc("authority", "call_local", "reliable")
func begin_deathmatch_map_start(dummy_count: int, dummy_difficulty: int) -> void:
	if not _peer_lifecycle.is_server_rpc_sender():
		return
	if dummy_count < 0 or dummy_count >= MAX_DEATHMATCH_PARTICIPANTS:
		return
	if dummy_difficulty < BaseAgent.Difficulty.EASY or dummy_difficulty > BaseAgent.Difficulty.HARD:
		return
	if _match_flow.is_deathmatch_map_loaded() or _match_flow.is_transition_pending():
		return
	match_started = true
	var error := _match_flow.load_deathmatch_match_scene(dummy_count, dummy_difficulty)
	if error != OK:
		match_started = false
		push_error("Could not load the Deathmatch map: %s" % error_string(error))
		if multiplayer.is_server():
			_match_loading_service.finish_match_loading()

@rpc("any_peer", "reliable")
func request_skirmish_scene_ready() -> void:
	_skirmish_service.mark_scene_ready(multiplayer.get_remote_sender_id())
@rpc("authority", "call_local", "reliable")
func clear_skirmish_round_effects() -> void:
	_skirmish_service.clear_round_effects()
@rpc("authority", "call_local", "reliable")
func sync_skirmish_round_result(winner_team: int, team_wins: Array, round_stats: Dictionary) -> void:
	_skirmish_service.apply_round_result(winner_team, team_wins, round_stats)
@rpc("any_peer", "call_remote", "reliable")
func submit_skirmish_round_stats(round_stats: Dictionary) -> void:
	_skirmish_service.submit_round_stats(multiplayer.get_remote_sender_id(), round_stats)
@rpc("authority", "call_remote", "reliable")
func request_skirmish_round_stats() -> void:
	if not is_skirmish_mode() or multiplayer.is_server():
		return
	var current_scene := get_tree().current_scene
	var hud := current_scene.get_node_or_null("HUD") as GameHud if current_scene else null
	if hud:
		rpc_id(1, "submit_skirmish_round_stats", hud.get_skirmish_local_round_stats())
@rpc("authority", "call_local", "reliable")
func return_skirmish_to_lobby_rpc() -> void:
	_skirmish_service.apply_return_to_lobby()
@rpc("authority", "call_local", "reliable")
func notify_match_started() -> void:
	if not _peer_lifecycle.is_server_rpc_sender():
		return
	_lobby_service.apply_match_started()

@rpc("any_peer", "reliable")
func request_lobby_state() -> void:
	_lobby_service.handle_lobby_state_request(multiplayer.get_remote_sender_id())

@rpc("authority", "call_remote", "reliable")
func sync_lobby_state(human_count: int, _host_started: bool) -> void:
	if not _peer_lifecycle.is_server_rpc_sender():
		return
	if (
		_host_started
		and not multiplayer.is_server()
		and not _match_flow.is_deathmatch_map_loaded()
		and not _match_flow.is_transition_pending()
	):
		var map_error: Error = _match_flow.load_deathmatch_match_scene(
			deathmatch_room_dummy_count,
			deathmatch_room_dummy_difficulty
		)
		if map_error != OK:
			push_error("[DeathmatchStart] Client could not load the host's match scene: %s" % error_string(map_error))
	_lobby_service.apply_lobby_state(human_count, _host_started)

func join_game(address: String, requested_mode: String = "deathmatch") -> Error:
	if requested_mode != "deathmatch" and requested_mode != "skirmish":
		return ERR_INVALID_PARAMETER
	expected_room_mode = requested_mode
	return _network_session.join(address, PORT, multiplayer)

func start_solo_match(
	solo_dummy_count: int = MAX_DEATHMATCH_PARTICIPANTS - 1,
	solo_dummy_difficulty: int = BaseAgent.Difficulty.HARD
) -> bool:
	return await _deathmatch_service.start_solo_match(solo_dummy_count, solo_dummy_difficulty)

func disconnect_game() -> void:
	_skirmish_round_service.stop()
	var was_server := multiplayer.has_multiplayer_peer() and multiplayer.is_server()
	if was_server:
		hosted_room_mode = ""
	_network_session.disconnect_session(multiplayer)
	match_started = false
	lobby_player_names.clear()
	skirmish_team_assignments.clear()
	lobby_players_updated.emit(lobby_player_names.duplicate(true))
	skirmish_teams_changed.emit(skirmish_team_assignments.duplicate(true))

func is_networked() -> bool:
	return multiplayer.has_multiplayer_peer()

@rpc("any_peer", "call_remote", "reliable")
func request_room_mode(requested_mode: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 1 or not multiplayer.get_peers().has(sender_id):
		return
	if requested_mode != hosted_room_mode:
		rpc_id(sender_id, "reject_room_mode", hosted_room_mode)
		return
	rpc_id(sender_id, "accept_room_mode", hosted_room_mode)

@rpc("authority", "call_remote", "reliable")
func accept_room_mode(accepted_mode: String) -> void:
	if not _peer_lifecycle.is_server_rpc_sender() or accepted_mode != expected_room_mode:
		return
	_network_session.clear_connection_pending()
	connected.emit()
	request_lobby_state.rpc_id(1)

@rpc("authority", "call_remote", "reliable")
func reject_room_mode(hosted_mode: String) -> void:
	if not _peer_lifecycle.is_server_rpc_sender():
		return
	_network_session.clear_connection_pending()
	room_mode_mismatch.emit(hosted_mode)
	disconnect_game()

func is_deathmatch_mode() -> bool:
	return _match_flow.is_deathmatch_mode()

func is_skirmish_mode() -> bool:
	return _match_flow.is_skirmish_mode()

func can_select_skirmish_agent() -> bool:
	return _skirmish_round_service.can_select_agent()

func is_skirmish_preparation() -> bool:
	return _skirmish_round_service.is_preparation

func is_skirmish_recess() -> bool:
	return _skirmish_round_service.is_recess

@rpc("authority", "call_local", "reliable")
func sync_skirmish_round_state(
	round_number: int,
	preparing: bool,
	duration: float,
	is_recess: bool = false
) -> void:
	_skirmish_service.apply_round_state(round_number, preparing, duration, is_recess)
func get_skirmish_team_for_peer(peer_id: int) -> int:
	return int(skirmish_team_assignments.get(peer_id, -1))

func get_skirmish_team_for_position(spawn_position: Vector2) -> int:
	return _skirmish_service.get_team_for_position(spawn_position)
func play_global_sfx_on_all_peers(sound_id: StringName) -> void:
	_audio_service.play_global_sfx(sound_id)

func play_audio_cue_on_all_peers(stream_path: String, volume_db: float, pitch: float) -> void:
	_audio_service.play_audio_cue_on_all_peers(stream_path, volume_db, pitch)
func play_audio_cue_on_team(stream_path: String, volume_db: float, pitch: float) -> void:
	_audio_service.play_audio_cue_on_team(stream_path, volume_db, pitch)
@rpc("any_peer", "reliable")
func request_team_audio_cue_rpc(
	stream_path: String,
	volume_db: float,
	pitch: float,
	team_id: int
) -> void:
	_audio_service.request_team_audio_cue(stream_path, volume_db, pitch, team_id)
@rpc("any_peer", "call_local", "reliable")
func sync_team_audio_cue_rpc(
	stream_path: String,
	volume_db: float,
	pitch: float,
	team_id: int
) -> void:
	_audio_service.receive_team_audio_cue(stream_path, volume_db, pitch, team_id)
@rpc("any_peer", "reliable")
func request_audio_cue_rpc(stream_path: String, volume_db: float, pitch: float) -> void:
	_audio_service.request_audio_cue(stream_path, volume_db, pitch)
@rpc("any_peer", "call_local", "reliable")
func sync_audio_cue_rpc(stream_path: String, volume_db: float, pitch: float) -> void:
	_audio_service.receive_audio_cue(stream_path, volume_db, pitch)
@rpc("any_peer", "call_local", "reliable")
func sync_global_sfx_rpc(sound_id: StringName) -> void:
	_audio_service.receive_global_sfx(
		sound_id,
		multiplayer.has_multiplayer_peer(),
		multiplayer.is_server(),
		multiplayer.get_remote_sender_id()
	)

func get_shop_item_price(item_id: String) -> int:
	return _shop_service.get_item_price(item_id)

func purchase_shop_item(agent: BaseAgent, item_id: String) -> bool:
	return _shop_service.purchase_item(agent, item_id)

@rpc("any_peer", "reliable")
func request_shop_purchase(item_id: String) -> void:
	_shop_service.handle_purchase_request(item_id, multiplayer.get_remote_sender_id())

@rpc("authority", "call_remote", "reliable")
func notify_shop_purchase_rejected(item_id: String) -> void:
	shop_purchase_rejected.emit(item_id)

@rpc("authority", "call_local", "reliable")
func sync_shop_purchase(peer_id: int, item_id: String, credits: int, shield: float) -> void:
	_shop_service.sync_purchase(peer_id, item_id, credits, shield)

func handle_player_death(agent: BaseAgent, killer: Node = null, weapon_name: String = "") -> void:
	await _deathmatch_service.handle_player_death(agent, killer, weapon_name)

func handle_dummy_death(dummy: BaseAgent, killer: Node = null, weapon_name: String = "") -> void:
	await _deathmatch_service.handle_dummy_death(dummy, killer, weapon_name)

func _get_combat_report_attacker_details(victim: BaseAgent) -> Array:
	return _match_services.get_combat_report_service().get_attacker_details(victim)
func _get_combat_damage_source_paths(victim: BaseAgent) -> Array:
	return _match_services.get_combat_report_service().get_damage_source_paths(victim)
@rpc("authority", "call_remote", "reliable")
func sync_skirmish_combat_outcome(
	outcome: String,
	outgoing_damage: float,
	target_actor_id: int,
	target_life_id: int
) -> void:
	_match_services.get_combat_report_service().apply_skirmish_outcome(
		outcome, outgoing_damage, target_actor_id, target_life_id
	)
func get_deathmatch_actor_id(actor: Node) -> int:
	return _deathmatch_service.get_actor_id(actor)

func find_deathmatch_actor(actor_id: int) -> Node:
	return _deathmatch_service.find_actor(actor_id)

func report_agent_kill_effect(agent: BaseAgent, attacker: Node, effect_name: String) -> void:
	_deathmatch_service.report_agent_kill_effect(agent, attacker, effect_name)

@rpc("authority", "call_local", "reliable")
func sync_deathmatch_scores(scores: Dictionary, deaths: Dictionary) -> void:
	_deathmatch_service.apply_scores(scores, deaths)

@rpc("authority", "call_local", "reliable")
func kill_feed_event(killer_peer_id: int, victim_peer_id: int, weapon_name: String) -> void:
	kill_feed_received.emit(killer_peer_id, victim_peer_id, weapon_name)

@rpc("authority", "call_local", "reliable")
func player_died(peer_id: int) -> void:
	_player_service.handle_player_died(peer_id)

@rpc("authority", "call_remote", "reliable")
func combat_report_event(
	killer_name: String,
	killer_agent_id: String,
	killer_sprite_path: String,
	weapon_name: String,
	outgoing_damage: float,
	incoming_damage: float,
	damage_source_paths: Array,
	attacker_details: Array
) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	combat_report_received.emit(
		killer_name, killer_agent_id, killer_sprite_path, weapon_name,
		outgoing_damage, incoming_damage, damage_source_paths, attacker_details
	)

@rpc("authority", "call_local", "reliable")
func respawn_player(peer_id: int, spawn_position: Vector2) -> void:
	_player_service.respawn_player(peer_id, spawn_position)

func find_player(peer_id: int) -> BaseAgent:
	return _player_service.find_player(peer_id)

func get_spawn_marker(excluded_actor: Node = null, preferred_index: int = -1) -> Marker2D:
	return _deathmatch_service.get_match_spawn_marker(excluded_actor, preferred_index)

func get_different_spawn_marker(actor: BaseAgent) -> Marker2D:
	return _deathmatch_service.get_match_different_spawn_marker(actor)

func get_player_weapon_slot(peer_id: int) -> int:
	return _weapon_service.get_player_weapon_slot(peer_id)

@rpc("authority", "call_local", "reliable")
func sync_dummy_spawn(
	dummy_index: int,
	spawn_position: Vector2,
	weapon_index: int,
	dummy_difficulty: int = BaseAgent.Difficulty.HARD,
	agent_index: int = -1
) -> void:
	_deathmatch_service.sync_dummy_spawn(
		dummy_index, spawn_position, weapon_index, dummy_difficulty,
		agent_index, _peer_lifecycle.is_server_rpc_sender()
	)

@rpc("authority", "call_local", "reliable")
func sync_dummy_despawn(dummy_index: int) -> void:
	_deathmatch_service.sync_dummy_despawn(
		dummy_index, _peer_lifecycle.is_server_rpc_sender()
	)

@rpc("authority", "call_local", "reliable")
func spawn_player(
	peer_id: int,
	spawn_position: Vector2,
	weapon_slot: int = 0,
	agent_id: String = ""
) -> void:
	_player_service.spawn_player(peer_id, spawn_position, weapon_slot, agent_id)

@rpc("any_peer", "unreliable", "call_remote", 1)
func sync_player_transform_rpc(
	peer_id: int,
	world_position: Vector2,
	movement_velocity: Vector2,
	visual_rotation: float
) -> void:
	_player_service.receive_network_transform(peer_id, world_position, movement_velocity, visual_rotation)

func broadcast_player_active_ability(peer_id: int, ability_name: String) -> void:
	_player_service.broadcast_active_ability(peer_id, ability_name)

@rpc("any_peer", "call_remote", "reliable")
func request_player_active_ability_rpc(peer_id: int, ability_name: String) -> void:
	_player_service.request_active_ability(
		peer_id, ability_name, multiplayer.get_remote_sender_id()
	)

@rpc("authority", "call_local", "reliable")
func sync_player_active_ability_rpc(peer_id: int, ability_name: String) -> void:
	if not _peer_lifecycle.is_server_rpc_sender():
		return
	_player_service.apply_active_ability(peer_id, ability_name)

func publish_player_health_state(
	peer_id: int,
	current_health: float,
	current_shield: float,
	max_health: float,
	max_shield: float,
	regenerative_reserve: float,
	regenerative_delay: float
) -> void:
	_player_service.publish_health_state(
		peer_id, current_health, current_shield, max_health, max_shield,
		regenerative_reserve, regenerative_delay
	)
@rpc("any_peer", "call_remote", "reliable")
func request_player_health_state(
	peer_id: int,
	current_health: float,
	current_shield: float,
	max_health: float,
	max_shield: float,
	regenerative_reserve: float,
	regenerative_delay: float
) -> void:
	_player_service.request_health_state(
		peer_id, current_health, current_shield, max_health, max_shield,
		regenerative_reserve, regenerative_delay
	)
@rpc("authority", "call_local", "reliable")
func sync_player_health_state_rpc(
	peer_id: int,
	current_health: float,
	current_shield: float,
	max_health: float,
	max_shield: float,
	regenerative_reserve: float,
	regenerative_delay: float
) -> void:
	_player_service.receive_health_state(
		peer_id, current_health, current_shield, max_health, max_shield,
		regenerative_reserve, regenerative_delay
	)
@rpc("authority", "call_remote", "reliable")
func sync_player_damage_direction_rpc(peer_id: int, direction: Vector2) -> void:
	_player_service.receive_damage_direction(peer_id, direction)
@rpc("any_peer", "call_remote", "reliable")
func sync_player_damage_flash_rpc(peer_id: int) -> void:
	_player_service.receive_damage_flash(peer_id)

func get_local_agent(current_scene: Node) -> BaseAgent:
	return _player_service.get_local_agent(current_scene)

func get_max_bot_count(human_count: int) -> int:
	return _deathmatch_service.get_max_bot_count(human_count)

func is_match_loading() -> bool:
	return _match_services != null and _match_services.get_loading_state()

func get_connected_peer_ids() -> Array[int]:
	return _lobby_service.get_connected_peer_ids()
@rpc("any_peer", "reliable")
func request_weapon_sync(peer_id: int, weapon_slot: int) -> void:
	_weapon_service.request_weapon_sync(peer_id, weapon_slot, multiplayer.get_remote_sender_id(), multiplayer.is_server())
@rpc("any_peer", "reliable")
func request_dropped_weapon(
	peer_id: int,
	weapon_path: String,
	drop_pos: Vector2,
	direction: Vector2,
	dropped_ammo: int,
	dropped_reserve: int
) -> void:
	_weapon_service.request_dropped_weapon(peer_id, multiplayer.get_remote_sender_id(), weapon_path, drop_pos, direction, dropped_ammo, dropped_reserve, multiplayer.is_server())
@rpc("authority", "call_local", "reliable")
func spawn_dropped_weapon(
	owner_peer_id: int,
	weapon_path: String,
	drop_pos: Vector2,
	direction: Vector2,
	dropped_ammo: int,
	dropped_reserve: int
) -> void:
	_weapon_service.spawn_dropped_weapon(owner_peer_id, weapon_path, drop_pos, direction, dropped_ammo, dropped_reserve)
@rpc("authority", "call_local", "reliable")
func sync_player_weapon(peer_id: int, weapon_slot: int) -> void:
	_weapon_service.sync_player_weapon(peer_id, weapon_slot)

@rpc("authority", "call_local", "reliable")
func remove_player(peer_id: int) -> void:
	_player_service.remove_player(peer_id)
