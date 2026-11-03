extends Node

signal charge_state_changed(state: Dictionary)

@export_group("Ability Charges")
@export_range(0, 10, 1) var barrier_orb_max_charges := 1
@export_range(0, 10, 1) var slow_orb_max_charges := 2
@export_range(0, 10, 1) var healing_orb_max_charges := 1
@export_range(1.0, 120.0, 1.0, "suffix:s") var healing_orb_recharge_time := 45.0
@export_range(1, 20, 1) var ultimate_max_charges := 7

@export_group("Audio")
@export var ultimate_ready_audio: AudioCue

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var barrier_orb_charges := 0
var slow_orb_charges := 0
var healing_orb_charges := 0
var healing_orb_recharge_remaining := 0.0
var ultimate_charges := 0
var ultimate_ready_audio_played := false

func _ready() -> void:
	barrier_orb_charges = barrier_orb_max_charges
	slow_orb_charges = slow_orb_max_charges
	healing_orb_charges = healing_orb_max_charges
	call_deferred("_sync_charge_state")

func _process(delta: float) -> void:
	if healing_orb_recharge_remaining <= 0.0:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	healing_orb_recharge_remaining = maxf(healing_orb_recharge_remaining - delta, 0.0)
	if healing_orb_recharge_remaining <= 0.0 and healing_orb_charges < healing_orb_max_charges:
		healing_orb_charges += 1
		_sync_charge_state()

func has_ability_charge(ability_name: String) -> bool:
	match ability_name:
		"BarrierOrb":
			return barrier_orb_charges > 0
		"SlowOrb":
			return slow_orb_charges > 0
		"HealingOrb":
			return healing_orb_charges > 0
		_:
			return false

func consume_ability_charge(ability_name: String) -> bool:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return false
	match ability_name:
		"BarrierOrb":
			if barrier_orb_charges <= 0:
				return false
			barrier_orb_charges -= 1
		"SlowOrb":
			if slow_orb_charges <= 0:
				return false
			slow_orb_charges -= 1
		"HealingOrb":
			if healing_orb_charges <= 0:
				return false
			healing_orb_charges -= 1
			healing_orb_recharge_remaining = healing_orb_recharge_time
		_:
			return false
	_sync_charge_state()
	return true

func has_ultimate_charge() -> bool:
	return ultimate_charges >= ultimate_max_charges

func consume_ultimate_charge() -> bool:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return false
	if not has_ultimate_charge():
		return false
	ultimate_charges -= ultimate_max_charges
	_sync_charge_state()
	return true

func get_charge_state() -> Dictionary:
	return {
		"barrier_orb": barrier_orb_charges,
		"slow_orb": slow_orb_charges,
		"healing_orb": healing_orb_charges,
		"healing_orb_recharge_remaining": healing_orb_recharge_remaining,
		"ultimate": ultimate_charges,
	}

func reset_life_ability_charges() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	barrier_orb_charges = barrier_orb_max_charges
	slow_orb_charges = slow_orb_max_charges
	healing_orb_charges = healing_orb_max_charges
	healing_orb_recharge_remaining = 0.0
	_sync_charge_state()

func get_training_refill_state() -> Dictionary:
	return {
		"barrier_orb": barrier_orb_max_charges,
		"slow_orb": slow_orb_max_charges,
		"healing_orb": healing_orb_max_charges,
		"healing_orb_recharge_remaining": 0.0,
		"ultimate": ultimate_max_charges,
	}

func refill_all_charges_for_training(sync_network: bool = true) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	_apply_charge_state(get_training_refill_state())
	if sync_network:
		_sync_charge_state()

func grant_kill_charge() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	ultimate_charges = mini(ultimate_charges + 1, ultimate_max_charges)
	_sync_charge_state()

func apply_training_refill_state(state: Dictionary) -> void:
	_apply_charge_state(state)

func _sync_charge_state() -> void:
	var state := get_charge_state()
	_emit_charge_state()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_charge_state_rpc.rpc(state)

func _apply_charge_state(state: Dictionary) -> void:
	barrier_orb_charges = clampi(int(state.get("barrier_orb", barrier_orb_charges)), 0, barrier_orb_max_charges)
	slow_orb_charges = clampi(int(state.get("slow_orb", slow_orb_charges)), 0, slow_orb_max_charges)
	healing_orb_charges = clampi(int(state.get("healing_orb", healing_orb_charges)), 0, healing_orb_max_charges)
	healing_orb_recharge_remaining = clampf(
		float(state.get("healing_orb_recharge_remaining", healing_orb_recharge_remaining)),
		0.0,
		healing_orb_recharge_time
	)
	ultimate_charges = clampi(int(state.get("ultimate", ultimate_charges)), 0, ultimate_max_charges)
	_emit_charge_state()

func _emit_charge_state() -> void:
	_update_ultimate_ready_audio()
	charge_state_changed.emit(get_charge_state())

func _update_ultimate_ready_audio() -> void:
	if not has_ultimate_charge():
		ultimate_ready_audio_played = false
		return
	if ultimate_ready_audio_played or not agent or not agent.has_local_authority():
		return
	if ultimate_ready_audio and ultimate_ready_audio.stream:
		AudioManager.play_local_cue(ultimate_ready_audio, &"sage_ultimate_ready")
	ultimate_ready_audio_played = true

@rpc("any_peer", "call_remote", "reliable")
func sync_charge_state_rpc(state: Dictionary) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.get_remote_sender_id() != 1:
		return
	if not _is_valid_charge_state(state):
		return
	_apply_charge_state(state)

func _is_valid_charge_state(state: Dictionary) -> bool:
	return (
		int(state.get("barrier_orb", -1)) >= 0
		and int(state.get("barrier_orb", -1)) <= barrier_orb_max_charges
		and int(state.get("slow_orb", -1)) >= 0
		and int(state.get("slow_orb", -1)) <= slow_orb_max_charges
		and int(state.get("healing_orb", -1)) >= 0
		and int(state.get("healing_orb", -1)) <= healing_orb_max_charges
		and is_finite(float(state.get("healing_orb_recharge_remaining", -1.0)))
		and float(state.get("healing_orb_recharge_remaining", -1.0)) >= 0.0
		and float(state.get("healing_orb_recharge_remaining", -1.0)) <= healing_orb_recharge_time
		and int(state.get("ultimate", -1)) >= 0
		and int(state.get("ultimate", -1)) <= ultimate_max_charges
	)
