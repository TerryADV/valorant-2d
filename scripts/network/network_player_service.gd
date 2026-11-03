extends RefCounted

const PLAYER_SCENE: PackedScene = preload("res://scenes/entities/base_agent.tscn")

var _manager: Node

func setup(manager: Node) -> void:
	_manager = manager

func find_player(peer_id: int) -> BaseAgent:
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return null
	var player := current_scene.get_node_or_null("Player_%d" % peer_id) as BaseAgent
	if player:
		return player
	if peer_id == 1:
		return current_scene.get_node_or_null("BaseAgent") as BaseAgent
	return null

func get_local_agent(current_scene: Node) -> BaseAgent:
	var multiplayer_api: MultiplayerAPI = _manager.get_multiplayer()
	var unique_id := multiplayer_api.get_unique_id() if multiplayer_api.has_multiplayer_peer() else 1
	var local_agent := current_scene.get_node_or_null("Player_%d" % unique_id) as BaseAgent
	if local_agent:
		return local_agent
	if unique_id == 1:
		return current_scene.get_node_or_null("BaseAgent") as BaseAgent
	return null

func spawn_player(
	peer_id: int,
	spawn_position: Vector2,
	weapon_slot: int,
	agent_id: String
) -> void:
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return
	var data := _resolve_agent_data(current_scene, agent_id)
	if not data:
		push_error("Cannot spawn peer %d with unknown agent ID: %s" % [peer_id, agent_id])
		return

	var multiplayer_api: MultiplayerAPI = _manager.get_multiplayer()
	var unique_id := multiplayer_api.get_unique_id() if multiplayer_api.has_multiplayer_peer() else 1
	var local_agent := get_local_agent(current_scene)
	if peer_id == unique_id and local_agent:
		local_agent.set_lobby_locked(false)
		local_agent.skirmish_team = int(_manager.call("get_skirmish_team_for_peer", peer_id))
		local_agent.configure_agent(data)
		local_agent.set_multiplayer_authority(peer_id)
		local_agent.global_position = spawn_position
		local_agent.velocity = Vector2.ZERO
		local_agent.visible = true
		local_agent.configure_network_visuals(true)
		local_agent.focus_local_camera()
		_manager.get("_weapon_service").apply_weapon_slot(local_agent, weapon_slot)
		_manager.get("_weapon_service").apply_pending_weapon_slot(local_agent, peer_id)
		if _manager.call("is_skirmish_mode"):
			_manager.get("_weapon_service").apply_skirmish_starting_loadout(local_agent)
		local_agent.grant_spawn_protection()
		_manager.get("_match_flow").show_match_hud()
		return

	if peer_id == 1 and unique_id != 1:
		var host_agent := current_scene.get_node_or_null("Player_1") as BaseAgent
		if not host_agent:
			host_agent = current_scene.get_node_or_null("BaseAgent") as BaseAgent
		if host_agent:
			host_agent.set_lobby_locked(false)
			host_agent.skirmish_team = int(_manager.call("get_skirmish_team_for_peer", peer_id))
			host_agent.configure_agent(data)
			host_agent.set_multiplayer_authority(peer_id)
			host_agent.global_position = spawn_position
			host_agent.velocity = Vector2.ZERO
			host_agent.visible = true
			host_agent.configure_network_visuals(false)
			_manager.get("_weapon_service").apply_weapon_slot(host_agent, weapon_slot)
			_manager.get("_weapon_service").apply_pending_weapon_slot(host_agent, peer_id)
			if _manager.call("is_skirmish_mode"):
				_manager.get("_weapon_service").apply_skirmish_starting_loadout(host_agent)
			host_agent.grant_spawn_protection()
			return

	var player_name := "Player_%d" % peer_id
	if current_scene.get_node_or_null(player_name):
		return
	var agent := PLAYER_SCENE.instantiate() as BaseAgent
	agent.agent_data = data
	agent.skirmish_team = int(_manager.call("get_skirmish_team_for_peer", peer_id))
	agent.set_lobby_locked(false)
	agent.name = player_name
	agent.position = spawn_position
	agent.set_multiplayer_authority(peer_id)
	current_scene.add_child(agent, true)
	agent.visible = true
	agent.configure_network_visuals(peer_id == unique_id)
	_manager.get("_weapon_service").apply_weapon_slot(agent, weapon_slot)
	_manager.get("_weapon_service").apply_pending_weapon_slot(agent, peer_id)
	if _manager.call("is_skirmish_mode"):
		_manager.get("_weapon_service").apply_skirmish_starting_loadout(agent)
	agent.grant_spawn_protection()
	if peer_id == unique_id:
		agent.focus_local_camera()
		_manager.get("_match_flow").show_match_hud()

func _resolve_agent_data(current_scene: Node, requested_agent_id: String) -> AgentData:
	var candidates := [requested_agent_id, str(_manager.get("selected_agent_id"))]
	for candidate in candidates:
		if candidate.is_empty():
			continue
		var agent_data := _manager.call("get_agent_data", candidate) as AgentData
		if agent_data:
			return agent_data
	var map_agent := current_scene.get_node_or_null("BaseAgent") as BaseAgent
	if map_agent and map_agent.agent_data:
		return map_agent.agent_data
	return _manager.call("get_agent_data", "phoenix") as AgentData

func remove_player(peer_id: int) -> void:
	var current_scene := _manager.get_tree().current_scene
	if current_scene:
		var player := current_scene.get_node_or_null("Player_%d" % peer_id) as BaseAgent
		if player:
			player.visible = false
			player.queue_free()
	var pending_weapon_slots: Dictionary = _manager.get("pending_weapon_slots")
	pending_weapon_slots.erase(peer_id)

func handle_player_died(peer_id: int) -> void:
	var player := find_player(peer_id)
	if player:
		player.handle_death()

func respawn_player(peer_id: int, spawn_position: Vector2) -> void:
	var player := find_player(peer_id)
	if player:
		player.respawn_at(spawn_position)

func apply_network_transform(
	peer_id: int,
	world_position: Vector2,
	movement_velocity: Vector2,
	visual_rotation: float
) -> void:
	var player := find_player(peer_id)
	if not player or player.is_multiplayer_authority():
		return
	player.apply_network_transform(world_position, movement_velocity, visual_rotation)

func receive_network_transform(
	peer_id: int,
	world_position: Vector2,
	movement_velocity: Vector2,
	visual_rotation: float
) -> void:
	if not _manager.call("is_networked"):
		return
	var multiplayer_api: MultiplayerAPI = _manager.get_multiplayer()
	var sender_id := multiplayer_api.get_remote_sender_id()
	if multiplayer_api.is_server():
		if peer_id <= 1 or sender_id != peer_id:
			return
		apply_network_transform(peer_id, world_position, movement_velocity, visual_rotation)
		for connected_peer_id in multiplayer_api.get_peers():
			if connected_peer_id == sender_id:
				continue
			_manager.rpc_id(
				connected_peer_id,
				"sync_player_transform_rpc",
				peer_id,
				world_position,
				movement_velocity,
				visual_rotation
			)
		return
	if sender_id == 1:
		apply_network_transform(peer_id, world_position, movement_velocity, visual_rotation)

func request_active_ability(peer_id: int, ability_name: String, sender_id: int) -> void:
	var multiplayer_api: MultiplayerAPI = _manager.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer() or not multiplayer_api.is_server():
		return
	if sender_id != peer_id or peer_id <= 1:
		return
	var player := find_player(peer_id)
	if not player or player.get_multiplayer_authority() != peer_id:
		return
	if player.is_dead or player.shop_open:
		return
	if ability_name != "" and (
		not player.has_ability_component(ability_name)
		or not player.has_ability_charge(ability_name)
	):
		return
	broadcast_active_ability(peer_id, ability_name)

func broadcast_active_ability(peer_id: int, ability_name: String) -> void:
	var multiplayer_api: MultiplayerAPI = _manager.get_multiplayer()
	if multiplayer_api.has_multiplayer_peer():
		if not multiplayer_api.is_server():
			return
		_manager.rpc("sync_player_active_ability_rpc", peer_id, ability_name)
		return
	apply_active_ability(peer_id, ability_name)

func apply_active_ability(peer_id: int, ability_name: String) -> void:
	var player := find_player(peer_id)
	if not player or player.get_multiplayer_authority() != peer_id:
		return
	if ability_name != "" and not player.has_ability_component(ability_name):
		return
	player.call("_apply_active_ability", ability_name)

func publish_health_state(
	peer_id: int,
	current_health: float,
	current_shield: float,
	max_health: float,
	max_shield: float,
	regenerative_reserve: float,
	regenerative_delay: float
) -> void:
	if not _manager.call("is_networked"):
		return
	var multiplayer_api: MultiplayerAPI = _manager.get_multiplayer()
	if multiplayer_api.is_server():
		if peer_id > 0 and _manager.call("find_player", peer_id):
			broadcast_health_state(
				peer_id, current_health, current_shield, max_health, max_shield,
				regenerative_reserve, regenerative_delay
			)
	elif peer_id == multiplayer_api.get_unique_id():
		_manager.rpc_id(
			1, "request_player_health_state", peer_id, current_health, current_shield,
			max_health, max_shield, regenerative_reserve, regenerative_delay
		)

func request_health_state(
	peer_id: int,
	current_health: float,
	current_shield: float,
	max_health: float,
	max_shield: float,
	regenerative_reserve: float,
	regenerative_delay: float
) -> void:
	var multiplayer_api: MultiplayerAPI = _manager.get_multiplayer()
	if not _manager.call("is_networked") or not multiplayer_api.is_server():
		return
	if multiplayer_api.get_remote_sender_id() != peer_id or peer_id <= 1:
		return
	broadcast_health_state(
		peer_id, current_health, current_shield, max_health, max_shield,
		regenerative_reserve, regenerative_delay
	)

func broadcast_health_state(
	peer_id: int,
	current_health: float,
	current_shield: float,
	max_health: float,
	max_shield: float,
	regenerative_reserve: float,
	regenerative_delay: float
) -> void:
	apply_health_state(
		peer_id, current_health, current_shield, max_health, max_shield,
		regenerative_reserve, regenerative_delay
	)
	_manager.rpc(
		"sync_player_health_state_rpc", peer_id, current_health, current_shield,
		max_health, max_shield, regenerative_reserve, regenerative_delay
	)

func receive_health_state(
	peer_id: int,
	current_health: float,
	current_shield: float,
	max_health: float,
	max_shield: float,
	regenerative_reserve: float,
	regenerative_delay: float
) -> void:
	if _manager.get("_peer_lifecycle").is_server_rpc_sender():
		apply_health_state(
			peer_id, current_health, current_shield, max_health, max_shield,
			regenerative_reserve, regenerative_delay
		)

func receive_damage_direction(peer_id: int, direction: Vector2) -> void:
	if _manager.call("is_networked") and _manager.get("_peer_lifecycle").is_server_rpc_sender():
		apply_damage_direction(peer_id, direction)

func receive_damage_flash(peer_id: int) -> void:
	if not _manager.call("is_networked"):
		return
	var multiplayer_api: MultiplayerAPI = _manager.get_multiplayer()
	if not multiplayer_api.is_server() and multiplayer_api.get_remote_sender_id() == 1:
		apply_damage_flash(peer_id)

func apply_health_state(
	peer_id: int,
	current_health: float,
	current_shield: float,
	max_health: float,
	max_shield: float,
	regenerative_reserve: float,
	regenerative_delay: float
) -> void:
	var player := find_player(peer_id)
	if not player:
		return
	player.is_applying_network_health_state = true
	if (
		not is_equal_approx(player.health_component.max_health, max_health)
		or not is_equal_approx(player.health_component.max_shield, max_shield)
	):
		player.health_component.configure_health(max_health, max_shield)
	if (
		not is_equal_approx(player.health_component.current_health, current_health)
		or not is_equal_approx(player.health_component.current_shield, current_shield)
		or not is_equal_approx(
			player.health_component.regenerative_shield_reserve, regenerative_reserve
		)
		or not is_equal_approx(
			player.health_component.regenerative_recharge_delay_remaining, regenerative_delay
		)
	):
		player.health_component.restore_state(
			current_health, current_shield, regenerative_reserve, regenerative_delay
		)
	player.is_applying_network_health_state = false

func apply_damage_direction(peer_id: int, direction: Vector2) -> void:
	var multiplayer_api: MultiplayerAPI = _manager.get_multiplayer()
	var local_peer_id := multiplayer_api.get_unique_id() if multiplayer_api.has_multiplayer_peer() else 1
	if local_peer_id != peer_id:
		return
	var player := find_player(peer_id)
	if not player or not player.is_multiplayer_authority():
		return
	player.call("_emit_damage_direction", direction)

func apply_damage_flash(peer_id: int) -> void:
	var player := find_player(peer_id)
	if not player or player.get_multiplayer_authority() != peer_id:
		return
	player.call("_play_damage_flash")

func prepare_current_scene() -> void:
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return
	var local_agent := current_scene.get_node_or_null("BaseAgent") as BaseAgent
	if not local_agent:
		local_agent = current_scene.get_node_or_null("Player_1") as BaseAgent
	if not local_agent:
		return

	if _manager.call("is_networked"):
		var multiplayer_api: MultiplayerAPI = _manager.get_multiplayer()
		var peer_id := multiplayer_api.get_unique_id()
		local_agent.set_multiplayer_authority(1)
		local_agent.configure_network_visuals(peer_id == 1)
	else:
		local_agent.configure_network_visuals(true)
		var spawn_marker := _manager.call("get_spawn_marker") as Marker2D
		if spawn_marker:
			local_agent.global_position = spawn_marker.global_position
		local_agent.focus_local_camera()
