extends RefCounted

const HEALING_AUDIO_STREAM: AudioStream = preload("res://assets/audio/sfx/healing.ogg")
const HEALING_AUDIO_CHANNEL: StringName = &"agent_healing"

var _agent: Node
var healing_status_ids: Dictionary = {}
var healing_audio_cue: AudioCue
var healing_audio_playing := false

var incoming_statuses: Dictionary:
	get:
		return _agent.get("incoming_healing_statuses") as Dictionary
var healing_visual_effects: Dictionary:
	get:
		return _agent.get("sage_healing_visual_effects") as Dictionary
var healing_preview_effects: Dictionary:
	get:
		return _agent.get("sage_healing_preview_effects") as Dictionary
var resurrection_visual_effects: Dictionary:
	get:
		return _agent.get("sage_resurrection_visual_effects") as Dictionary

func setup(agent: Node) -> void:
	_agent = agent
	healing_audio_cue = AudioCue.new()
	healing_audio_cue.playback_type = AudioCue.PlaybackType.LOCAL
	healing_audio_cue.stream = HEALING_AUDIO_STREAM

func add_healing_status(effect_id: int, duration: float) -> void:
	if not _is_server_sender() or not _agent.has_local_authority():
		return
	if effect_id <= 0 or not is_finite(duration) or duration <= 0.0:
		return
	var hud := _get_local_game_hud()
	if hud:
		hud.add_healing_state(effect_id, "Healing Orb", duration)
	healing_status_ids[effect_id] = true
	_update_healing_audio()

func update_healing_status(effect_id: int, remaining: float) -> void:
	if not _is_server_sender() or not _agent.has_local_authority():
		return
	if effect_id <= 0 or not is_finite(remaining) or remaining < 0.0:
		return
	var hud := _get_local_game_hud()
	if hud:
		hud.update_healing_state(effect_id, remaining)

func remove_healing_status(effect_id: int) -> void:
	if not _is_server_sender() or not _agent.has_local_authority() or effect_id <= 0:
		return
	var hud := _get_local_game_hud()
	if hud:
		hud.remove_healing_state(effect_id)
	healing_status_ids.erase(effect_id)
	_update_healing_audio()

func clear_healing_statuses() -> void:
	incoming_statuses.clear()
	healing_status_ids.clear()
	_update_healing_audio()
	var hud := _get_local_game_hud()
	if hud:
		hud.clear_healing_states()

func set_local_healing_audio_status(effect_id: int, active: bool) -> void:
	if effect_id <= 0 or not _agent.has_local_authority():
		return
	if active:
		healing_status_ids[effect_id] = true
	else:
		healing_status_ids.erase(effect_id)
	_update_healing_audio()

func _update_healing_audio() -> void:
	if not _agent or not _agent.has_local_authority():
		return
	var handled_by_agent_audio := _agent.has_node("Components/JettAudio")
	var should_play := not healing_status_ids.is_empty() and not handled_by_agent_audio
	if should_play and not healing_audio_playing:
		AudioManager.play_local_loop_cue(healing_audio_cue, HEALING_AUDIO_CHANNEL)
		healing_audio_playing = true
	elif not should_play and healing_audio_playing:
		AudioManager.stop_local_cue(HEALING_AUDIO_CHANNEL)
		healing_audio_playing = false

func set_healing_visual(effect_id: int, active: bool) -> void:
	if effect_id <= 0:
		return
	_set_effect(healing_visual_effects, effect_id, active)
	_update_ability_indicator()

func set_healing_preview(effect_id: int, active: bool) -> void:
	if effect_id <= 0:
		return
	_set_effect(healing_preview_effects, effect_id, active)
	_update_ability_indicator()

func set_resurrection_indicator(effect_id: int, active: bool) -> void:
	if effect_id <= 0:
		return
	_set_effect(resurrection_visual_effects, effect_id, active)
	_update_ability_indicator()

func sync_healing_visual(effect_id: int, active: bool) -> void:
	if not _is_server_sender():
		return
	set_healing_visual(effect_id, active)

func sync_incoming_status(status_id: int, active: bool) -> void:
	var multiplayer_api := _agent.get_multiplayer()
	if (
		not multiplayer_api.has_multiplayer_peer()
		or multiplayer_api.get_remote_sender_id() != 1
		or not _agent.is_multiplayer_authority()
		or status_id <= 0
	):
		return
	_set_effect(incoming_statuses, status_id, active)

func _set_effect(effect_map: Dictionary, effect_id: int, active: bool) -> void:
	if active:
		effect_map[effect_id] = true
	else:
		effect_map.erase(effect_id)

func _is_server_sender() -> bool:
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer():
		return true
	var sender_id := multiplayer_api.get_remote_sender_id()
	return (multiplayer_api.is_server() and sender_id in [0, 1]) or (
		not multiplayer_api.is_server() and sender_id == 1
	)

func _get_local_game_hud() -> GameHud:
	var current_scene := _agent.get_tree().current_scene
	if not current_scene:
		return null
	var hud := current_scene.get_node_or_null("HUD") as GameHud
	if not hud:
		hud = current_scene.find_child("GameHud", true, false) as GameHud
	return hud

func _update_ability_indicator() -> void:
	var indicator := _agent.get_node_or_null("Visuals/AbilityIndicator") as Sprite2D
	if not indicator:
		return
	var has_resurrection := not resurrection_visual_effects.is_empty()
	var has_healing := (
		not healing_visual_effects.is_empty()
		or not healing_preview_effects.is_empty()
	)
	if has_resurrection:
		indicator.texture = preload("res://assets/sprites/ui/abilities/sage/resurrection.png")
	else:
		indicator.texture = preload("res://assets/sprites/ui/abilities/sage/healing_orb.png")
	indicator.visible = has_healing or has_resurrection
