extends RefCounted

var _agent: Node

func setup(agent: Node) -> void:
	_agent = agent

func reset_options() -> void:
	_agent.set("training_menu_open", false)
	_agent.set(
		"is_movement_locked",
		bool(_agent.get("shop_open")) or bool(_agent.get("agent_select_open"))
	)
	_agent.set("infinite_ammo_enabled", false)
	_agent.set("infinite_credits_enabled", false)
	_agent.set("invulnerable_enabled", false)
	if _agent.is_node_ready():
		(_agent.get("weapon_controller") as Node).call("set_infinite_ammo_enabled", false)
		(_agent.get("credits_component") as Node).call("set_infinite_credits_enabled", false)

func set_option(option: String, enabled: bool) -> void:
	if not is_valid_option(option):
		return
	var multiplayer_api := _agent.get_multiplayer()
	if multiplayer_api.has_multiplayer_peer() and not multiplayer_api.is_server():
		if _agent.is_multiplayer_authority():
			_agent.rpc_id(1, "request_training_option_rpc", option, enabled)
		return
	apply_option(option, enabled)
	if multiplayer_api.has_multiplayer_peer():
		_agent.rpc("sync_training_option_rpc", _agent.get_multiplayer_authority(), option, enabled)

func is_valid_option(option: String) -> bool:
	return option == "ammo" or option == "credits" or option == "invulnerable"

func apply_option(option: String, enabled: bool) -> void:
	match option:
		"ammo":
			set_ammo_state(enabled)
		"credits":
			set_credits_state(enabled)
		"invulnerable":
			_agent.set("invulnerable_enabled", enabled)

func request_charge_refill() -> void:
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer() or multiplayer_api.is_server():
		refill_charges()
	elif _agent.is_multiplayer_authority():
		_agent.rpc_id(1, "request_training_charge_refill_server")

func handle_charge_refill_request() -> void:
	var multiplayer_api := _agent.get_multiplayer()
	if (
		not multiplayer_api.is_server()
		or multiplayer_api.get_remote_sender_id() != _agent.get_multiplayer_authority()
	):
		return
	refill_charges()

func refill_charges() -> void:
	var ability_charges := _agent.get("ability_charges") as Node
	if not is_instance_valid(ability_charges):
		return
	var charge_state: Dictionary = {}
	if ability_charges.has_method("get_training_refill_state"):
		charge_state = ability_charges.call("get_training_refill_state")
	elif ability_charges.has_method("get_charge_state"):
		charge_state = ability_charges.call("get_charge_state")
	if charge_state.is_empty():
		return
	if ability_charges.has_method("refill_all_charges_for_training"):
		ability_charges.call("refill_all_charges_for_training", false)
		charge_state = ability_charges.call("get_charge_state")
	apply_charge_state(charge_state)
	if _agent.get_multiplayer().has_multiplayer_peer():
		_agent.rpc("sync_training_charge_state_rpc", _agent.get_multiplayer_authority(), charge_state)

func apply_charge_state(charge_state: Dictionary) -> void:
	var ability_charges := _agent.get("ability_charges") as Node
	if (
		is_instance_valid(ability_charges)
		and ability_charges.has_method("apply_training_refill_state")
	):
		ability_charges.call("apply_training_refill_state", charge_state)

func validate_charge_state(peer_id: int) -> bool:
	var multiplayer_api := _agent.get_multiplayer()
	return (
		peer_id == _agent.get_multiplayer_authority()
		and (
			not multiplayer_api.has_multiplayer_peer()
			or multiplayer_api.is_server()
			or multiplayer_api.get_remote_sender_id() == 1
		)
	)

func validate_option_request(option: String) -> bool:
	var multiplayer_api := _agent.get_multiplayer()
	return (
		multiplayer_api.is_server()
		and is_valid_option(option)
		and multiplayer_api.get_remote_sender_id() == _agent.get_multiplayer_authority()
	)

func validate_option_sync(peer_id: int, option: String) -> bool:
	var multiplayer_api := _agent.get_multiplayer()
	return (
		peer_id == _agent.get_multiplayer_authority()
		and is_valid_option(option)
		and (
			not multiplayer_api.has_multiplayer_peer()
			or multiplayer_api.is_server()
			or multiplayer_api.get_remote_sender_id() == 1
		)
	)

func set_ammo_state(enabled: bool) -> void:
	_agent.set("infinite_ammo_enabled", enabled)
	var weapon_controller := _agent.get("weapon_controller") as Node
	weapon_controller.call("set_infinite_ammo_enabled", enabled)
	if enabled:
		weapon_controller.call("_refill_infinite_ammo")

func set_credits_state(enabled: bool) -> void:
	_agent.set("infinite_credits_enabled", enabled)
	(_agent.get("credits_component") as Node).call("set_infinite_credits_enabled", enabled)

func set_menu_open(is_open: bool) -> void:
	_sync_menu_state(is_open)
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer():
		return
	if multiplayer_api.is_server():
		_agent.rpc("sync_training_menu_state_rpc", _agent.get_multiplayer_authority(), is_open)
	elif _agent.is_multiplayer_authority():
		_agent.rpc_id(1, "request_training_menu_state_rpc", is_open)

func validate_menu_request() -> bool:
	var multiplayer_api := _agent.get_multiplayer()
	return (
		multiplayer_api.is_server()
		and multiplayer_api.get_remote_sender_id() == _agent.get_multiplayer_authority()
	)

func validate_menu_sync(peer_id: int) -> bool:
	var multiplayer_api := _agent.get_multiplayer()
	return (
		peer_id == _agent.get_multiplayer_authority()
		and (
			not multiplayer_api.has_multiplayer_peer()
			or multiplayer_api.is_server()
			or multiplayer_api.get_remote_sender_id() == 1
		)
	)

func sync_menu_state(is_open: bool) -> void:
	_sync_menu_state(is_open)

func _sync_menu_state(is_open: bool) -> void:
	_agent.set("training_menu_open", is_open)
	_agent.set(
		"is_movement_locked",
		is_open or bool(_agent.get("shop_open")) or bool(_agent.get("agent_select_open"))
	)
	if is_open:
		_agent.set("velocity", Vector2.ZERO)
		(_agent.get("weapon_controller") as Node).call("suppress_shoot_until_released")
