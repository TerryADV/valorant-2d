extends RefCounted

const DROPPED_WEAPON_SCENE: PackedScene = preload("res://scenes/weapons/dropped_weapon.tscn")
const DROPPABLE_WEAPON_PATHS: Array[String] = [
	"res://resources/weapons/classic.tres",
	"res://resources/weapons/vandal.tres",
	"res://resources/weapons/spectre.tres",
	"res://resources/weapons/judge.tres",
	"res://resources/weapons/operator.tres",
	"res://resources/weapons/odin.tres",
]
const SKIRMISH_CLASSIC: WeaponData = preload("res://resources/weapons/classic.tres")
const SKIRMISH_KNIFE: WeaponData = preload("res://resources/weapons/knife.tres")

var pending_weapon_slots: Dictionary = {}
var _drop_sequence := 0
var _manager: Node

func setup(manager: Node) -> void:
	_manager = manager

func get_player_weapon_slot(peer_id: int) -> int:
	var player := _manager.call("find_player", peer_id) as BaseAgent
	if player:
		return player.weapon_controller.current_weapon_slot
	return 0

func request_weapon_sync(
	peer_id: int,
	weapon_slot: int,
	sender_id: int,
	is_server: bool
) -> void:
	if not is_server or sender_id != peer_id:
		return
	if weapon_slot < 0 or weapon_slot > 2:
		return
	if not _manager.call("find_player", peer_id):
		return
	_manager.rpc("sync_player_weapon", peer_id, weapon_slot)

func request_dropped_weapon(
	peer_id: int,
	sender_id: int,
	weapon_path: String,
	drop_position: Vector2,
	direction: Vector2,
	dropped_ammo: int,
	dropped_reserve: int,
	is_server: bool
) -> void:
	if not is_server or sender_id != peer_id or not DROPPABLE_WEAPON_PATHS.has(weapon_path):
		return
	var player := _manager.call("find_player", peer_id) as BaseAgent
	var weapon := load(weapon_path) as WeaponData
	if not player or not weapon or weapon.is_melee:
		return
	_manager.rpc(
		"spawn_dropped_weapon",
		peer_id,
		weapon_path,
		drop_position,
		direction,
		clampi(dropped_ammo, 0, weapon.magazine_size),
		maxi(dropped_reserve, 0)
	)

func spawn_dropped_weapon(
	owner_peer_id: int,
	weapon_path: String,
	drop_position: Vector2,
	direction: Vector2,
	dropped_ammo: int,
	dropped_reserve: int
) -> void:
	if not DROPPABLE_WEAPON_PATHS.has(weapon_path):
		return
	var weapon := load(weapon_path) as WeaponData
	if not weapon or weapon.is_melee:
		return
	var current_scene := _manager.get_tree().current_scene
	if not current_scene:
		return
	_drop_sequence += 1
	var drop := DROPPED_WEAPON_SCENE.instantiate() as DroppedWeapon
	drop.name = "DroppedWeapon_%d_%d" % [owner_peer_id, _drop_sequence]
	drop.network_spawned = true
	current_scene.add_child(drop, true)
	drop.init_weapon(weapon, drop_position, direction, dropped_ammo, dropped_reserve)

func sync_dropped_weapons_to_peer(peer_id: int) -> void:
	for node in _manager.get_tree().get_nodes_in_group("dropped_weapons"):
		var drop := node as DroppedWeapon
		if not drop or not drop.network_spawned or not drop.weapon_data:
			continue
		if not DROPPABLE_WEAPON_PATHS.has(drop.weapon_data.resource_path):
			continue
		_manager.rpc_id(
			peer_id,
			"spawn_dropped_weapon",
			0,
			drop.weapon_data.resource_path,
			drop.global_position,
			Vector2.ZERO,
			drop.ammo_in_magazine,
			drop.reserve_ammo
		)

func sync_player_weapon(peer_id: int, weapon_slot: int) -> void:
	if weapon_slot < 0 or weapon_slot > 2:
		return
	var player := _manager.call("find_player", peer_id) as BaseAgent
	if player:
		apply_weapon_slot(player, weapon_slot)
	else:
		pending_weapon_slots[peer_id] = weapon_slot

func apply_weapon_slot(player: BaseAgent, weapon_slot: int) -> void:
	if not is_instance_valid(player):
		return
	var controller := player.get_node_or_null("Components/WeaponController")
	if not controller:
		push_error("WeaponController is missing on %s" % player.get_path())
		return
	if not controller.has_method("select_weapon_slot"):
		push_error("WeaponController has no select_weapon_slot() on %s" % player.get_path())
		return
	controller.call("select_weapon_slot", weapon_slot, false)

func apply_skirmish_starting_loadout(player: BaseAgent) -> void:
	if not is_instance_valid(player):
		return
	var controller: Node = player.weapon_controller
	var weapon_slots: Array = controller.weapon_slots
	var slot_ammo: Array = controller.slot_ammo
	var slot_reserve_ammo: Array = controller.slot_reserve_ammo
	var slot_initialized: Array = controller.slot_initialized
	if weapon_slots.size() < 3:
		weapon_slots.resize(3)
	weapon_slots[0] = null
	weapon_slots[1] = SKIRMISH_CLASSIC
	weapon_slots[2] = SKIRMISH_KNIFE
	slot_ammo[0] = 0
	slot_reserve_ammo[0] = 0
	slot_initialized[0] = false
	slot_ammo[1] = SKIRMISH_CLASSIC.magazine_size
	slot_reserve_ammo[1] = SKIRMISH_CLASSIC.reserve_ammo
	slot_initialized[1] = true
	slot_ammo[2] = 0
	slot_reserve_ammo[2] = 0
	slot_initialized[2] = true
	controller.call("select_weapon_slot", 1, false, false)

func apply_pending_weapon_slot(player: BaseAgent, peer_id: int) -> void:
	if not pending_weapon_slots.has(peer_id):
		return
	var weapon_slot := int(pending_weapon_slots[peer_id])
	pending_weapon_slots.erase(peer_id)
	apply_weapon_slot(player, weapon_slot)
