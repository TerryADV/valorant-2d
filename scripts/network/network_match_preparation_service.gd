extends RefCounted

var _manager: Node

func setup(manager: Node) -> void:
	_manager = manager

func update_dummy_population_async(
	human_count: int,
	requested_dummy_count: int,
	dummy_difficulty: int
) -> void:
	if _manager.call("is_networked") and not _manager.get_multiplayer().is_server():
		return
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return
	var deathmatch: Object = _manager.get("_deathmatch_service")
	var available_count := int(_manager.call("get_max_bot_count", human_count))
	var target_count: int = mini(requested_dummy_count, available_count)
	if target_count < 0:
		push_error("Not enough spawn points to prepare the Deathmatch bots.")
		return

	var room_dummies: Array = deathmatch.call("get_room_dummies")
	while room_dummies.size() > target_count:
		var removed := room_dummies.pop_back() as BaseAgent
		deathmatch.call("broadcast_dummy_despawn", absi(removed.get_deathmatch_id()) - 1)
		await _manager.get_tree().process_frame

	var dummy_index := 0
	while room_dummies.size() < target_count:
		var dummies: Array = deathmatch.call("get_dummies")
		if dummy_index < dummies.size() and (dummies[dummy_index] as BaseAgent).is_in_match:
			dummy_index += 1
			continue
		var spawn_marker := deathmatch.call("get_spawn_marker", null, dummy_index) as Marker2D
		if not spawn_marker:
			push_error("Could not find a spawn while preparing Deathmatch bots.")
			return
		deathmatch.call(
			"broadcast_dummy_spawn",
			dummy_index,
			spawn_marker.global_position,
			randi_range(0, BaseAgent.AVAILABLE_WEAPONS.size() - 1),
			dummy_difficulty,
			randi_range(0, BaseAgent.AVAILABLE_AGENTS.size() - 1)
		)
		await _manager.get_tree().process_frame
		room_dummies = deathmatch.call("get_room_dummies")
		dummy_index += 1
