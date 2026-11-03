extends RefCounted

const WEAPON_PATHS: Dictionary = {
	"classic": "res://resources/weapons/classic.tres",
	"vandal": "res://resources/weapons/vandal.tres",
	"judge": "res://resources/weapons/judge.tres",
	"spectre": "res://resources/weapons/spectre.tres",
	"odin": "res://resources/weapons/odin.tres",
	"operator": "res://resources/weapons/operator.tres",
}
const ITEM_PRICES: Dictionary = {
	"classic": 0,
	"vandal": 2900,
	"judge": 1850,
	"spectre": 1600,
	"odin": 3200,
	"operator": 4700,
	"shield_small": 400,
	"shield_regen": 400,
	"shield_large": 1000,
}
var _manager: Node

func setup(manager: Node) -> void:
	_manager = manager

func has_item(item_id: String) -> bool:
	return ITEM_PRICES.has(item_id)

func get_item_price(item_id: String) -> int:
	return int(ITEM_PRICES.get(item_id, -1))

func purchase_item(agent: BaseAgent, item_id: String) -> bool:
	if (
		not is_instance_valid(agent)
		or not has_item(item_id)
		or (
			_manager.call("is_skirmish_mode")
			and not _manager.call("is_skirmish_preparation")
		)
	):
		return false
	if _manager.call("is_networked") and not _manager.get_multiplayer().is_server():
		_manager.rpc_id(1, "request_shop_purchase", item_id)
		return true
	return _process_purchase(agent, item_id)

func handle_purchase_request(item_id: String, sender_id: int) -> void:
	if not _manager.get_multiplayer().is_server():
		return
	if _manager.call("is_skirmish_mode") and not _manager.call("is_skirmish_preparation"):
		_reject_purchase(sender_id, item_id)
		return
	if not has_item(item_id):
		_reject_purchase(sender_id, item_id)
		return
	var agent := _manager.call("find_player", sender_id) as BaseAgent
	if not agent or agent.get_multiplayer_authority() != sender_id:
		_reject_purchase(sender_id, item_id)
		return
	if _manager.call("is_skirmish_mode") and not _manager.call("is_skirmish_preparation"):
		_reject_purchase(sender_id, item_id)
		return
	if not _process_purchase(agent, item_id):
		_reject_purchase(sender_id, item_id)

func _reject_purchase(peer_id: int, item_id: String) -> void:
	_manager.rpc_id(peer_id, "notify_shop_purchase_rejected", item_id)

func _process_purchase(agent: BaseAgent, item_id: String) -> bool:
	if _manager.call("is_skirmish_mode") and not _manager.call("is_skirmish_preparation"):
		return false
	var purchase := prepare_purchase(
		agent,
		item_id,
		_manager.call("is_deathmatch_mode") or _manager.call("is_skirmish_mode")
	)
	if purchase.is_empty():
		return false
	if _manager.call("is_networked"):
		_manager.rpc(
			"sync_shop_purchase",
			agent.get_multiplayer_authority(),
			item_id,
			purchase["credits"],
			purchase["shield"]
		)
	else:
		apply_purchase(agent, item_id, purchase["credits"], purchase["shield"])
	return true

func sync_purchase(peer_id: int, item_id: String, credits: int, shield: float) -> void:
	if not has_item(item_id):
		return
	var agent := _manager.call("find_player", peer_id) as BaseAgent
	if not agent:
		push_error("Cannot apply shop purchase: player %d is missing." % peer_id)
		return
	apply_purchase(agent, item_id, credits, shield)

func prepare_purchase(agent: BaseAgent, item_id: String, deathmatch: bool) -> Dictionary:
	if not is_instance_valid(agent) or agent.is_dead or not has_item(item_id):
		return {}

	var credits = agent.credits_component
	var new_shield: float = agent.get_current_shield()
	if WEAPON_PATHS.has(item_id):
		var weapon := load(WEAPON_PATHS[item_id]) as WeaponData
		if not weapon:
			push_error("Could not load shop weapon: %s" % item_id)
			return {}
		var weapon_slot: int = agent.weapon_controller.get_weapon_slot(weapon)
		if agent.weapon_controller.weapon_slots[weapon_slot] == weapon:
			return {}
	elif item_id in ["shield_small", "shield_regen", "shield_large"]:
		var shield_offer: float = 50.0 if item_id == "shield_large" else 25.0
		new_shield = minf(shield_offer, agent.get_max_shield())
		var already_active := agent.active_shield_item_id == item_id
		var has_full_regenerative_reserve := (
			item_id == "shield_regen"
			and agent.health_component.regenerative_shield_reserve
			>= HealthComponent.REGENERATIVE_RESERVE_CAPACITY
		)
		if (
			already_active
			and is_equal_approx(new_shield, agent.get_current_shield())
			and (item_id != "shield_regen" or has_full_regenerative_reserve)
		):
			return {}
	else:
		return {}

	var remaining_credits: int = credits.current_credits
	if not deathmatch:
		if not credits.try_spend(int(ITEM_PRICES[item_id])):
			return {}
		remaining_credits = credits.current_credits
	return {"credits": remaining_credits, "shield": new_shield}

func apply_purchase(agent: BaseAgent, item_id: String, credits: int, shield: float) -> void:
	agent.credits_component.set_credits(credits)
	if WEAPON_PATHS.has(item_id):
		var weapon := load(WEAPON_PATHS[item_id]) as WeaponData
		if not weapon:
			push_error("Could not load shop weapon: %s" % item_id)
			return
		agent.weapon_controller.apply_shop_weapon(weapon)
	else:
		agent.active_shield_item_id = item_id
		if item_id == "shield_regen":
			agent.health_component.activate_regenerative_shield()
		else:
			agent.health_component.deactivate_regenerative_shield()
			agent.health_component.set_current_shield(shield)
		agent.purchased_shield_items[item_id] = true
