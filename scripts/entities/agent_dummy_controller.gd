extends RefCounted

const AVAILABLE_WEAPONS: Array[WeaponData] = [
	preload("res://resources/weapons/vandal.tres"),
	preload("res://resources/weapons/classic.tres"),
	preload("res://resources/weapons/knife.tres"),
	preload("res://resources/weapons/spectre.tres"),
	preload("res://resources/weapons/operator.tres"),
	preload("res://resources/weapons/judge.tres"),
	preload("res://resources/weapons/odin.tres"),
]
const AVAILABLE_AGENTS: Array[AgentData] = [
	preload("res://resources/agents/phoenix.tres"),
	preload("res://resources/agents/jett.tres"),
	preload("res://resources/agents/sage.tres"),
]
const MovementScript = preload("res://scripts/entities/dummy_movement_controller.gd")
const CombatScript = preload("res://scripts/entities/dummy_combat_controller.gd")
const WeaponScript = preload("res://scripts/entities/dummy_weapon_controller.gd")
const LifecycleScript = preload("res://scripts/entities/dummy_lifecycle_controller.gd")

var _agent: Node
var _movement: RefCounted
var _combat: RefCounted
var _weapon: RefCounted
var _lifecycle: RefCounted

func setup(agent: Node) -> void:
	_agent = agent
	_movement = MovementScript.new()
	_combat = CombatScript.new()
	_weapon = WeaponScript.new()
	_lifecycle = LifecycleScript.new()
	_weapon.call("setup", _agent, AVAILABLE_WEAPONS)
	_movement.call("setup", _agent, AVAILABLE_WEAPONS)
	_combat.call("setup", _agent, AVAILABLE_WEAPONS)
	_lifecycle.call("setup", _agent, AVAILABLE_WEAPONS, AVAILABLE_AGENTS)
	var weapons: Array[WeaponData] = AVAILABLE_WEAPONS
	var selected_weapon := weapons[randi_range(0, weapons.size() - 1)]
	_agent.set("current_weapon", selected_weapon)
	_weapon.call("apply_weapon", selected_weapon)
	_agent.set("ammo_in_magazine", selected_weapon.magazine_size if not selected_weapon.is_melee else 0)

func call_movement(method: StringName, args: Array = []) -> Variant:
	return _movement.callv(method, args)

func call_combat(method: StringName, args: Array = []) -> Variant:
	return _combat.callv(method, args)

func call_weapon(method: StringName, args: Array = []) -> Variant:
	return _weapon.callv(method, args)

func call_lifecycle(method: StringName, args: Array = []) -> Variant:
	return _lifecycle.callv(method, args)

func get_agent_count() -> int:
	return AVAILABLE_AGENTS.size()

func get_agent_data(index: int) -> AgentData:
	if index < 0 or index >= AVAILABLE_AGENTS.size():
		return null
	return AVAILABLE_AGENTS[index]

func apply_agent_appearance(index: int) -> void:
	var selected_agent := get_agent_data(index)
	if selected_agent and selected_agent != _agent.get("agent_data"):
		if _agent.has_method("configure_agent"):
			_agent.call("configure_agent", selected_agent)

func get_weapon_index(weapon: WeaponData) -> int:
	return AVAILABLE_WEAPONS.find(weapon)

func reset_aim() -> void:
	_agent.set("is_aiming", false)
	_agent.set("aim_target", null)
	_agent.set("aim_time_remaining", 0.0)

func is_server_rpc_sender() -> bool:
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer():
		return true
	var sender_id := multiplayer_api.get_remote_sender_id()
	return (multiplayer_api.is_server() and sender_id in [0, 1]) or (
		not multiplayer_api.is_server() and sender_id == 1
	)

func update_ability_indicator() -> void:
	var healing_state := _agent.get("_healing_state") as RefCounted
	if healing_state:
		healing_state.call("_update_ability_indicator")
