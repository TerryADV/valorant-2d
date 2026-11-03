extends Node

const MATCH_LOADING_SERVICE_SCRIPT := preload("res://scripts/network/network_match_loading_service.gd")
const MATCH_PREPARATION_SERVICE_SCRIPT := preload("res://scripts/network/network_match_preparation_service.gd")
const COMBAT_REPORT_SERVICE_SCRIPT := preload("res://scripts/network/network_combat_report_service.gd")
const WEAPON_SERVICE_SCRIPT := preload("res://scripts/network/network_weapon_service.gd")
const PLAYER_SERVICE_SCRIPT := preload("res://scripts/network/network_player_service.gd")
const AGENT_SELECTION_SERVICE_SCRIPT := preload("res://scripts/network/network_agent_selection_service.gd")

var _manager: Node
var _preparation_service: RefCounted = MATCH_PREPARATION_SERVICE_SCRIPT.new()
var _loading_service: Node = MATCH_LOADING_SERVICE_SCRIPT.new()
var _combat_report_service: RefCounted = COMBAT_REPORT_SERVICE_SCRIPT.new()
var _weapon_service: RefCounted = WEAPON_SERVICE_SCRIPT.new()
var _player_service: RefCounted = PLAYER_SERVICE_SCRIPT.new()
var _agent_selection_service: RefCounted = AGENT_SELECTION_SERVICE_SCRIPT.new()

func setup(manager: Node) -> void:
	_manager = manager
	_preparation_service.setup(manager)
	_combat_report_service.setup(manager)
	_weapon_service.setup(manager)
	_player_service.setup(manager)
	_agent_selection_service.setup(manager)
	_loading_service.name = "MatchLoadingService"
	_loading_service.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_loading_service)
	_loading_service.setup(manager)

func get_loading_service() -> Node:
	return _loading_service

func get_combat_report_service() -> RefCounted:
	return _combat_report_service

func get_weapon_service() -> RefCounted:
	return _weapon_service

func get_player_service() -> RefCounted:
	return _player_service

func get_agent_selection_service() -> RefCounted:
	return _agent_selection_service

func get_preparation_service() -> RefCounted:
	return _preparation_service

func get_loading_state() -> bool:
	return _loading_service.get_loading_state()

func is_loading_screen_visible() -> bool:
	return _loading_service.is_loading_screen_visible()
