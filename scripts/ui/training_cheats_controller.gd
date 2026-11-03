extends RefCounted

var _hud: GameHud
var _infinite_abilities_enabled := false
var _refill_request_timer := 0.0

func setup(hud: GameHud) -> void:
	_hud = hud

func set_infinite_abilities_enabled(enabled: bool) -> void:
	_infinite_abilities_enabled = enabled
	_refill_request_timer = 0.0
	if enabled:
		refill_ability_charges()

func process(delta: float) -> void:
	if not _infinite_abilities_enabled:
		return
	_refill_request_timer -= delta
	if _refill_request_timer <= 0.0:
		_refill_request_timer = 0.25
		refill_ability_charges()

func bind_player() -> void:
	if _infinite_abilities_enabled:
		refill_ability_charges()

func refill_ability_charges() -> void:
	var player: BaseAgent = _hud.player
	if not player or not player.has_local_authority():
		return
	var charges: Node = player.ability_charges
	if not charges:
		return
	if _hud.multiplayer.has_multiplayer_peer() and not _hud.multiplayer.is_server():
		player.request_training_charge_refill_rpc()
		return
	if charges.has_method("refill_all_charges_for_training"):
		charges.call("refill_all_charges_for_training")
