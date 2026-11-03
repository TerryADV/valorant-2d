extends Node

signal charges_changed(
	blaze_charges: int,
	hot_hands_charges: int,
	curveball_charges: int,
	curveball_kill_progress: int,
	ultimate_charges: int
)
signal charge_state_changed(state: Dictionary)

const BLAZE_MAX_CHARGES := 1
const HOT_HANDS_MAX_CHARGES := 1
const CURVEBALL_MAX_CHARGES := 2
const CURVEBALL_KILLS_PER_CHARGE := 2
const ULTIMATE_MAX_CHARGES := 7

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var blaze_charges := BLAZE_MAX_CHARGES
var hot_hands_charges := HOT_HANDS_MAX_CHARGES
var curveball_charges := CURVEBALL_MAX_CHARGES
var curveball_kill_progress := 0
var ultimate_charges := 0
var ultimate_ready_audio_played := false

@export var ultimate_ready_audio: AudioCue

func has_ability_charge(ability_name: String) -> bool:
	match ability_name:
		"Blaze":
			return blaze_charges > 0
		"HotHands":
			return hot_hands_charges > 0
		"Curveball":
			return curveball_charges > 0
		_:
			push_error("Unknown Phoenix ability charge: %s" % ability_name)
			return false

func consume_ability_charge(ability_name: String) -> bool:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return false

	match ability_name:
		"Blaze":
			if blaze_charges == 0:
				return false
			blaze_charges -= 1
		"HotHands":
			if hot_hands_charges == 0:
				return false
			hot_hands_charges -= 1
		"Curveball":
			if curveball_charges == 0:
				return false
			curveball_charges -= 1
		_:
			push_error("Unknown Phoenix ability charge: %s" % ability_name)
			return false

	_sync_charges()
	return true

func has_ultimate_charge() -> bool:
	return ultimate_charges >= ULTIMATE_MAX_CHARGES

func get_charge_state() -> Dictionary:
	return {
		"blaze": blaze_charges,
		"hot_hands": hot_hands_charges,
		"curveball": curveball_charges,
		"curveball_kill_progress": curveball_kill_progress,
		"ultimate": ultimate_charges,
	}

func consume_ultimate_charge() -> bool:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return false
	if not has_ultimate_charge():
		return false

	ultimate_charges -= ULTIMATE_MAX_CHARGES
	_sync_charges()
	return true

func reset_life_ability_charges() -> void:
	blaze_charges = BLAZE_MAX_CHARGES
	hot_hands_charges = HOT_HANDS_MAX_CHARGES
	curveball_charges = CURVEBALL_MAX_CHARGES
	curveball_kill_progress = 0
	_sync_charges()

func get_training_refill_state() -> Dictionary:
	return {
		"blaze": BLAZE_MAX_CHARGES,
		"hot_hands": HOT_HANDS_MAX_CHARGES,
		"curveball": CURVEBALL_MAX_CHARGES,
		"curveball_kill_progress": 0,
		"ultimate": ULTIMATE_MAX_CHARGES,
	}

func refill_all_charges_for_training(sync_network: bool = true) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	apply_training_refill_state(get_training_refill_state())
	if sync_network:
		_sync_charges()

func apply_training_refill_state(state: Dictionary) -> void:
	blaze_charges = clampi(int(state.get("blaze", 0)), 0, BLAZE_MAX_CHARGES)
	hot_hands_charges = clampi(int(state.get("hot_hands", 0)), 0, HOT_HANDS_MAX_CHARGES)
	curveball_charges = clampi(int(state.get("curveball", 0)), 0, CURVEBALL_MAX_CHARGES)
	curveball_kill_progress = clampi(int(state.get("curveball_kill_progress", 0)), 0, CURVEBALL_KILLS_PER_CHARGE - 1)
	ultimate_charges = clampi(int(state.get("ultimate", 0)), 0, ULTIMATE_MAX_CHARGES)
	_emit_charges_changed()

func grant_kill_charge() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	ultimate_charges = mini(ultimate_charges + 1, ULTIMATE_MAX_CHARGES)
	if curveball_charges < CURVEBALL_MAX_CHARGES:
		curveball_kill_progress += 1
		if curveball_kill_progress >= CURVEBALL_KILLS_PER_CHARGE:
			curveball_charges += 1
			curveball_kill_progress = 0
	_sync_charges()

func _sync_charges() -> void:
	if multiplayer.has_multiplayer_peer():
		sync_charges_rpc.rpc(
			agent.get_multiplayer_authority(),
			blaze_charges,
			hot_hands_charges,
			curveball_charges,
			curveball_kill_progress,
			ultimate_charges
		)
	else:
		_emit_charges_changed()

@rpc("any_peer", "call_local", "reliable")
func sync_charges_rpc(
	owner_peer_id: int,
	new_blaze_charges: int,
	new_hot_hands_charges: int,
	new_curveball_charges: int,
	new_curveball_kill_progress: int,
	new_ultimate_charges: int
) -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if multiplayer.is_server():
			if sender_id != 0 and sender_id != 1:
				return
		elif sender_id != 1:
			return
	if (
		owner_peer_id != agent.get_multiplayer_authority()
		or new_blaze_charges < 0
		or new_blaze_charges > BLAZE_MAX_CHARGES
		or new_hot_hands_charges < 0
		or new_hot_hands_charges > HOT_HANDS_MAX_CHARGES
		or new_curveball_charges < 0
		or new_curveball_charges > CURVEBALL_MAX_CHARGES
		or new_curveball_kill_progress < 0
		or new_curveball_kill_progress >= CURVEBALL_KILLS_PER_CHARGE
		or new_ultimate_charges < 0
		or new_ultimate_charges > ULTIMATE_MAX_CHARGES
	):
		return

	blaze_charges = new_blaze_charges
	hot_hands_charges = new_hot_hands_charges
	curveball_charges = new_curveball_charges
	curveball_kill_progress = new_curveball_kill_progress
	ultimate_charges = new_ultimate_charges
	_emit_charges_changed()

func _emit_charges_changed() -> void:
	var ultimate_is_ready := has_ultimate_charge()
	if (
		ultimate_is_ready
		and not ultimate_ready_audio_played
		and agent
		and agent.has_local_authority()
	):
		AudioManager.play_local_cue(ultimate_ready_audio, &"phoenix_ultimate_ready")
	ultimate_ready_audio_played = ultimate_is_ready
	charge_state_changed.emit(get_charge_state())
	charges_changed.emit(
		blaze_charges,
		hot_hands_charges,
		curveball_charges,
		curveball_kill_progress,
		ultimate_charges
	)
