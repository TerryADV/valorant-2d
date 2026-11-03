extends RefCounted

var _manager: Node
var _transition_pending := false
var _pending_skirmish := false
var _pending_local_lobby := false
var _pending_deathmatch_match := false
var _deathmatch_room_ready := false
var _pending_dummy_count := 0
var _pending_dummy_difficulty: int = BaseAgent.Difficulty.HARD

func setup(manager: Node) -> void:
	_manager = manager

func is_transition_pending() -> bool:
	return _transition_pending

func show_local_deathmatch_loading() -> void:
	_manager.get("_match_loading_service").show_local_deathmatch()

func set_pending_deathmatch_match(dummy_count: int, dummy_difficulty: int) -> void:
	_pending_deathmatch_match = true
	_pending_local_lobby = false
	_pending_dummy_count = dummy_count
	_pending_dummy_difficulty = dummy_difficulty

func is_deathmatch_map_loaded() -> bool:
	var current_scene := _manager.get_tree().current_scene
	return current_scene != null and current_scene.scene_file_path == "res://scenes/maps/ascent.tscn"

func is_deathmatch_room_ready() -> bool:
	return _deathmatch_room_ready or _manager.get_multiplayer().has_multiplayer_peer()

func mark_deathmatch_room_ready(ready: bool = true) -> void:
	_deathmatch_room_ready = ready

func on_menu_deathmatch_room_closed() -> void:
	_deathmatch_room_ready = false

func show_match_hud() -> void:
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return
	var hud := current_scene.get_node_or_null("HUD") as CanvasLayer
	if hud:
		hud.visible = true
		if hud.has_method("bind_player"):
			hud.call_deferred("bind_player")
		if hud.has_method("refresh_game_mode"):
			hud.call("refresh_game_mode")
	var lobby := current_scene.get_node_or_null("NetworkLobby") as CanvasLayer
	if lobby:
		lobby.visible = false

func is_deathmatch_mode() -> bool:
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return false
	var mode_selector := current_scene.get_node_or_null("GameModeSelector") as GameModeSelector
	return mode_selector != null and mode_selector.is_deathmatch()

func is_skirmish_mode() -> bool:
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return false
	var mode_selector := current_scene.get_node_or_null("GameModeSelector") as GameModeSelector
	return mode_selector != null and mode_selector.is_skirmish()

func load_match_scene(
	game_scene_path: String,
	open_local_lobby: bool,
	max_participants: int
) -> Error:
	return load_scene(
		game_scene_path,
		open_local_lobby,
		max_participants - 1,
		BaseAgent.Difficulty.HARD
	)

func load_solo_match_scene(
	game_scene_path: String,
	max_participants: int,
	dummy_count: int,
	dummy_difficulty: int
) -> Error:
	if dummy_count < 0 or dummy_count >= max_participants:
		push_error("[MatchStart] Solo bot count must be between 0 and 11.")
		return ERR_INVALID_PARAMETER
	if dummy_difficulty < BaseAgent.Difficulty.EASY or dummy_difficulty > BaseAgent.Difficulty.HARD:
		push_error("[MatchStart] Invalid solo bot difficulty.")
		return ERR_INVALID_PARAMETER
	return load_scene(game_scene_path, false, dummy_count, dummy_difficulty)

func load_deathmatch_from_menu(
	open_local_lobby: bool,
	dummy_count: int,
	dummy_difficulty: int
) -> Error:
	var map_path := "res://scenes/maps/ascent.tscn"
	_manager.get("_match_loading_service").show_local_deathmatch()
	await _manager.get_tree().process_frame
	var request_error := ResourceLoader.load_threaded_request(map_path)
	if request_error != OK and request_error != ERR_BUSY:
		_manager.get("_match_loading_service").finish_offline()
		return request_error
	var load_status := ResourceLoader.load_threaded_get_status(map_path)
	while load_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await _manager.get_tree().process_frame
		load_status = ResourceLoader.load_threaded_get_status(map_path)
	if load_status != ResourceLoader.THREAD_LOAD_LOADED:
		_manager.get("_match_loading_service").finish_offline()
		return ERR_CANT_OPEN
	var loaded_map := ResourceLoader.load_threaded_get(map_path) as PackedScene
	if not loaded_map:
		_manager.get("_match_loading_service").finish_offline()
		return ERR_FILE_CORRUPT
	if dummy_count < 0 or dummy_count > 11:
		_manager.get("_match_loading_service").finish_offline()
		return ERR_INVALID_PARAMETER
	if dummy_difficulty < BaseAgent.Difficulty.EASY or dummy_difficulty > BaseAgent.Difficulty.HARD:
		_manager.get("_match_loading_service").finish_offline()
		return ERR_INVALID_PARAMETER
	return load_packed_scene(loaded_map, open_local_lobby, dummy_count, dummy_difficulty)


func load_skirmish_scene(game_scene_path: String) -> Error:
	if _transition_pending:
		return ERR_BUSY
	_transition_pending = true
	_pending_skirmish = true
	var error := _manager.get_tree().change_scene_to_file(game_scene_path)
	if error != OK:
		_transition_pending = false
		_pending_skirmish = false
		push_error("Could not load the Skirmish map: %s" % error_string(error))
		return error
	return OK

func load_scene(
	game_scene_path: String,
	open_local_lobby: bool,
	dummy_count: int,
	dummy_difficulty: int
) -> Error:
	if _transition_pending:
		return ERR_BUSY
	_transition_pending = true
	_pending_local_lobby = open_local_lobby
	_pending_dummy_count = dummy_count
	_pending_dummy_difficulty = dummy_difficulty
	var error := _manager.get_tree().change_scene_to_file(game_scene_path)
	if error != OK:
		_transition_pending = false
		push_error("Could not load the Deathmatch map: %s" % error_string(error))
		return error
	return OK

func load_packed_scene(
	game_scene: PackedScene,
	open_local_lobby: bool,
	dummy_count: int,
	dummy_difficulty: int
) -> Error:
	if not game_scene:
		return ERR_INVALID_PARAMETER
	if _transition_pending:
		return ERR_BUSY
	_transition_pending = true
	_pending_skirmish = false
	_pending_deathmatch_match = false
	_pending_local_lobby = open_local_lobby
	_pending_dummy_count = dummy_count
	_pending_dummy_difficulty = dummy_difficulty
	var error := _manager.get_tree().change_scene_to_packed(game_scene)
	if error != OK:
		_transition_pending = false
		_pending_local_lobby = false
		push_error("Could not change to the loaded Deathmatch map: %s" % error_string(error))
		return error
	return OK

func load_deathmatch_match_scene(dummy_count: int, dummy_difficulty: int) -> Error:
	set_pending_deathmatch_match(dummy_count, dummy_difficulty)
	return load_scene("res://scenes/maps/ascent.tscn", false, dummy_count, dummy_difficulty)

func on_scene_changed() -> void:
	if not _transition_pending:
		return
	_transition_pending = false
	if _pending_skirmish:
		_pending_skirmish = false
		_manager.get("_skirmish_service").on_scene_loaded()
		return
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		push_error("[MatchStart] No active scene after the menu transition.")
		return
	_manager.get("_player_service").prepare_current_scene()
	if _pending_deathmatch_match:
		_pending_deathmatch_match = false
		_deathmatch_room_ready = false
		var was_loading: bool = _manager.get("_match_loading_service").is_deathmatch_loading()
		var selector := current_scene.get_node_or_null("GameModeSelector") as GameModeSelector
		if selector:
			selector.selected_mode = GameModeSelector.Mode.DEATHMATCH
		var multiplayer_api := _manager.get_multiplayer()
		if not multiplayer_api.has_multiplayer_peer() or multiplayer_api.is_server():
			_manager.set("match_started", true)
			var human_count: int = _manager.call("get_connected_peer_ids").size()
			var selected_dummy_count: int = int(_manager.get("deathmatch_room_dummy_count")) if multiplayer_api.has_multiplayer_peer() else _pending_dummy_count
			var spawn_capacity := int(_manager.call("get_max_bot_count", human_count))
			var allowed_dummy_count := mini(selected_dummy_count, spawn_capacity)
			_manager.set("lan_dummy_count", allowed_dummy_count)
			if multiplayer_api.has_multiplayer_peer():
				_manager.set("deathmatch_room_dummy_count", allowed_dummy_count)
			if not was_loading:
				_manager.get("_match_loading_service").start_deathmatch(
					human_count
				)
			if multiplayer_api.has_multiplayer_peer():
				_manager.rpc("sync_lobby_state", human_count, true)
		else:
			_manager.set("match_started", true)
			if not was_loading:
				_manager.get("_match_loading_service").start_deathmatch(1)
		return
	if _manager.get("_match_loading_service").is_loading_screen_visible():
		_manager.get("_match_loading_service").pause_after_scene_change()
	if _pending_local_lobby:
		var lobby := current_scene.get_node_or_null("NetworkLobby") as CanvasLayer
		if not lobby:
			push_error("The Deathmatch map is missing its NetworkLobby.")
			return
		_manager.set("match_started", false)
		_manager.get("_match_loading_service").finish_offline()
		var local_agent := _manager.call("get_local_agent", current_scene) as BaseAgent
		if local_agent:
			local_agent.set_lobby_locked(true)
			local_agent.visible = false
		var hud := current_scene.get_node_or_null("HUD") as CanvasLayer
		if hud:
			hud.visible = false
		lobby.visible = false
		return
	var match_started: bool = await _manager.get("_deathmatch_service").start_solo_match(
		_pending_dummy_count, _pending_dummy_difficulty
	)
	if not match_started:
		push_error("Could not start the solo Deathmatch match.")
	_manager.get("_match_loading_service").finish_offline()
