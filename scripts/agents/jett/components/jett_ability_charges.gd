extends Node

signal charge_state_changed(state: Dictionary)

@export_group("Ability Charges")
@export_range(0, 10, 1) var cloudburst_max_charges: int = 2
@export_range(0, 10, 1) var updraft_max_charges: int = 1
@export_range(0, 10, 1) var tailwind_max_charges: int = 1
@export_range(1, 20, 1) var tailwind_kills_per_charge: int = 2
@export_range(1, 20, 1) var ultimate_max_charges: int = 7

@export_group("Audio")
@export var ultimate_ready_audio: AudioCue

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var cloudburst_charges := 0
var updraft_charges := 0
var tailwind_charges := 0
var tailwind_kill_progress := 0
var ultimate_charges := 0
var ultimate_ready_audio_played := false

func _ready() -> void:
	cloudburst_charges = cloudburst_max_charges
	updraft_charges = updraft_max_charges
	tailwind_charges = tailwind_max_charges
	ultimate_charges = mini(ultimate_charges, ultimate_max_charges)
	call_deferred("_emit_charge_state")

func _emit_charge_state() -> void:
	if not is_inside_tree():
		return
	_update_ultimate_ready_audio()
	charge_state_changed.emit(get_charge_state())
func has_ability_charge(ability_name: String) -> bool:
	match ability_name:
		"Cloudburst":
			return cloudburst_charges > 0
		"Updraft":
			return updraft_charges > 0
		"Tailwind":
			return tailwind_charges > 0
		_:
			return false

func consume_ability_charge(ability_name: String) -> bool:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return false

	match ability_name:
		"Cloudburst":
			if cloudburst_charges <= 0:
				return false
			cloudburst_charges -= 1
		"Updraft":
			if updraft_charges <= 0:
				return false
			updraft_charges -= 1
		"Tailwind":
			if tailwind_charges <= 0:
				return false
			tailwind_charges -= 1
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
		"cloudburst": cloudburst_charges,
		"updraft": updraft_charges,
		"tailwind": tailwind_charges,
		"tailwind_kill_progress": tailwind_kill_progress,
		"ultimate": ultimate_charges,
	}

func reset_life_ability_charges() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	cloudburst_charges = cloudburst_max_charges
	updraft_charges = updraft_max_charges
	tailwind_charges = tailwind_max_charges
	tailwind_kill_progress = 0
	_sync_charge_state()

func get_training_refill_state() -> Dictionary:
	return {
		"cloudburst": cloudburst_max_charges,
		"updraft": updraft_max_charges,
		"tailwind": tailwind_max_charges,
		"tailwind_kill_progress": 0,
		"ultimate": ultimate_max_charges,
	}

func refill_all_charges_for_training(sync_network: bool = true) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	apply_training_refill_state(get_training_refill_state())
	if sync_network:
		_sync_charge_state()

func apply_training_refill_state(state: Dictionary) -> void:
	cloudburst_charges = clampi(int(state.get("cloudburst", 0)), 0, cloudburst_max_charges)
	updraft_charges = clampi(int(state.get("updraft", 0)), 0, updraft_max_charges)
	tailwind_charges = clampi(int(state.get("tailwind", 0)), 0, tailwind_max_charges)
	tailwind_kill_progress = clampi(int(state.get("tailwind_kill_progress", 0)), 0, tailwind_kills_per_charge - 1)
	ultimate_charges = clampi(int(state.get("ultimate", 0)), 0, ultimate_max_charges)
	_update_ultimate_ready_audio()
	charge_state_changed.emit(get_charge_state())

func grant_kill_charge() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if tailwind_charges < tailwind_max_charges:
		tailwind_kill_progress += 1
		if tailwind_kill_progress >= tailwind_kills_per_charge:
			tailwind_charges += 1
			tailwind_kill_progress = 0
	ultimate_charges = mini(ultimate_charges + 1, ultimate_max_charges)
	_sync_charge_state()

func _sync_charge_state() -> void:
	if multiplayer.has_multiplayer_peer():
		if not multiplayer.is_server():
			return
		_apply_charge_state(get_charge_state())
		sync_charge_state_rpc.rpc(
			cloudburst_charges,
			updraft_charges,
			tailwind_charges,
			tailwind_kill_progress,
			ultimate_charges
		)
		return
	_apply_charge_state(get_charge_state())

func _apply_charge_state(state: Dictionary) -> void:
	cloudburst_charges = int(state.get("cloudburst", cloudburst_charges))
	updraft_charges = int(state.get("updraft", updraft_charges))
	tailwind_charges = int(state.get("tailwind", tailwind_charges))
	tailwind_kill_progress = int(state.get("tailwind_kill_progress", tailwind_kill_progress))
	ultimate_charges = int(state.get("ultimate", ultimate_charges))
	_update_ultimate_ready_audio()
	charge_state_changed.emit(get_charge_state())

@rpc("any_peer", "call_remote", "reliable")
func sync_charge_state_rpc(
	new_cloudburst_charges: int,
	new_updraft_charges: int,
	new_tailwind_charges: int,
	new_tailwind_kill_progress: int,
	new_ultimate_charges: int
) -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if multiplayer.is_server():
			if sender_id != 0 and sender_id != multiplayer.get_unique_id():
				return
		elif sender_id != 1:
			return
	if (
		new_cloudburst_charges < 0
		or new_cloudburst_charges > cloudburst_max_charges
		or new_updraft_charges < 0
		or new_updraft_charges > updraft_max_charges
		or new_tailwind_charges < 0
		or new_tailwind_charges > tailwind_max_charges
		or new_tailwind_kill_progress < 0
		or new_tailwind_kill_progress >= tailwind_kills_per_charge
		or new_ultimate_charges < 0
		or new_ultimate_charges > ultimate_max_charges
	):
		push_warning("Rejected invalid Jett ability charge state.")
		return
	_apply_charge_state({
		"cloudburst": new_cloudburst_charges,
		"updraft": new_updraft_charges,
		"tailwind": new_tailwind_charges,
		"tailwind_kill_progress": new_tailwind_kill_progress,
		"ultimate": new_ultimate_charges,
	})

func _update_ultimate_ready_audio() -> void:
	if not has_ultimate_charge():
		ultimate_ready_audio_played = false
		return
	if ultimate_ready_audio_played or not agent.has_local_authority():
		return
	if ultimate_ready_audio and ultimate_ready_audio.stream:
		AudioManager.play_local_cue(ultimate_ready_audio, &"jett_ultimate_ready")
	ultimate_ready_audio_played = true
