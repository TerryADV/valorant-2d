extends RefCounted

signal scores_updated(scores: Dictionary, deaths: Dictionary)

const AGENT_SCENE: PackedScene = preload("res://scenes/entities/base_agent.tscn")

var deathmatch_scores: Dictionary = {}
var deathmatch_deaths: Dictionary = {}
var respawning_peers: Dictionary = {}
var _manager: Node
var _max_participants := 12
var _respawn_delay := 3.0

func setup(manager: Node, max_participants: int, respawn_delay: float) -> void:
	_manager = manager
	_max_participants = max_participants
	_respawn_delay = respawn_delay

func handle_player_death(agent: BaseAgent, killer: Node, weapon_name: String) -> void:
	if not agent:
		return
	if _manager.call("is_networked") and not _manager.get_multiplayer().is_server():
		return
	var peer_id := agent.get_multiplayer_authority()
	_manager.get("_match_services").get_combat_report_service().broadcast_combat_report(agent, killer, weapon_name)
	_manager.get("_match_services").get_combat_report_service().broadcast_skirmish_outcomes(agent, killer)
	deathmatch_deaths[peer_id] = int(deathmatch_deaths.get(peer_id, 0)) + 1
	_register_kill(killer, peer_id, weapon_name)
	publish_scores()
	if respawning_peers.has(peer_id):
		return
	broadcast_player_died(peer_id)
	if _manager.call("is_skirmish_mode"):
		return
	respawning_peers[peer_id] = true
	await _manager.get_tree().create_timer(_respawn_delay).timeout
	if not is_instance_valid(agent) or not agent.is_dead:
		respawning_peers.erase(peer_id)
		return
	var spawn_marker := _manager.call("get_spawn_marker", agent) as Marker2D
	if spawn_marker:
		broadcast_player_respawn(peer_id, spawn_marker.global_position)
	else:
		push_error("[Respawn] Could not respawn player %d: no free spawn point." % peer_id)
	respawning_peers.erase(peer_id)

func handle_dummy_death(dummy: BaseAgent, killer: Node, weapon_name: String) -> void:
	if not dummy or (_manager.call("is_networked") and not _manager.get_multiplayer().is_server()):
		return
	var dummy_id := dummy.get_deathmatch_id()
	_manager.get("_match_services").get_combat_report_service().broadcast_skirmish_outcomes(dummy, killer)
	deathmatch_deaths[dummy_id] = int(deathmatch_deaths.get(dummy_id, 0)) + 1
	_register_kill(killer, dummy_id, weapon_name)
	publish_scores()
	if _manager.call("is_networked"):
		dummy.sync_dummy_lifecycle.rpc(false, dummy.global_position)
	else:
		dummy.sync_dummy_lifecycle(false, dummy.global_position)
	if _manager.call("is_skirmish_mode"):
		return
	if respawning_peers.has(dummy_id):
		return
	respawning_peers[dummy_id] = true
	await _manager.get_tree().create_timer(_respawn_delay).timeout
	if is_instance_valid(dummy):
		dummy.respawn_dummy()
	respawning_peers.erase(dummy_id)

func _register_kill(killer: Node, victim_id: int, weapon_name: String) -> void:
	var killer_id := get_actor_id(killer)
	if killer_id == 0 or killer_id == victim_id:
		return
	deathmatch_scores[killer_id] = int(deathmatch_scores.get(killer_id, 0)) + 1
	if killer is BaseAgent and not killer.is_ai_dummy:
		for component in killer.get_node("Components").get_children():
			if component.has_method("grant_kill_charge"):
				component.call("grant_kill_charge")
	broadcast_kill_feed(killer_id, victim_id, weapon_name)

func publish_scores() -> void:
	if _manager.call("is_networked"):
		_manager.rpc(
			"sync_deathmatch_scores",
			deathmatch_scores.duplicate(true),
			deathmatch_deaths.duplicate(true)
		)
	else:
		scores_updated.emit(deathmatch_scores.duplicate(true), deathmatch_deaths.duplicate(true))

func broadcast_kill_feed(killer_id: int, victim_id: int, weapon_name: String) -> void:
	if _manager.call("is_networked"):
		_manager.rpc("kill_feed_event", killer_id, victim_id, weapon_name)
	else:
		_manager.emit_signal("kill_feed_received", killer_id, victim_id, weapon_name)

func broadcast_player_died(peer_id: int) -> void:
	if _manager.call("is_networked"):
		_manager.rpc("player_died", peer_id)
	else:
		_manager.call("player_died", peer_id)

func broadcast_player_respawn(peer_id: int, spawn_position: Vector2) -> void:
	if _manager.call("is_networked"):
		_manager.rpc("respawn_player", peer_id, spawn_position)
	else:
		_manager.call("respawn_player", peer_id, spawn_position)

func broadcast_dummy_spawn(
	dummy_index: int,
	spawn_position: Vector2,
	weapon_index: int,
	dummy_difficulty: int,
	agent_index: int
) -> void:
	if _manager.call("is_networked"):
		_manager.rpc("sync_dummy_spawn", dummy_index, spawn_position, weapon_index, dummy_difficulty, agent_index)
	else:
		_manager.call("sync_dummy_spawn", dummy_index, spawn_position, weapon_index, dummy_difficulty, agent_index)

func broadcast_dummy_despawn(dummy_index: int) -> void:
	if _manager.call("is_networked"):
		_manager.rpc("sync_dummy_despawn", dummy_index)
	else:
		_manager.call("sync_dummy_despawn", dummy_index)

func apply_scores(scores: Dictionary, deaths: Dictionary) -> void:
	deathmatch_scores = scores.duplicate(true)
	deathmatch_deaths = deaths.duplicate(true)
	scores_updated.emit(deathmatch_scores.duplicate(true), deathmatch_deaths.duplicate(true))

func get_actor_id(actor: Node) -> int:
	if actor is BaseAgent and actor.is_ai_dummy:
		return actor.get_deathmatch_id()
	if actor is BaseAgent:
		return actor.get_multiplayer_authority()
	return 0

func find_actor(actor_id: int) -> Node:
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return null
	return _find_actor_in(current_scene, actor_id)

func _find_actor_in(node: Node, actor_id: int) -> Node:
	if get_actor_id(node) == actor_id:
		return node
	for child in node.get_children():
		var actor := _find_actor_in(child, actor_id)
		if actor:
			return actor
	return null

func report_agent_kill_effect(agent: BaseAgent, attacker: Node, effect_name: String) -> void:
	if not agent or (_manager.call("is_networked") and not _manager.get_multiplayer().is_server()):
		return
	if effect_name.is_empty():
		push_error("Cannot report an agent kill effect without a name.")
		return
	broadcast_kill_feed(get_actor_id(attacker), agent.get_multiplayer_authority(), effect_name)

func start_solo_match(dummy_count: int, dummy_difficulty: int) -> bool:
	if dummy_count < 0 or dummy_count >= _max_participants:
		push_error("[MatchStart] Solo bot count must be between 0 and 11.")
		return false
	if dummy_difficulty < BaseAgent.Difficulty.EASY or dummy_difficulty > BaseAgent.Difficulty.HARD:
		push_error("[MatchStart] Invalid solo bot difficulty.")
		return false
	if _manager.call("is_networked"):
		_manager.call("disconnect_game")
	elif _manager.get("peer") != null or _manager.get("connection_pending"):
		_manager.call("disconnect_game")
	deathmatch_scores.clear()
	deathmatch_deaths.clear()
	respawning_peers.clear()
	var pending_weapon_slots: Dictionary = _manager.get("pending_weapon_slots")
	pending_weapon_slots.clear()

	var current_scene := _manager.get_tree().current_scene
	var local_agent: BaseAgent = null
	if current_scene:
		local_agent = _manager.call("get_local_agent", current_scene) as BaseAgent
	if not local_agent:
		push_error("The Deathmatch map has no local player.")
		return false
	var spawn_marker := get_spawn_marker(local_agent)
	if not spawn_marker:
		push_error("Cannot start the solo match because no free spawn point is available.")
		return false

	var mode_selector := current_scene.get_node_or_null("GameModeSelector") as GameModeSelector
	if mode_selector:
		mode_selector.selected_mode = GameModeSelector.Mode.DEATHMATCH
	local_agent.global_position = spawn_marker.global_position
	local_agent.visible = true
	local_agent.configure_network_visuals(true)
	local_agent.validate_visual_configuration()
	local_agent.grant_spawn_protection()
	await _manager.get("_match_services").get_preparation_service().update_dummy_population_async(
		1, dummy_count, dummy_difficulty
	)
	_manager.get("_match_flow").show_match_hud()
	var hud := current_scene.get_node_or_null("HUD") as GameHud
	if hud:
		hud.refresh_game_mode()
	return true

func get_max_bot_count(human_count: int) -> int:
	if human_count <= 0:
		return 0
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return 0
	var spawn_count := get_scene_spawn_markers(current_scene).size()
	return maxi(0, mini(_max_participants - human_count, spawn_count - human_count))

func get_spawn_marker(excluded_actor: Node = null, preferred_index: int = -1) -> Marker2D:
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		push_error("Cannot find a spawn point without an active scene.")
		return null
	var spawn_markers := get_scene_spawn_markers(current_scene)
	if spawn_markers.is_empty():
		push_error("No Marker2D nodes are in the 'spawn_points' group in the active scene.")
		return null
	var available_markers: Array[Marker2D] = []
	for marker in spawn_markers:
		if not _is_spawn_marker_occupied(marker, excluded_actor, current_scene):
			available_markers.append(marker)
	if available_markers.is_empty():
		push_error("No unoccupied spawn point is available for the participant.")
		return null
	if preferred_index >= 0:
		var preferred_marker := spawn_markers[posmod(preferred_index, spawn_markers.size())]
		if available_markers.has(preferred_marker):
			return preferred_marker
	return available_markers[randi_range(0, available_markers.size() - 1)]

func get_match_spawn_marker(excluded_actor: Node = null, preferred_index: int = -1) -> Marker2D:
	if _manager.call("is_skirmish_mode") and excluded_actor is BaseAgent:
		var team_id := int(excluded_actor.get("skirmish_team"))
		if team_id >= 0:
			return get_spawn_marker_for_team(team_id, excluded_actor, preferred_index)
	return get_spawn_marker(excluded_actor, preferred_index)

func get_match_different_spawn_marker(actor: BaseAgent) -> Marker2D:
	if _manager.call("is_skirmish_mode") and actor.skirmish_team >= 0:
		return get_different_spawn_marker_for_team(actor, actor.skirmish_team)
	return get_different_spawn_marker(actor)

func get_spawn_marker_for_team(
	team_id: int,
	excluded_actor: Node = null,
	preferred_index: int = -1
) -> Marker2D:
	var current_scene := _manager.get_tree().current_scene
	if not current_scene or team_id < 0 or team_id > 1:
		return null
	var team_name := "EquipA" if team_id == 0 else "EquipB"
	var team_node := current_scene.get_node_or_null("Spawnpoint/%s" % team_name)
	if not team_node:
		return null
	var team_markers: Array[Marker2D] = []
	for child in team_node.get_children():
		if child is Marker2D:
			team_markers.append(child)
	var available_markers: Array[Marker2D] = []
	for marker in team_markers:
		if not _is_spawn_marker_occupied(marker, excluded_actor, current_scene):
			available_markers.append(marker)
	if available_markers.is_empty():
		push_error("No free Skirmish spawn point is available for team %d." % team_id)
		return null
	if preferred_index >= 0 and preferred_index < team_markers.size():
		var preferred_marker := team_markers[preferred_index]
		if available_markers.has(preferred_marker):
			return preferred_marker
	return available_markers[randi_range(0, available_markers.size() - 1)]

func get_different_spawn_marker_for_team(actor: BaseAgent, team_id: int) -> Marker2D:
	if not actor:
		return null
	var current_scene := _manager.get_tree().current_scene
	if not current_scene or team_id < 0 or team_id > 1:
		return null
	var team_name := "EquipA" if team_id == 0 else "EquipB"
	var team_node := current_scene.get_node_or_null("Spawnpoint/%s" % team_name)
	if not team_node:
		return null
	var available_markers: Array[Marker2D] = []
	for child in team_node.get_children():
		if not (child is Marker2D):
			continue
		var marker := child as Marker2D
		if marker.global_position.distance_squared_to(actor.global_position) < 1.0:
			continue
		if not _is_spawn_marker_occupied(marker, actor, current_scene):
			available_markers.append(marker)
	if available_markers.is_empty():
		return null
	return available_markers[randi_range(0, available_markers.size() - 1)]

func get_different_spawn_marker(actor: BaseAgent) -> Marker2D:
	if not actor:
		push_error("Cannot select a new spawn point for an empty agent.")
		return null
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		push_error("Cannot select a new spawn point without an active scene.")
		return null
	var available_markers: Array[Marker2D] = []
	for marker in get_scene_spawn_markers(current_scene):
		if marker.global_position.distance_squared_to(actor.global_position) < 1.0:
			continue
		if not _is_spawn_marker_occupied(marker, actor, current_scene):
			available_markers.append(marker)
	if available_markers.is_empty():
		push_error("No unoccupied spawn point different from the player's current position is available.")
		return null
	return available_markers[randi_range(0, available_markers.size() - 1)]

func get_scene_spawn_markers(current_scene: Node) -> Array[Marker2D]:
	var spawn_markers: Array[Marker2D] = []
	for spawn_node in _manager.get_tree().get_nodes_in_group("spawn_points"):
		if spawn_node is Marker2D and current_scene.is_ancestor_of(spawn_node):
			spawn_markers.append(spawn_node as Marker2D)
	return spawn_markers

func _is_spawn_marker_occupied(marker: Marker2D, excluded_actor: Node, node: Node) -> bool:
	if node != excluded_actor and node is BaseAgent and not node.is_queued_for_deletion():
		var agent := node as BaseAgent
		var occupies_spawn := not agent.is_ai_dummy or agent.is_in_match
		if (
			occupies_spawn
			and agent.visible
			and not agent.is_dead
			and agent.global_position.distance_squared_to(marker.global_position) < 1.0
		):
			return true
	for child in node.get_children():
		if _is_spawn_marker_occupied(marker, excluded_actor, child):
			return true
	return false

func get_dummies() -> Array[BaseAgent]:
	var dummies: Array[BaseAgent] = []
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return dummies
	for child in current_scene.get_children():
		if child is BaseAgent and child.is_ai_dummy:
			dummies.append(child as BaseAgent)
	dummies.sort_custom(func(first: BaseAgent, second: BaseAgent) -> bool:
		return absi(first.get_deathmatch_id()) < absi(second.get_deathmatch_id())
	)
	return dummies

func get_room_dummies() -> Array[BaseAgent]:
	var room_dummies: Array[BaseAgent] = []
	for dummy in get_dummies():
		if dummy.is_in_match:
			room_dummies.append(dummy)
	return room_dummies

func update_dummy_population(
	human_count: int,
	requested_dummy_count: int = -1,
	dummy_difficulty: int = BaseAgent.Difficulty.HARD
) -> void:
	if _manager.call("is_networked") and not _manager.get_multiplayer().is_server():
		return
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		push_error("Cannot fill the Deathmatch room without an active scene.")
		return
	var spawn_markers := get_scene_spawn_markers(current_scene)
	if spawn_markers.is_empty():
		push_error("Cannot fill the Deathmatch room: the active scene has no spawn_points markers.")
		return
	var available_dummy_count := mini(_max_participants - human_count, spawn_markers.size() - human_count)
	var target_dummy_count := mini(requested_dummy_count, available_dummy_count) if requested_dummy_count >= 0 else available_dummy_count
	if target_dummy_count < 0:
		push_error("Not enough spawn points for the current Deathmatch players.")
		return

	var room_dummies := get_room_dummies()
	while room_dummies.size() > target_dummy_count:
		var last_dummy: BaseAgent = room_dummies.pop_back()
		var removed_dummy_index := absi(last_dummy.get_deathmatch_id()) - 1
		broadcast_dummy_despawn(removed_dummy_index)

	var dummy_index := 0
	while room_dummies.size() < target_dummy_count:
		var dummies := get_dummies()
		if dummy_index < dummies.size() and dummies[dummy_index].is_in_match:
			dummy_index += 1
			continue
		var spawn_marker := get_spawn_marker(null, dummy_index)
		if not spawn_marker:
			push_error(
				("[DummySpawn] Aborting room fill at slot %d: no free spawn point. "
				+ "active_dummies=%d target_dummies=%d.")
				% [dummy_index, room_dummies.size(), target_dummy_count]
			)
			return
		var weapon_index := randi_range(0, BaseAgent.AVAILABLE_WEAPONS.size() - 1)
		var agent_index := randi_range(0, BaseAgent.AVAILABLE_AGENTS.size() - 1)
		broadcast_dummy_spawn(
			dummy_index,
			spawn_marker.global_position,
			weapon_index,
			dummy_difficulty,
			agent_index
		)
		room_dummies = get_room_dummies()
		dummies = get_dummies()
		if dummy_index >= dummies.size():
			push_error("[DummySpawn] Spawn slot %d was not created." % dummy_index)
			return
		var spawned_dummy := dummies[dummy_index]
		if not spawned_dummy.is_in_match or not spawned_dummy.visible:
			push_error(
				"[DummySpawn] Slot %d failed activation: visible=%s in_match=%s."
				% [dummy_index, spawned_dummy.visible, spawned_dummy.is_in_match]
			)
			return
		dummy_index += 1
	if room_dummies.size() != target_dummy_count:
		push_error(
			"Deathmatch room fill incomplete: expected %d dummies, got %d."
			% [target_dummy_count, room_dummies.size()]
		)

func _get_or_create_dummy(dummy_index: int, agent_index: int) -> BaseAgent:
	var dummies := get_dummies()
	while dummies.size() <= dummy_index:
		var dummy := AGENT_SCENE.instantiate() as BaseAgent
		if not dummy:
			push_error("Could not instantiate the dummy scene.")
			return null
		dummy.name = "Dummy_%02d" % (dummies.size() + 1)
		dummy.is_ai_dummy = true
		dummy.agent_index = agent_index
		dummy.agent_data = BaseAgent.AVAILABLE_AGENTS[agent_index] as AgentData
		dummy.set_multiplayer_authority(1)
		dummy.visible = false
		_manager.get_tree().current_scene.add_child(dummy, true)
		dummies = get_dummies()
	return dummies[dummy_index]

func sync_dummy_spawn(
	dummy_index: int,
	spawn_position: Vector2,
	weapon_index: int,
	dummy_difficulty: int,
	agent_index: int,
	server_sender: bool
) -> void:
	if not server_sender or dummy_index < 0 or not spawn_position.is_finite():
		return
	if weapon_index < 0 or weapon_index >= BaseAgent.AVAILABLE_WEAPONS.size():
		return
	if dummy_difficulty < BaseAgent.Difficulty.EASY or dummy_difficulty > BaseAgent.Difficulty.HARD:
		return
	if agent_index < 0 or agent_index >= BaseAgent.AVAILABLE_AGENTS.size():
		return
	var dummy := _get_or_create_dummy(dummy_index, agent_index)
	if dummy:
		dummy.initialize_for_match(
			spawn_position,
			BaseAgent.AVAILABLE_WEAPONS[weapon_index],
			dummy_difficulty,
			agent_index
		)
		deathmatch_scores.erase(dummy.get_deathmatch_id())
		deathmatch_deaths.erase(dummy.get_deathmatch_id())
		if _manager.call("is_skirmish_mode"):
			dummy.skirmish_team = int(_manager.call("get_skirmish_team_for_position", spawn_position))

func sync_dummy_despawn(dummy_index: int, server_sender: bool) -> void:
	if not server_sender or dummy_index < 0:
		return
	var dummies := get_dummies()
	if dummy_index >= dummies.size():
		return
	var dummy := dummies[dummy_index]
	var current_scene := _manager.get_tree().current_scene
	current_scene.remove_child(dummy)
	dummy.queue_free()
