extends Node

var _manager: Node
var _ready_peers: Dictionary = {}
var _overlay: CanvasLayer
var _deathmatch_loading := false
var _paused_scene: Node
var _previous_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _previous_master_mute := false
var _load_state_active := false
var _previous_tree_paused := false
var _match_initializing := false
var _pause_tree_on_finish := true
var _previous_network_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT

func setup(manager: Node) -> void:
	_manager = manager

func start_deathmatch(player_count: int) -> void:
	_ready_peers.clear()
	_match_initializing = false
	_deathmatch_loading = true
	if not is_loading_screen_visible():
		_show("deathmatch", 0, player_count)
	call_deferred("_report_local_ready")

func is_deathmatch_loading() -> bool:
	return _deathmatch_loading

func prepare_match_loading(mode: String, player_count: int) -> void:
	_deathmatch_loading = mode == "deathmatch"
	_show(mode, 0, player_count)
	call_deferred("_report_local_ready")

@rpc("authority", "call_remote", "reliable")
func receive_match_loading_finish() -> void:
	finish_match_loading()

func set_match_loading_pause(paused: bool) -> void:
	if paused:
		pause_current_scene()
	else:
		_hide()

func get_loading_state() -> bool:
	return is_loading_screen_visible()

@rpc("any_peer", "reliable")
func request_match_loading_ready() -> void:
	if not _manager.get_multiplayer().is_server() or not _manager.get("match_started"):
		return
	var sender_id := _manager.get_multiplayer().get_remote_sender_id()
	if sender_id <= 1 or not _manager.get_multiplayer().get_peers().has(sender_id):
		return
	_mark_ready(sender_id)

func _report_local_ready() -> void:
	if not _manager.call("is_networked"):
		return
	if _manager.get_multiplayer().is_server():
		_mark_ready(1)
	else:
		_await_local_visual_frame()

func _await_local_visual_frame() -> void:
	await _manager.get_tree().process_frame
	if is_instance_valid(_overlay):
		rpc_id(1, "request_match_loading_ready")

func _mark_ready(peer_id: int) -> void:
	if not _manager.get_multiplayer().is_server() or not _manager.get("match_started"):
		return
	var connected_ids: Array = _manager.call("get_connected_peer_ids")
	if not connected_ids.has(peer_id):
		return
	_ready_peers[peer_id] = true
	rpc("sync_match_loading_progress", _ready_peers.size(), connected_ids.size())
	if _all_connected_peers_ready(connected_ids):
		_manager.get("_lobby_service").complete_lan_match_start()
	return

func _all_connected_peers_ready(connected_ids: Array) -> bool:
	for connected_id in connected_ids:
		if not _ready_peers.has(connected_id):
			return false
	return true

func is_initializing_match() -> bool:
	return _match_initializing

func set_initializing_match(initializing: bool) -> void:
	_match_initializing = initializing

func on_peer_disconnected(peer_id: int) -> void:
	if not _deathmatch_loading or not _manager.get_multiplayer().is_server():
		return
	_ready_peers.erase(peer_id)
	var connected_ids: Array = _manager.call("get_connected_peer_ids")
	rpc("sync_match_loading_progress", _ready_peers.size(), connected_ids.size())
	if _all_connected_peers_ready(connected_ids):
		_manager.get("_lobby_service").complete_lan_match_start()

@rpc("authority", "call_local", "reliable")
func sync_match_loading_progress(ready_count: int, player_count: int) -> void:
	if _overlay and _overlay.get_child_count() > 0:
		var screen: Control = _overlay.get_child(0) as Control
		if screen.has_method("set_ready_count"):
			screen.call("set_ready_count", ready_count, player_count)

@rpc("authority", "call_local", "reliable")
func finish_match_loading() -> void:
	if _manager.call("is_networked") and not _manager.get_multiplayer().is_server():
		if _manager.get_multiplayer().get_remote_sender_id() != 1:
			return
	_deathmatch_loading = false
	_match_initializing = false
	_hide()

func pause_after_scene_change() -> void:
	if not _load_state_active:
		_previous_tree_paused = _manager.get_tree().paused
		_previous_master_mute = AudioServer.is_bus_mute(0)
		_previous_network_process_mode = _manager.process_mode
	_load_state_active = true
	_pause_tree_on_finish = false
	_manager.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_active_scene()
	_manager.get_tree().paused = true
	AudioServer.set_bus_mute(0, true)

func show_skirmish(ready_count: int, player_count: int) -> void:
	_show("skirmish", ready_count, player_count)

func show_local_deathmatch() -> void:
	_show("deathmatch", 1, 1)

func finish_offline() -> void:
	_hide()

func reset_session() -> void:
	_deathmatch_loading = false
	_match_initializing = false
	_ready_peers.clear()
	_hide()

func _show(
	mode: String,
	ready_count: int,
	player_count: int
) -> void:
	_hide()
	if mode == "skirmish":
		_overlay = CanvasLayer.new()
		_overlay.name = "MatchLoadingOverlay"
		_overlay.layer = 100
		_manager.get_tree().root.add_child(_overlay)
		_enable_loading_display_processing()
		var skirmish_screen: Control = load("res://scenes/ui/loading_screen.tscn").instantiate() as Control
		_overlay.add_child(skirmish_screen)
		skirmish_screen.process_mode = Node.PROCESS_MODE_ALWAYS
		skirmish_screen.call("configure_for_match", mode, ready_count, player_count)
		return
	pause_current_scene()
	_overlay = CanvasLayer.new()
	_overlay.name = "MatchLoadingOverlay"
	_overlay.layer = 100
	_manager.get_tree().root.add_child(_overlay)
	_enable_loading_display_processing()
	var screen: Control = load("res://scenes/ui/loading_screen.tscn").instantiate() as Control
	_overlay.add_child(screen)
	screen.process_mode = Node.PROCESS_MODE_ALWAYS
	screen.call("configure_for_match", mode, ready_count, player_count)
	var current_scene := _manager.get_tree().current_scene
	if current_scene:
		var lobby := current_scene.get_node_or_null("NetworkLobby")
		if lobby:
			lobby.visible = false
		var hud := current_scene.get_node_or_null("HUD")
		if hud:
			hud.visible = false

func is_loading_screen_visible() -> bool:
	return is_instance_valid(_overlay)

func pause_current_scene() -> void:
	if not _load_state_active:
		_previous_tree_paused = _manager.get_tree().paused
		_previous_master_mute = AudioServer.is_bus_mute(0)
		_previous_network_process_mode = _manager.process_mode
	_load_state_active = true
	_pause_tree_on_finish = true
	_manager.process_mode = Node.PROCESS_MODE_ALWAYS
	if not _manager.get_tree().paused:
		_pause_active_scene()
	_manager.get_tree().paused = true
	AudioServer.set_bus_mute(0, true)
	_enable_loading_display_processing()

func resume_game_for_loading() -> void:
	if not _load_state_active:
		return
	_manager.get_tree().paused = _previous_tree_paused
	if is_instance_valid(_paused_scene):
		_paused_scene.process_mode = _previous_process_mode
		_paused_scene = null
	if not _pause_tree_on_finish:
		_manager.process_mode = _previous_network_process_mode
	_pause_tree_on_finish = true
	AudioServer.set_bus_mute(0, _previous_master_mute)
	_load_state_active = false

func _pause_active_scene() -> void:
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return
	_paused_scene = current_scene
	_previous_process_mode = current_scene.process_mode
	current_scene.process_mode = Node.PROCESS_MODE_DISABLED

func _enable_loading_display_processing() -> void:
	if not is_instance_valid(_overlay):
		return
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	for child in _overlay.get_children():
		child.process_mode = Node.PROCESS_MODE_ALWAYS

func _hide() -> void:
	var had_loading_state := _load_state_active
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	if _load_state_active and not _pause_tree_on_finish:
		_manager.get_tree().paused = false
	if had_loading_state:
		if _pause_tree_on_finish:
			_manager.get_tree().paused = _previous_tree_paused
			_manager.process_mode = _previous_network_process_mode
		AudioServer.set_bus_mute(0, _previous_master_mute)
		_load_state_active = false
	if is_instance_valid(_paused_scene):
		_paused_scene.process_mode = _previous_process_mode
		_paused_scene = null
