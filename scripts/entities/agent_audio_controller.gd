extends RefCounted

var _agent: Node

func setup(agent: Node) -> void:
	_agent = agent

func play_reload(weapon_slot: int) -> void:
	var weapon_controller: Node = _agent.get("weapon_controller")
	var weapon_slots: Array = weapon_controller.get("weapon_slots")
	if weapon_slot < 0 or weapon_slot >= weapon_slots.size():
		push_error("Cannot play reload audio for an invalid weapon slot.")
		return
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer():
		var weapon := weapon_slots[weapon_slot] as WeaponData
		if weapon:
			AudioManager.play_world_cue(weapon.reload_audio, Vector2(_agent.get("global_position")))
	elif multiplayer_api.is_server():
		_broadcast_reload(weapon_slot)
	else:
		_agent.rpc_id(1, "request_reload_sfx_rpc", weapon_slot)

func play_footstep() -> void:
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer():
		AudioManager.play_event_world(_get_footstep_cue_id(), Vector2(_agent.get("global_position")))
	elif multiplayer_api.is_server():
		_broadcast_footstep()
	else:
		_agent.rpc_id(1, "request_footstep_sfx_rpc", true)

func play_melee(heavy_attack: bool) -> void:
	var weapon_controller: Node = _agent.get("weapon_controller")
	var current_weapon := weapon_controller.get("current_weapon") as WeaponData
	if not current_weapon or not current_weapon.is_melee:
		return
	var weapon_name := current_weapon.weapon_name
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer():
		_agent.call(
			"sync_melee_sfx_rpc",
			weapon_name,
			heavy_attack,
			Vector2(_agent.get("global_position"))
		)
	elif multiplayer_api.is_server():
		_broadcast_melee(weapon_name, heavy_attack)
	else:
		_agent.rpc_id(1, "request_melee_sfx_rpc", weapon_name, heavy_attack)

func handle_melee_request(weapon_name: String, heavy_attack: bool) -> void:
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer() or not multiplayer_api.is_server():
		return
	if multiplayer_api.get_remote_sender_id() != _agent.get_multiplayer_authority():
		return
	var weapon_controller: Node = _agent.get("weapon_controller")
	var current_weapon := weapon_controller.get("current_weapon") as WeaponData
	if (
		bool(_agent.get("is_dead"))
		or not current_weapon
		or not current_weapon.is_melee
		or current_weapon.weapon_name != weapon_name
	):
		return
	var current_time_msec := Time.get_ticks_msec()
	if current_time_msec - int(_agent.get("last_melee_sfx_request_msec")) < 120:
		return
	_agent.set("last_melee_sfx_request_msec", current_time_msec)
	_broadcast_melee(weapon_name, heavy_attack)

func sync_melee(weapon_name: String, heavy_attack: bool, world_position: Vector2) -> void:
	if not _is_server_audio_sender():
		return
	if not world_position.is_finite():
		push_warning("Rejected melee audio at a non-finite position.")
		return
	var weapon_controller: Node = _agent.get("weapon_controller")
	var weapon := weapon_controller.call("get_weapon_by_name", weapon_name) as WeaponData
	if not weapon or not weapon.is_melee:
		push_warning("Rejected melee audio for an invalid melee weapon.")
		return
	weapon_controller.call("animate_melee_attack", heavy_attack)
	var cue: AudioCue = weapon.melee_heavy_audio if heavy_attack else weapon.melee_light_audio
	AudioManager.play_world_cue(cue, world_position)

func handle_footstep_request(allow_footstep_audio: bool) -> void:
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer() or not multiplayer_api.is_server():
		return
	if multiplayer_api.get_remote_sender_id() != _agent.get_multiplayer_authority():
		return
	if (
		not allow_footstep_audio
		or bool(_agent.get("is_dead"))
		or bool(_agent.get("is_movement_locked"))
	):
		return
	if Vector2(_agent.get("velocity")).length() < 8.0:
		return
	var current_time_msec := Time.get_ticks_msec()
	if current_time_msec - int(_agent.get("last_footstep_request_msec")) < 220:
		return
	_agent.set("last_footstep_request_msec", current_time_msec)
	_broadcast_footstep()

func sync_footstep(world_position: Vector2) -> void:
	if not _is_server_audio_sender():
		return
	if not world_position.is_finite():
		push_warning("Rejected a footstep sound at a non-finite position.")
		return
	AudioManager.play_event_world(_get_footstep_cue_id(), world_position)

func handle_reload_request(weapon_slot: int) -> void:
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer() or not multiplayer_api.is_server():
		return
	if multiplayer_api.get_remote_sender_id() != _agent.get_multiplayer_authority():
		return
	var weapon_controller: Node = _agent.get("weapon_controller")
	var current_weapon := weapon_controller.get("current_weapon") as WeaponData
	if (
		bool(_agent.get("is_dead"))
		or weapon_slot != int(weapon_controller.get("current_weapon_slot"))
		or not current_weapon
		or current_weapon.is_melee
	):
		return
	var current_time_msec := Time.get_ticks_msec()
	if current_time_msec - int(_agent.get("last_reload_sfx_request_msec")) < 200:
		return
	_agent.set("last_reload_sfx_request_msec", current_time_msec)
	_broadcast_reload(weapon_slot)

func sync_reload(weapon_slot: int, world_position: Vector2) -> void:
	if not _is_server_audio_sender():
		return
	var weapon_controller: Node = _agent.get("weapon_controller")
	var weapon_slots: Array = weapon_controller.get("weapon_slots")
	if weapon_slot < 0 or weapon_slot >= weapon_slots.size():
		push_warning("Rejected reload audio for an invalid weapon slot.")
		return
	var weapon := weapon_slots[weapon_slot] as WeaponData
	if weapon:
		AudioManager.play_world_cue(weapon.reload_audio, world_position)

func _broadcast_melee(weapon_name: String, heavy_attack: bool) -> void:
	_agent.rpc(
		"sync_melee_sfx_rpc",
		weapon_name,
		heavy_attack,
		Vector2(_agent.get("global_position"))
	)

func _broadcast_footstep() -> void:
	_agent.rpc("sync_footstep_sfx_rpc", Vector2(_agent.get("global_position")))

func _get_footstep_cue_id() -> StringName:
	var slow_zone_sources: Dictionary = _agent.get("slow_zone_sources")
	if not slow_zone_sources.is_empty():
		return &"slow_orb_step"
	var movement_controller := _agent.get("movement_controller") as Node
	var movement_slow_zone_sources: Dictionary = {}
	if movement_controller:
		movement_slow_zone_sources = movement_controller.get("slow_zone_sources") as Dictionary
	if not movement_slow_zone_sources.is_empty():
		return &"slow_orb_step"
	return &"steps"

func _broadcast_reload(weapon_slot: int) -> void:
	var weapon_controller: Node = _agent.get("weapon_controller")
	var weapon_slots: Array = weapon_controller.get("weapon_slots")
	if weapon_slot < 0 or weapon_slot >= weapon_slots.size():
		push_error("Cannot broadcast reload audio for an invalid weapon slot.")
		return
	_agent.rpc("sync_reload_sfx_rpc", weapon_slot, Vector2(_agent.get("global_position")))

func _is_server_audio_sender() -> bool:
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer():
		return true
	var sender_id := multiplayer_api.get_remote_sender_id()
	if multiplayer_api.is_server():
		return sender_id == 0 or sender_id == 1
	return sender_id == 1
