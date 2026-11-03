extends Node

const HEALING_DURATION := 8.0
const HEALING_AMOUNT := 50.0
const HEALING_PER_SECOND := HEALING_AMOUNT / HEALING_DURATION
const DAMAGE_INTERRUPTION_DURATION := 2.0

@export var healing_audio: AudioCue

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var next_effect_id := 0
var healing_effects: Dictionary = {}
var healing_audio_playing := false
var interruption_remaining := 0.0

func _ready() -> void:
	if not agent.damage_taken.is_connected(_on_agent_damaged):
		agent.damage_taken.connect(_on_agent_damaged)

func apply_healing_effect(ability_name: String) -> void:
	if not agent or agent.is_dead:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	next_effect_id += 1
	var effect_id := next_effect_id
	_register_healing_effect(effect_id, ability_name, HEALING_DURATION)
	var owner_peer_id := agent.get_multiplayer_authority()
	if multiplayer.has_multiplayer_peer() and owner_peer_id != 1:
		show_healing_effect_rpc.rpc_id(
			owner_peer_id,
			effect_id,
			ability_name,
			HEALING_DURATION
		)

func _process(delta: float) -> void:
	if healing_effects.is_empty():
		return
	if NetworkManager.is_skirmish_mode() and NetworkManager.is_skirmish_preparation():
		_clear_healing_effects()
		return
	if agent.is_dead:
		_clear_healing_effects()
		return

	var paused_delta := minf(delta, interruption_remaining)
	interruption_remaining = maxf(interruption_remaining - delta, 0.0)
	var healing_amount := 0.0
	var expired_effects: Array[int] = []
	for effect_id in healing_effects.keys():
		var effect: Dictionary = healing_effects[effect_id]
		var remaining: float = effect["remaining"]
		var effect_delta := minf(delta, remaining)
		var effect_active_delta := maxf(effect_delta - paused_delta, 0.0)
		healing_amount += HEALING_PER_SECOND * effect_active_delta
		remaining = maxf(remaining - effect_delta, 0.0)
		effect["remaining"] = remaining
		healing_effects[effect_id] = effect
		if remaining <= 0.0:
			expired_effects.append(int(effect_id))

	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		agent.heal(healing_amount)
	_update_healing_state_bars()
	for effect_id in expired_effects:
		_remove_healing_effect(effect_id, true)

func _update_healing_state_bars() -> void:
	if not agent.has_local_authority():
		return
	var hud := _get_game_hud()
	if not hud:
		return
	for effect_id in healing_effects.keys():
		var effect: Dictionary = healing_effects[effect_id]
		hud.update_healing_state(int(effect_id), float(effect["remaining"]))

func _on_agent_damaged(_amount: float) -> void:
	if not healing_effects.is_empty():
		interruption_remaining = DAMAGE_INTERRUPTION_DURATION
		if (
			multiplayer.has_multiplayer_peer()
			and multiplayer.is_server()
			and agent.get_multiplayer_authority() != 1
		):
			sync_healing_interruption_rpc.rpc_id(
				agent.get_multiplayer_authority(),
				DAMAGE_INTERRUPTION_DURATION
			)

@rpc("any_peer", "call_remote", "reliable")
func sync_healing_interruption_rpc(duration: float) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.get_remote_sender_id() != 1:
		return
	if agent.get_multiplayer_authority() != multiplayer.get_unique_id():
		return
	if not is_finite(duration) or duration <= 0.0:
		push_error("Healing interruption duration must be finite and positive.")
		return
	interruption_remaining = maxf(interruption_remaining, duration)

@rpc("any_peer", "call_remote", "reliable")
func show_healing_effect_rpc(
	effect_id: int,
	ability_name: String,
	duration: float
) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.get_remote_sender_id() != 1:
		return
	if agent.get_multiplayer_authority() != multiplayer.get_unique_id():
		return
	if not _is_valid_healing_effect(effect_id, ability_name, duration):
		return
	_register_healing_effect(effect_id, ability_name, duration)

@rpc("any_peer", "call_remote", "reliable")
func remove_healing_effect_rpc(effect_id: int) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.get_remote_sender_id() != 1:
		return
	if agent.get_multiplayer_authority() != multiplayer.get_unique_id():
		return
	_remove_healing_effect(effect_id, false)

func _register_healing_effect(
	effect_id: int,
	ability_name: String,
	duration: float
) -> void:
	if not _is_valid_healing_effect(effect_id, ability_name, duration):
		return
	healing_effects[effect_id] = {
		"ability_name": ability_name,
		"duration": duration,
		"remaining": duration,
	}
	if agent.has_local_authority():
		var hud := _get_game_hud()
		if hud:
			hud.add_healing_state(effect_id, ability_name, duration)
		else:
			push_warning("Phoenix healing started, but no GameHud was found.")
		_update_healing_audio()

func _remove_healing_effect(effect_id: int, notify_owner: bool) -> void:
	if not healing_effects.erase(effect_id):
		return
	if agent.has_local_authority():
		var hud := _get_game_hud()
		if hud:
			hud.remove_healing_state(effect_id)
		_update_healing_audio()
	elif (
		notify_owner
		and multiplayer.has_multiplayer_peer()
		and multiplayer.is_server()
	):
		var owner_peer_id := agent.get_multiplayer_authority()
		if owner_peer_id != multiplayer.get_unique_id():
			remove_healing_effect_rpc.rpc_id(owner_peer_id, effect_id)

func _clear_healing_effects() -> void:
	for effect_id in healing_effects.keys():
		_remove_healing_effect(int(effect_id), true)

func _update_healing_audio() -> void:
	if not agent.has_local_authority():
		return
	if healing_effects.is_empty():
		if healing_audio_playing:
			AudioManager.stop_local_cue(&"phoenix_healing")
			healing_audio_playing = false
	elif not healing_audio_playing and healing_audio and healing_audio.stream:
		AudioManager.play_local_loop_cue(healing_audio, &"phoenix_healing")
		healing_audio_playing = true

func _get_game_hud() -> GameHud:
	var current_scene := get_tree().current_scene
	if not current_scene:
		return null
	var hud := current_scene.get_node_or_null("HUD") as GameHud
	if not hud:
		hud = current_scene.find_child("GameHud", true, false) as GameHud
	return hud

func _is_valid_healing_effect(
	effect_id: int,
	ability_name: String,
	duration: float
) -> bool:
	return (
		effect_id > 0
		and ability_name in ["Blaze", "Hot Hands"]
		and is_finite(duration)
		and duration > 0.0
	)
