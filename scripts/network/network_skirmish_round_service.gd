extends RefCounted

const FIRST_PREPARATION_SECONDS := 15.0
const PREPARATION_SECONDS := 5.0
const RECESS_SECONDS := 5.0
const ROUND_SECONDS := 90.0
const WINS_TO_FINISH_MATCH := 10

var _manager: Node
var _run_id := 0
var round_number := 0
var team_round_wins := [0, 0]
var is_preparation := false
var is_recess := false
var phase_duration := 0.0
var _initial_agent_selection_closed := false

func setup(manager: Node) -> void:
	_manager = manager

func start_match() -> void:
	stop()
	if _manager.call("is_networked") and not _manager.get_multiplayer().is_server():
		return
	_initial_agent_selection_closed = false
	team_round_wins = [0, 0]
	_run_id += 1
	_run_rounds(_run_id)

func stop() -> void:
	_run_id += 1
	round_number = 0
	is_preparation = false
	is_recess = false
	phase_duration = 0.0

func can_select_agent() -> bool:
	return round_number == 1 and is_preparation and not _initial_agent_selection_closed

func apply_state(
	new_round_number: int,
	preparing: bool,
	duration: float,
	phase_is_recess: bool = false
) -> void:
	round_number = new_round_number
	is_recess = phase_is_recess
	is_preparation = preparing and not phase_is_recess
	phase_duration = duration
	if new_round_number == 1 and not preparing:
		_initial_agent_selection_closed = true

func _run_rounds(run_id: int) -> void:
	var skirmish_service: Object = _manager.get("_skirmish_service")
	var next_round := 1
	var preparation_duration := FIRST_PREPARATION_SECONDS
	while run_id == _run_id and _manager.call("is_skirmish_mode"):
		skirmish_service.broadcast_round_state(next_round, true, preparation_duration, false)
		await _manager.get_tree().create_timer(preparation_duration).timeout
		if run_id != _run_id or not _manager.call("is_skirmish_mode"):
			return
		skirmish_service.broadcast_round_state(next_round, false, ROUND_SECONDS, false)
		var elapsed := 0.0
		while elapsed < ROUND_SECONDS:
			if run_id != _run_id or not _manager.call("is_skirmish_mode"):
				return
			if bool(skirmish_service.is_round_over()):
				break
			var step := minf(0.25, ROUND_SECONDS - elapsed)
			await _manager.get_tree().create_timer(step).timeout
			elapsed += step
		if run_id != _run_id or not _manager.call("is_skirmish_mode"):
			return
		var ended_by_elimination := bool(skirmish_service.is_round_over())
		var winner_team := int(skirmish_service.get_round_winner()) if ended_by_elimination else -1
		if winner_team >= 0 and winner_team < team_round_wins.size():
			team_round_wins[winner_team] += 1
		skirmish_service.broadcast_round_result(winner_team, team_round_wins.duplicate())
		if (
			team_round_wins[0] >= WINS_TO_FINISH_MATCH
			or team_round_wins[1] >= WINS_TO_FINISH_MATCH
		):
			skirmish_service.return_to_lobby()
			return
		if ended_by_elimination:
			skirmish_service.broadcast_round_state(next_round, true, RECESS_SECONDS, true)
			await _manager.get_tree().create_timer(RECESS_SECONDS).timeout
			if run_id != _run_id or not _manager.call("is_skirmish_mode"):
				return
		skirmish_service.reset_round()
		next_round += 1
		preparation_duration = PREPARATION_SECONDS
