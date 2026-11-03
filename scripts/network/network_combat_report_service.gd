extends RefCounted

var _manager: Node

func setup(manager: Node) -> void:
	_manager = manager

func broadcast_combat_report(victim: BaseAgent, killer: Node, weapon_name: String) -> void:
	if not victim or not is_instance_valid(killer):
		return
	var killer_name := "Unknown"
	var killer_agent_id := ""
	var killer_sprite_path := ""
	var outgoing_damage := (
		victim.get_combat_damage_dealt_total()
		if _manager.call("is_skirmish_mode")
		else victim.get_combat_damage_dealt_to(killer)
	)
	var incoming_damage := (
		victim.get_combat_damage_received_total()
		if _manager.call("is_skirmish_mode")
		else victim.get_combat_damage_received_from(killer)
	)
	var damage_source_paths: Array = get_damage_source_paths(victim)
	var attacker_details: Array = get_attacker_details(victim)
	if killer is BaseAgent and not killer.is_ai_dummy:
		var peer_id := killer.get_multiplayer_authority()
		killer_name = _manager.call("get_player_display_name", peer_id)
		if killer.agent_data:
			killer_agent_id = killer.agent_data.agent_id
			killer_sprite_path = killer.agent_data.agent_sprite.resource_path if killer.agent_data.agent_sprite else ""
	elif killer is BaseAgent and killer.is_ai_dummy:
		killer_name = str(killer.get("display_name"))
		var killer_sprite := killer.get_agent_sprite() as Texture2D
		killer_sprite_path = killer_sprite.resource_path if killer_sprite else ""
	if _manager.call("is_networked"):
		if victim.get_multiplayer_authority() != _manager.get_multiplayer().get_unique_id():
			_manager.rpc_id(
				victim.get_multiplayer_authority(), "combat_report_event", killer_name,
				killer_agent_id, killer_sprite_path, weapon_name, outgoing_damage,
				incoming_damage, damage_source_paths, attacker_details
			)
		else:
			_emit_combat_report(
				killer_name, killer_agent_id, killer_sprite_path, weapon_name,
				outgoing_damage, incoming_damage, damage_source_paths, attacker_details
			)
	elif victim.get_multiplayer_authority() == 1:
		_emit_combat_report(
			killer_name, killer_agent_id, killer_sprite_path, weapon_name,
			outgoing_damage, incoming_damage, damage_source_paths, attacker_details
		)

func get_attacker_details(victim: BaseAgent) -> Array:
	var details: Array = []
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return details
	for actor in current_scene.get_children():
		if not actor is BaseAgent:
			continue
		var actor_name := "Unknown"
		var sprite: Texture2D
		var actor_id := actor.get_instance_id()
		if not actor.is_ai_dummy:
			actor_name = _manager.call("get_player_display_name", actor.get_multiplayer_authority())
			sprite = actor.agent_data.agent_sprite if actor.agent_data else null
		else:
			actor_name = str(actor.get("display_name"))
			sprite = actor.get_agent_sprite() as Texture2D
		var incoming_by_life: Dictionary = victim.combat_damage_received_by_life.get(actor_id, {})
		var outgoing_by_life: Dictionary = victim.combat_damage_dealt_to_actor_by_life.get(actor_id, {})
		var weapons_by_life: Dictionary = victim.combat_damage_received_weapon_by_life.get(actor_id, {})
		var life_ids: Dictionary = {}
		for life_id in incoming_by_life:
			life_ids[int(life_id)] = true
		for life_id in outgoing_by_life:
			life_ids[int(life_id)] = true
		for life_id in life_ids:
			var incoming_damage := float(incoming_by_life.get(life_id, 0.0))
			var outgoing_damage := float(outgoing_by_life.get(life_id, 0.0))
			if incoming_damage <= 0.0 and outgoing_damage <= 0.0:
				continue
			details.append({
				"name": actor_name,
				"actor_id": actor.get_deathmatch_id(),
				"life_id": int(life_id),
				"sprite_path": sprite.resource_path if sprite else "",
				"incoming": incoming_damage,
				"outgoing": outgoing_damage,
				"weapon": str(weapons_by_life.get(life_id, "")),
				"is_killer": (
					actor == victim.last_attacker
					and int(life_id) == int(victim.last_attacker_life_id)
				),
			})
	details.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return float(first.get("incoming", 0.0)) > float(second.get("incoming", 0.0))
	)
	return details

func get_damage_source_paths(victim: BaseAgent) -> Array:
	var paths: Array = []
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return paths
	for actor in current_scene.get_children():
		if not actor is BaseAgent or victim.get_combat_damage_received_from(actor) <= 0.0:
			continue
		var sprite: Texture2D
		if actor.agent_data:
			sprite = actor.agent_data.agent_sprite
		if sprite and not sprite.resource_path.is_empty() and not paths.has(sprite.resource_path):
			paths.append(sprite.resource_path)
	return paths

func broadcast_skirmish_outcomes(victim: Node, killer: Node) -> void:
	if not _manager.call("is_skirmish_mode") or not victim or not is_instance_valid(killer):
		return
	var killer_team := int(killer.get("skirmish_team"))
	if killer_team < 0 or killer_team > 1:
		return
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return
	for actor in current_scene.get_children():
		if not actor is BaseAgent or actor.is_ai_dummy or actor.skirmish_team != killer_team:
			continue
		var outgoing_damage := 0.0
		if victim is BaseAgent:
			outgoing_damage = victim.get_combat_damage_received_from(actor)
		var outcome := "KILL" if actor == killer else "ASSIST"
		if actor != killer and outgoing_damage < 50.0:
			continue
		broadcast_skirmish_outcome(
			actor.get_multiplayer_authority(),
			outcome,
			outgoing_damage,
			victim.get_deathmatch_id() if victim is BaseAgent else -1,
			int(victim.get("combat_life_id")) if victim is BaseAgent else -1
		)


func broadcast_skirmish_outcome(
	peer_id: int,
	outcome: String,
	outgoing_damage: float,
	target_actor_id: int,
	target_life_id: int
) -> void:
	if _manager.call("is_networked"):
		if peer_id == _manager.get_multiplayer().get_unique_id():
			_manager.emit_signal(
				"skirmish_combat_outcome_received",
				outcome,
				outgoing_damage,
				target_actor_id,
				target_life_id
			)
		else:
			_manager.rpc_id(
				peer_id,
				"sync_skirmish_combat_outcome",
				outcome,
				outgoing_damage,
				target_actor_id,
				target_life_id
			)
	elif peer_id == 1:
		_manager.emit_signal(
			"skirmish_combat_outcome_received",
			outcome,
			outgoing_damage,
			target_actor_id,
			target_life_id
		)

func apply_skirmish_outcome(
	outcome: String,
	outgoing_damage: float,
	target_actor_id: int,
	target_life_id: int
) -> void:
	if not _manager.get("_peer_lifecycle").is_server_rpc_sender() or not ["KILL", "ASSIST"].has(outcome):
		return
	_manager.emit_signal(
		"skirmish_combat_outcome_received",
		outcome,
		outgoing_damage,
		target_actor_id,
		target_life_id
	)

func _emit_combat_report(
	killer_name: String,
	killer_agent_id: String,
	killer_sprite_path: String,
	weapon_name: String,
	outgoing_damage: float,
	incoming_damage: float,
	damage_source_paths: Array,
	attacker_details: Array
) -> void:
	_manager.emit_signal(
		"combat_report_received", killer_name, killer_agent_id, killer_sprite_path,
		weapon_name, outgoing_damage, incoming_damage, damage_source_paths, attacker_details
	)
