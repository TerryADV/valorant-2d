extends Node2D

@export var event_cues: Dictionary = {}
@export var sfx_bus: StringName = &"Master"

var local_cue_players: Dictionary = {}

func has_cue(cue_id: StringName) -> bool:
	var cue := _get_event_cue(cue_id)
	return cue != null and cue.stream != null

func play_world_cue(cue: AudioCue, world_position: Vector2) -> void:
	if not cue or not cue.stream:
		return
	if not world_position.is_finite():
		push_error("Cannot play spatial sound at a non-finite position.")
		return
	match cue.playback_type:
		AudioCue.PlaybackType.LOCAL:
			_play_nonpositional_cue(cue)
		AudioCue.PlaybackType.TEAM:
			_play_team_cue_on_allies(cue)
		AudioCue.PlaybackType.GLOBAL:
			_play_global_cue_on_all_peers(cue)
		AudioCue.PlaybackType.RANGE:
			_play_range_cue(cue, world_position)

	return

func _play_range_cue(cue: AudioCue, world_position: Vector2) -> void:
	var player := AudioStreamPlayer2D.new()
	player.stream = cue.stream
	player.global_position = world_position
	player.max_distance = cue.max_distance
	player.attenuation = cue.attenuation
	player.volume_db = cue.volume_db
	player.pitch_scale = _get_pitch(cue)
	player.bus = sfx_bus
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func play_global_cue(cue: AudioCue, world_position: Vector2 = Vector2.INF) -> void:
	if not cue or not cue.stream:
		return
	match cue.playback_type:
		AudioCue.PlaybackType.LOCAL:
			_play_nonpositional_cue(cue)
		AudioCue.PlaybackType.TEAM:
			_play_team_cue_on_allies(cue)
		AudioCue.PlaybackType.GLOBAL:
			_play_global_cue_on_all_peers(cue)
		AudioCue.PlaybackType.RANGE:
			if world_position.is_finite():
				_play_range_cue(cue, world_position)
			else:
				# Keep legacy calls without a source position non-spatial.
				_play_nonpositional_cue(cue)

	return

func play_global_stream(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if not stream:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.bus = sfx_bus
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _play_nonpositional_cue(cue: AudioCue) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = cue.stream
	player.volume_db = cue.volume_db
	player.pitch_scale = _get_pitch(cue)
	player.bus = sfx_bus
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _play_global_cue_on_all_peers(cue: AudioCue) -> void:
	if not cue.stream.resource_path.begins_with("res://assets/audio/"):
		push_warning("Networked global cues must use an audio asset under res://assets/audio/.")
		return
	if NetworkManager.is_networked():
		NetworkManager.play_audio_cue_on_all_peers(
			cue.stream.resource_path,
			cue.volume_db,
			_get_pitch(cue)
		)
	else:
		_play_nonpositional_cue(cue)

func _play_team_cue_on_allies(cue: AudioCue) -> void:
	if not cue.stream.resource_path.begins_with("res://assets/audio/"):
		push_warning("Networked team cues must use an audio asset under res://assets/audio/.")
		return
	if NetworkManager.is_networked():
		NetworkManager.play_audio_cue_on_team(
			cue.stream.resource_path,
			cue.volume_db,
			_get_pitch(cue)
		)
	else:
		_play_nonpositional_cue(cue)

func play_local_cue(
	cue: AudioCue,
	channel: StringName,
	world_position: Vector2 = Vector2.INF
) -> void:
	if not cue or not cue.stream:
		return
	if cue.playback_type == AudioCue.PlaybackType.GLOBAL:
		_play_global_cue_on_all_peers(cue)
		return
	if cue.playback_type == AudioCue.PlaybackType.TEAM:
		_play_team_cue_on_allies(cue)
		return
	if cue.playback_type == AudioCue.PlaybackType.RANGE and world_position.is_finite():
		_play_range_cue(cue, world_position)
		return
	stop_local_cue(channel)

	var player := AudioStreamPlayer.new()
	player.stream = cue.stream
	player.volume_db = cue.volume_db
	player.pitch_scale = _get_pitch(cue)
	player.bus = sfx_bus
	add_child(player)
	local_cue_players[channel] = player
	player.finished.connect(_on_local_cue_finished.bind(channel, player))
	player.play()

func play_local_loop_cue(cue: AudioCue, channel: StringName) -> void:
	if not cue or not cue.stream:
		return
	stop_local_cue(channel)

	var loop_stream := cue.stream.duplicate()
	if not loop_stream is AudioStreamOggVorbis:
		push_error("Looping local audio cues require an Ogg Vorbis stream.")
		return
	(loop_stream as AudioStreamOggVorbis).loop = true

	var player := AudioStreamPlayer.new()
	player.stream = loop_stream
	player.volume_db = cue.volume_db
	player.pitch_scale = _get_pitch(cue)
	player.bus = sfx_bus
	add_child(player)
	local_cue_players[channel] = player
	player.finished.connect(_on_local_cue_finished.bind(channel, player))
	player.play()

func stop_local_cue(channel: StringName) -> void:
	var player := local_cue_players.get(channel) as AudioStreamPlayer
	if not player:
		local_cue_players.erase(channel)
		return
	local_cue_players.erase(channel)
	player.stop()
	player.queue_free()

func _on_local_cue_finished(channel: StringName, player: AudioStreamPlayer) -> void:
	if local_cue_players.get(channel) == player:
		local_cue_players.erase(channel)
	player.queue_free()

func play_event_world(cue_id: StringName, world_position: Vector2) -> void:
	var cue := _get_event_cue(cue_id)
	if cue:
		play_world_cue(cue, world_position)

func play_event_global(cue_id: StringName) -> void:
	var cue := _get_event_cue(cue_id)
	if cue:
		play_global_cue(cue)

func play_event_global_local(cue_id: StringName) -> void:
	var cue := _get_event_cue(cue_id)
	if cue and cue.stream:
		_play_nonpositional_cue(cue)

func _get_event_cue(cue_id: StringName) -> AudioCue:
	return event_cues.get(String(cue_id)) as AudioCue

func _get_pitch(cue: AudioCue) -> float:
	return randf_range(minf(cue.pitch_min, cue.pitch_max), maxf(cue.pitch_min, cue.pitch_max))
