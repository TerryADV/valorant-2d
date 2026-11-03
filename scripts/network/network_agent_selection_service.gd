extends RefCounted

var selected_agent_id := ""
var _manager: Node

func setup(manager: Node) -> void:
	_manager = manager

func set_selected_agent(agent_id: String) -> bool:
	var data := _manager.call("get_agent_data", agent_id) as AgentData
	if not data:
		push_error("Cannot select unknown agent ID: %s" % agent_id)
		return false
	if _manager.call("is_skirmish_mode"):
		if not _manager.call("can_select_skirmish_agent"):
			return false
		var selection_scene := _manager.get_tree().current_scene
		var selection_agent := _manager.call("get_local_agent", selection_scene) as BaseAgent
		if selection_agent and _has_same_team_agent(selection_agent, agent_id):
			return false
	if _manager.call("is_deathmatch_mode"):
		var deathmatch_scene := _manager.get_tree().current_scene
		var deathmatch_local_agent: BaseAgent = null
		if deathmatch_scene:
			deathmatch_local_agent = _manager.call("get_local_agent", deathmatch_scene) as BaseAgent
		if deathmatch_local_agent and deathmatch_local_agent.get_agent_switch_lock_remaining() > 0.0:
			return false
	if _manager.call("is_networked"):
		var multiplayer_api := _manager.get_multiplayer()
		if multiplayer_api.is_server():
			return select_agent_for_peer(multiplayer_api.get_unique_id(), agent_id)
		_manager.rpc_id(1, "request_agent_selection", agent_id)
		return true

	var current_scene := _manager.get_tree().current_scene
	var local_agent: BaseAgent = null
	if current_scene:
		local_agent = _manager.call("get_local_agent", current_scene) as BaseAgent
	if local_agent:
		if local_agent.agent_data and local_agent.agent_data.agent_id == agent_id:
			selected_agent_id = agent_id
			return true
		var spawn_position := local_agent.global_position
		if not _manager.call("is_skirmish_mode"):
			var spawn_marker := _manager.call("get_different_spawn_marker", local_agent) as Marker2D
			if not spawn_marker:
				return false
			spawn_position = spawn_marker.global_position
		var was_movement_locked := local_agent.is_movement_locked
		local_agent.configure_agent(data)
		local_agent.respawn_at(spawn_position)
		local_agent.is_movement_locked = was_movement_locked
	selected_agent_id = agent_id
	return true

func select_agent_for_peer(peer_id: int, agent_id: String) -> bool:
	var selected_player := _manager.call("find_player", peer_id) as BaseAgent
	if not selected_player or selected_player.is_dead or selected_player.shop_open:
		return false
	if _manager.call("is_skirmish_mode"):
		if not _manager.call("can_select_skirmish_agent"):
			return false
		if _has_same_team_agent(selected_player, agent_id):
			return false
	if _manager.call("is_deathmatch_mode") and selected_player.get_agent_switch_lock_remaining() > 0.0:
		return false
	if selected_player.agent_data and selected_player.agent_data.agent_id == agent_id:
		return true
	var spawn_position := selected_player.global_position
	if not _manager.call("is_skirmish_mode"):
		var spawn_marker := _manager.call("get_different_spawn_marker", selected_player) as Marker2D
		if not spawn_marker:
			return false
		spawn_position = spawn_marker.global_position
	if peer_id == _manager.get_multiplayer().get_unique_id():
		selected_agent_id = agent_id
	var was_movement_locked := selected_player.is_movement_locked
	_manager.rpc("sync_agent_selection", peer_id, agent_id, spawn_position)
	selected_player.is_movement_locked = was_movement_locked
	return true

func _has_same_team_agent(selected_player: BaseAgent, agent_id: String) -> bool:
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return false
	for actor in current_scene.get_children():
		if not actor is BaseAgent or actor == selected_player:
			continue
		if actor.skirmish_team != selected_player.skirmish_team or not actor.agent_data:
			continue
		if actor.agent_data.agent_id == agent_id:
			return true
	return false

func request_agent_selection(agent_id: String, sender_id: int) -> void:
	if not _manager.call("is_networked") or not _manager.get_multiplayer().is_server():
		return
	if not _manager.call("get_agent_data", agent_id):
		return
	select_agent_for_peer(sender_id, agent_id)

func sync_agent_selection(peer_id: int, agent_id: String, spawn_position: Vector2) -> void:
	var data := _manager.call("get_agent_data", agent_id) as AgentData
	var selected_player := _manager.call("find_player", peer_id) as BaseAgent
	if not data or not selected_player:
		return
	var was_movement_locked := selected_player.is_movement_locked
	selected_player.configure_agent(data)
	selected_player.respawn_at(spawn_position)
	selected_player.is_movement_locked = was_movement_locked
	if peer_id == _manager.get_multiplayer().get_unique_id():
		selected_agent_id = agent_id
