extends RefCounted

var _manager: Node

func setup(manager: Node) -> void:
	_manager = manager

func play_global_sfx(sound_id: StringName) -> void:
	if not AudioManager.has_cue(sound_id):
		return
	if not _manager.call("is_networked"):
		AudioManager.play_event_global(sound_id)
	elif _manager.get_multiplayer().is_server():
		_manager.rpc("sync_global_sfx_rpc", sound_id)
	else:
		push_error("Only the server can broadcast a global sound effect.")

func receive_global_sfx(sound_id: StringName, has_peer: bool, is_server: bool, sender_id: int) -> void:
	if has_peer:
		if is_server:
			if sender_id != 0 and sender_id != 1:
				return
		elif sender_id != 1:
			return
	if not AudioManager.has_cue(sound_id):
		return
	AudioManager.play_event_global_local(sound_id)

func play_audio_cue_on_all_peers(stream_path: String, volume_db: float, pitch: float) -> void:
	if not _manager.call("is_networked"):
		_play_stream_locally(stream_path, volume_db, pitch)
	elif _manager.get_multiplayer().is_server():
		_manager.rpc("sync_audio_cue_rpc", stream_path, volume_db, pitch)
	else:
		_manager.rpc_id(1, "request_audio_cue_rpc", stream_path, volume_db, pitch)

func play_audio_cue_on_team(stream_path: String, volume_db: float, pitch: float) -> void:
	if not _manager.call("is_networked"):
		_play_stream_locally(stream_path, volume_db, pitch)
		return
	if not _manager.call("is_skirmish_mode") or not is_valid_audio_request(stream_path, volume_db, pitch):
		return
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return
	var local_agent := _manager.call("get_local_agent", current_scene) as BaseAgent
	if not local_agent:
		return
	var team_id := int(local_agent.get("skirmish_team"))
	if team_id < 0:
		return
	if _manager.get_multiplayer().is_server():
		sync_team_audio_cue_to_members(stream_path, volume_db, pitch, team_id)
	else:
		_manager.rpc_id(1, "request_team_audio_cue_rpc", stream_path, volume_db, pitch, team_id)

func request_team_audio_cue(
	stream_path: String,
	volume_db: float,
	pitch: float,
	team_id: int
) -> void:
	if (
		not _manager.call("is_networked")
		or not _manager.get_multiplayer().is_server()
		or not _manager.call("is_skirmish_mode")
		or team_id < 0
		or not is_valid_audio_request(stream_path, volume_db, pitch)
	):
		return
	var sender_id := _manager.get_multiplayer().get_remote_sender_id()
	if int(_manager.call("get_skirmish_team_for_peer", sender_id)) != team_id:
		return
	sync_team_audio_cue_to_members(stream_path, volume_db, pitch, team_id)

func sync_team_audio_cue_to_members(
	stream_path: String,
	volume_db: float,
	pitch: float,
	team_id: int
) -> void:
	if int(_manager.call("get_skirmish_team_for_peer", 1)) == team_id:
		play_team_audio_cue_locally(stream_path, volume_db, pitch, team_id)
	if _manager.get_multiplayer().get_peers().has(1):
		return
	var team_assignments: Dictionary = _manager.get("skirmish_team_assignments")
	for peer_id_value in team_assignments:
		var peer_id := int(peer_id_value)
		if peer_id > 1 and int(team_assignments[peer_id_value]) == team_id:
			_manager.rpc_id(peer_id, "sync_team_audio_cue_rpc", stream_path, volume_db, pitch, team_id)

func receive_team_audio_cue(
	stream_path: String,
	volume_db: float,
	pitch: float,
	team_id: int
) -> void:
	if (
		not _manager.call("is_networked")
		or not _manager.call("is_skirmish_mode")
		or not is_valid_audio_request(stream_path, volume_db, pitch)
	):
		return
	var sender_id := _manager.get_multiplayer().get_remote_sender_id()
	if _manager.get_multiplayer().is_server():
		if sender_id != 0:
			return
	elif sender_id != 1:
		return
	play_team_audio_cue_locally(stream_path, volume_db, pitch, team_id)

func play_team_audio_cue_locally(
	stream_path: String,
	volume_db: float,
	pitch: float,
	team_id: int
) -> void:
	if not is_valid_audio_request(stream_path, volume_db, pitch):
		return
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return
	var local_agent := _manager.call("get_local_agent", current_scene) as BaseAgent
	if not local_agent or int(local_agent.get("skirmish_team")) != team_id:
		return
	_play_stream_locally(stream_path, volume_db, pitch)

func request_audio_cue(stream_path: String, volume_db: float, pitch: float) -> void:
	if not _manager.call("is_networked") or not _manager.get_multiplayer().is_server():
		return
	if is_valid_audio_request(stream_path, volume_db, pitch):
		_manager.rpc("sync_audio_cue_rpc", stream_path, volume_db, pitch)

func receive_audio_cue(stream_path: String, volume_db: float, pitch: float) -> void:
	if _manager.call("is_networked"):
		var sender_id := _manager.get_multiplayer().get_remote_sender_id()
		if (
			(_manager.get_multiplayer().is_server() and sender_id != 0 and sender_id != 1)
			or (not _manager.get_multiplayer().is_server() and sender_id != 1)
		):
			return
	if is_valid_audio_request(stream_path, volume_db, pitch):
		_play_stream_locally(stream_path, volume_db, pitch)

func is_valid_audio_request(stream_path: String, volume_db: float, pitch: float) -> bool:
	return (
		stream_path.begins_with("res://assets/audio/")
		and (stream_path.ends_with(".ogg") or stream_path.ends_with(".wav") or stream_path.ends_with(".mp3"))
		and is_finite(volume_db)
		and volume_db >= -60.0 and volume_db <= 20.0
		and is_finite(pitch)
		and pitch >= 0.1 and pitch <= 3.0
	)

func _play_stream_locally(stream_path: String, volume_db: float, pitch: float) -> void:
	var stream := load(stream_path) as AudioStream
	if stream:
		AudioManager.play_global_stream(stream, volume_db, pitch)
