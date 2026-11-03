class_name BaseAgentCore
extends CharacterBody2D

enum CoreDifficulty { EASY, MEDIUM, HARD }

const CreditsComponentScript = preload("res://scripts/components/credits_component.gd")
const AgentLoadoutControllerScript = preload("res://scripts/entities/agent_loadout_controller.gd")
const AgentProjectileControllerScript = preload("res://scripts/entities/agent_projectile_controller.gd")
const AgentAudioControllerScript = preload("res://scripts/entities/agent_audio_controller.gd")
const AgentLifecycleControllerScript = preload("res://scripts/entities/agent_lifecycle_controller.gd")
const AgentDamageControllerScript = preload("res://scripts/entities/agent_damage_controller.gd")
const AgentCombatStatsScript = preload("res://scripts/entities/agent_combat_stats.gd")
const AgentHealingStateScript = preload("res://scripts/entities/agent_healing_state.gd")
const AgentTrainingControllerScript = preload("res://scripts/entities/agent_training_controller.gd")
const TeamVisibilityControllerScript = preload("res://scripts/components/team_visibility_controller.gd")
const SkirmishTeamContextScript = preload("res://scripts/systems/skirmish_team_context.gd")
const SpectatorControllerScript = preload("res://scripts/components/spectator_controller.gd")

signal health_changed(current_health: float, max_health: float)
signal shield_changed(current_shield: float, max_shield: float)
signal damage_taken(amount: float)
signal damage_direction_received(direction: Vector2)
signal agent_data_changed(data: AgentData)
signal died
signal weapon_changed(weapon: WeaponData, slot: int)
signal death_reported(killer: Node, victim: Node)
@warning_ignore("unused_signal")
signal kill_streak_reset_requested
@warning_ignore("unused_signal")
signal respawned

@export var run_speed: float = 60.0
@export_range(0.0, 1.0, 0.01) var walk_speed_ratio: float = 0.6
@export var acceleration: float = 2500.0
@export var friction: float = 2200.0

@export_group("Agent")
@export var agent_data: AgentData
@export var is_ai_dummy := false
@export var difficulty: int = CoreDifficulty.HARD
@export var shooting_range: float = 450.0
@export_range(50.0, 1000.0, 10.0) var vision_range: float = 260.0
@export_range(0.0, 20.0, 0.5) var shooting_spread_degrees: float = 0.0
@export_range(0.1, 3.0, 0.1) var aim_time: float = 0.8
@export_range(0.1, 2.0, 0.05) var footstep_interval: float = 0.38
@export_range(0.1, 5.0, 0.1) var min_wait_time: float = 0.5
@export_range(0.1, 5.0, 0.1) var max_wait_time: float = 1.5
var is_in_match := false
var current_weapon: WeaponData
var agent_index := 0
var target_actor: Node2D
var last_known_target_position := Vector2.ZERO
var has_last_known_target_position := false
var aim_target: Node2D
var display_name := "Agent"
var has_wander_target := false
var slow_zone_sources: Dictionary = {}
var wait_time_remaining := 0.0
var shoot_cooldown := 0.0
var recoil_degrees := 0.0
var reload_time_remaining := 0.0
var aim_time_remaining := 0.0
var footstep_time_remaining := 0.0
var ammo_in_magazine := 0
var is_aiming := false
var navigation_error_reported := false
var network_weapon_synced := false
var network_transform_buffer: Array[Dictionary] = []
var network_interpolation_delay := 0.1
var initial_collision_layer := 0
var initial_collision_mask := 0
var flash_time_remaining := 0.0
var flashed_indicator: Sprite2D
var _dummy_controller
var navigation_agent: NavigationAgent2D
var network_sync_time_remaining := 0.0
var health_sync_time_remaining := 0.0
var is_dead := false
var is_applying_network_health_state := false
var is_match_preparing := false
var death_intercepted_by_ability := false
var shop_open := false
var purchased_shield_items: Dictionary = {}
var active_shield_item_id := ""
var agent_select_open := false
var training_menu_open := false
var infinite_ammo_enabled := false
var is_lobby_locked := false
var last_attacker: Node
var last_attacker_weapon_name: String = ""
var combat_damage_received_by_actor: Dictionary = {}
var combat_damage_received_weapon_by_actor: Dictionary = {}
var combat_damage_dealt_to_actor: Dictionary = {}
var combat_damage_dealt_weapon_by_actor: Dictionary = {}
var combat_damage_received_by_life: Dictionary = {}
var combat_damage_received_weapon_by_life: Dictionary = {}
var combat_damage_dealt_to_actor_by_life: Dictionary = {}
var combat_life_id := 0
var last_attacker_life_id := -1
var damage_source_for_current_hit: Node2D
var damage_indicator_tween: Tween
var damage_flash_tween: Tween
var damage_indicator_radius: float
var infinite_credits_enabled := false
var invulnerable_enabled := false
var incoming_healing_statuses: Dictionary = {}
var last_reload_sfx_request_msec := -200
var last_footstep_request_msec := -250
var last_melee_sfx_request_msec := -200
var active_ability_name := ""
var is_movement_locked := false
var skirmish_team := -1
var held_ability_equip_tweens: Dictionary = {}
var spawn_protection_time_remaining := 0.0
var spawn_protection_tween: Tween
var visuals_base_alpha := 1.0
var body_sprite_base_modulate := Color.WHITE
var resurrection_gradient_base_modulate := Color.WHITE
var last_combat_activity_msec := -1
var sage_healing_visual_effects: Dictionary = {}
var sage_healing_preview_effects: Dictionary = {}
var sage_resurrection_visual_effects: Dictionary = {}

@onready var visuals: Node2D = $Visuals
@onready var agent_circle: AgentCircleVisual = $Visuals/AgentCircle
@onready var body_sprite: Sprite2D = $Visuals/BodySprite
@onready var weapon_sprite: Sprite2D = $Visuals/BodySprite/WeaponPivot/WeaponSprite
@onready var damage_indicator: Sprite2D = $DamageIndicator
@onready var health_component: HealthComponent = $Components/HealthComponent
@onready var weapon_controller = $Components/WeaponController
@onready var movement_controller: Node = $Components/MovementController
@onready var camera_controller: Node = $Components/CameraController
@onready var interaction_controller: Node = $Components/InteractionController
@onready var player_camera: Camera2D = $Camera2D
@onready var credits_component: CreditsComponentScript = $Components/CreditsComponent
var ability_charges: Node
var loaded_agent_nodes: Array[Node] = []
var _loadout_controller
var _projectile_controller
var _audio_controller
var _lifecycle_controller
var _damage_controller
var _team_visibility_controller
var _combat_stats
var _healing_state
var _spectator_controller
var _training_controller

func _ready() -> void:
	_ensure_controllers()
	_spectator_controller = SpectatorControllerScript.new()
	_spectator_controller.setup(self)
	if not agent_data:
		push_error("BaseAgent requires an AgentData resource.")
		return
	add_to_group("combat_actors")
	_configure_agent_loadout()
	if is_ai_dummy:
		call("_setup_dummy_controllers")
		navigation_agent = NavigationAgent2D.new()
		navigation_agent.name = "NavigationAgent2D"
		add_child(navigation_agent)
		initial_collision_layer = collision_layer
		initial_collision_mask = collision_mask
		is_in_match = visible
		display_name = "Dummy %d" % absi(int(call("get_deathmatch_id")))
		flashed_indicator = get_node_or_null("Visuals/Flashed") as Sprite2D
	_team_visibility_controller = TeamVisibilityControllerScript.new()
	_team_visibility_controller.setup(self, SkirmishTeamContextScript.new())
	apply_agent_data()
	agent_data_changed.emit(agent_data)
	if NetworkManager.is_deathmatch_mode() or NetworkManager.is_skirmish_mode():
		credits_component.set_credits(99999)

	health_component.health_changed.connect(Callable(self, "_on_health_changed"))
	health_component.damage_taken.connect(Callable(self, "_on_damage_taken"))
	health_component.died.connect(Callable(self, "_on_died"))
	damage_indicator_radius = damage_indicator.position.length()
	visuals_base_alpha = visuals.modulate.a
	if body_sprite:
		body_sprite_base_modulate = body_sprite.modulate
	var resurrection_gradient := get_node_or_null("Visuals/BodySprite/ResurrectionGradient") as Sprite2D
	if resurrection_gradient:
		resurrection_gradient_base_modulate = resurrection_gradient.modulate
	damage_direction_received.connect(Callable(self, "_show_damage_indicator"))
	weapon_controller.weapon_changed.connect(Callable(self, "_on_weapon_changed"))
	configure_network_visuals(
		not is_ai_dummy and (not multiplayer.has_multiplayer_peer() or is_multiplayer_authority())
	)
	if is_ai_dummy:
		_dummy_controller.call("setup", self)

func _setup_controllers() -> void:
	_combat_stats = AgentCombatStatsScript.new()
	_combat_stats.setup(self)
	_healing_state = AgentHealingStateScript.new()
	_healing_state.setup(self)
	_training_controller = AgentTrainingControllerScript.new()
	_training_controller.setup(self)
	_loadout_controller = AgentLoadoutControllerScript.new()
	_loadout_controller.setup(self)
	_projectile_controller = AgentProjectileControllerScript.new()
	_projectile_controller.setup(self)
	_audio_controller = AgentAudioControllerScript.new()
	_audio_controller.setup(self)
	_lifecycle_controller = AgentLifecycleControllerScript.new()
	_lifecycle_controller.setup(self)
	_damage_controller = AgentDamageControllerScript.new()
	_damage_controller.setup(self)

func _input(event: InputEvent) -> void:
	if NetworkManager.is_match_loading():
		return
	if _spectator_controller and has_local_authority() and is_dead:
		_spectator_controller.process_input(event)
		return
	if (
		is_ai_dummy
		or not agent_data
		or not has_local_authority()
		or is_dead
		or (is_match_preparing and not NetworkManager.is_skirmish_preparation())
		or shop_open
	):
		return
	var slot_count := mini(
		agent_data.ability_component_ids.size(),
		agent_data.ability_input_actions.size()
	)
	for index in range(slot_count):
		var input_action := agent_data.ability_input_actions[index]
		if not event.is_action(input_action):
			continue
		if event is InputEventKey and (event as InputEventKey).echo:
			return
		if NetworkManager.is_skirmish_preparation():
			if event.is_action_pressed(input_action):
				set_active_ability(agent_data.ability_component_ids[index])
				get_viewport().set_input_as_handled()
				return
			continue
		var ability_path := (
			agent_data.ability_component_paths[index]
			if index < agent_data.ability_component_paths.size()
			else NodePath()
		)
		var ability := get_node_or_null(ability_path)
		if ability and ability.has_method("handle_ability_input"):
			if bool(ability.call("handle_ability_input", event, input_action)):
				get_viewport().set_input_as_handled()
				return
		if not event.is_action_pressed(input_action):
			continue
		set_active_ability(agent_data.ability_component_ids[index])
		get_viewport().set_input_as_handled()
		return

func configure_agent(data: Variant) -> void:
	if not data is Resource:
		push_error("Cannot configure BaseAgent with an invalid agent resource.")
		return
	_ensure_controllers()
	_reset_training_options()
	if _loadout_controller.configure_agent(data):
		agent_data_changed.emit(agent_data)

func _reset_training_options() -> void:
	_training_controller.call("reset_options")

func _configure_agent_loadout() -> void:
	_loadout_controller.configure_loadout()

func _ensure_controllers() -> void:
	if _loadout_controller:
		return
	_setup_controllers()

func configure_network_visuals(is_local_player: bool) -> void:
	player_camera.enabled = is_local_player
	if is_local_player:
		player_camera.make_current()
	visuals.call("set_lights_visible", is_local_player)
	if _team_visibility_controller:
		_team_visibility_controller.process(0.0)

func focus_local_camera() -> void:
	if not player_camera:
		return
	player_camera.enabled = true
	player_camera.make_current()
	player_camera.reset_smoothing()
	player_camera.force_update_scroll()

func has_local_authority() -> bool:
	if is_ai_dummy or is_lobby_locked:
		return false
	var multiplayer_api := get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer():
		return true
	var network_peer := multiplayer_api.multiplayer_peer
	if (
		not network_peer
		or network_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED
	):
		return false
	return is_multiplayer_authority()

func set_lobby_locked(locked: bool) -> void:
	is_lobby_locked = locked
	if locked:
		velocity = Vector2.ZERO
		shop_open = false
		weapon_controller.aiming = false
		weapon_controller.aim_level = 0
		_apply_active_ability("")

func validate_visual_configuration() -> void:
	var body_visible := false
	if body_sprite:
		body_visible = body_sprite.is_visible_in_tree()

	if not body_sprite or not body_sprite.texture:
		push_warning("VisualDebug: the agent has no visible body texture at %s." % get_path())
	elif not is_visible_in_tree() or not body_visible:
		push_warning("VisualDebug: the agent visibility configuration is incomplete at %s." % get_path())

func set_shop_open(is_open: bool) -> void:
	shop_open = is_open
	if shop_open:
		set_active_ability("")
		weapon_controller.aiming = false
		weapon_controller.aim_level = 0

func set_active_ability(ability_name: String) -> void:
	_ensure_controllers()
	_loadout_controller.set_active_ability(ability_name)

func has_ability_charge(ability_name: String) -> bool:
	_ensure_controllers()
	return _loadout_controller.has_ability_charge(ability_name)

func consume_ability_charge(ability_name: String) -> bool:
	_ensure_controllers()
	return _loadout_controller.consume_ability_charge(ability_name)

func has_ultimate_charge() -> bool:
	_ensure_controllers()
	return _loadout_controller.has_ultimate_charge()

func consume_ultimate_charge() -> bool:
	_ensure_controllers()
	return _loadout_controller.consume_ultimate_charge()

func get_ability_charge_state() -> Dictionary:
	_ensure_controllers()
	return _loadout_controller.get_ability_charge_state()

func has_ability_component(ability_name: String) -> bool:
	_ensure_controllers()
	return _loadout_controller.has_ability_component(ability_name)

func animate_held_ability_equip(sprite: Sprite2D, base_scale: Vector2, equipped: bool) -> void:
	_ensure_controllers()
	_loadout_controller.animate_held_ability_equip(sprite, base_scale, equipped)

func _apply_active_ability(ability_name: String) -> void:
	_ensure_controllers()
	_loadout_controller.apply_active_ability(ability_name)

func reset_skirmish_round_abilities() -> void:
	if not NetworkManager.is_skirmish_mode():
		return
	_ensure_controllers()
	_loadout_controller.reset_for_new_round()

func apply_agent_data() -> void:
	_ensure_controllers()
	_loadout_controller.apply_agent_data()

func _physics_process(delta: float) -> void:
	if NetworkManager.is_match_loading():
		return
	_process_network_transform_interpolation()
	if is_ai_dummy:
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			return
		if is_movement_locked:
			velocity = Vector2.ZERO
		else:
			_dummy_controller.call_movement("process_authoritative_movement", [delta])
		if multiplayer.has_multiplayer_peer():
			health_sync_time_remaining -= delta
			if health_sync_time_remaining <= 0.0:
				health_sync_time_remaining = 0.1
				rpc(
					"sync_dummy_health",
					int(call("get_deathmatch_id")), health_component.current_health,
					health_component.current_shield, health_component.max_health,
					health_component.max_shield
				)
			network_sync_time_remaining -= delta
			if network_sync_time_remaining <= 0.0:
				network_sync_time_remaining = 1.0 / 30.0
				var weapon_index := int(_dummy_controller.call("get_weapon_index", current_weapon))
				rpc(
					"sync_dummy_state",
					global_position,
					velocity,
					visuals.rotation,
					weapon_index
				)
			return
		return
	if is_lobby_locked:
		velocity = Vector2.ZERO
		return
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	if is_dead:
		return
	if is_movement_locked:
		velocity = Vector2.ZERO
	else:
		movement_controller.call("process_movement", delta)
	visuals.call("process_visuals")
	if multiplayer.has_multiplayer_peer():
		NetworkManager.sync_player_transform_rpc.rpc(
			get_multiplayer_authority(), global_position, velocity, visuals.rotation
		)
	if is_movement_locked:
		return
	camera_controller.call("process_camera_look_ahead")
	weapon_controller.process_weapon(delta)
	interaction_controller.call("process_interaction")

func apply_network_transform(
	world_position: Vector2, movement_velocity: Vector2, visual_rotation: float
) -> void:
	if is_multiplayer_authority():
		return
	var received_at := Time.get_ticks_usec() / 1000000.0
	if not network_transform_buffer.is_empty():
		var previous: Dictionary = network_transform_buffer.back()
		if received_at - float(previous["time"]) > 0.25:
			network_transform_buffer.clear()
	network_transform_buffer.append({
			"time": received_at,
			"position": world_position,
			"velocity": movement_velocity,
			"rotation": visual_rotation,
		})
	while network_transform_buffer.size() > 8:
		network_transform_buffer.pop_front()
	velocity = movement_velocity

func _process_network_transform_interpolation() -> void:
	if network_transform_buffer.is_empty():
		return
	var multiplayer_api := get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer() or is_multiplayer_authority():
		return
	var render_time := Time.get_ticks_usec() / 1000000.0 - network_interpolation_delay
	while network_transform_buffer.size() > 2 and float(network_transform_buffer[1]["time"]) <= render_time:
		network_transform_buffer.pop_front()
	var first: Dictionary = network_transform_buffer[0]
	var first_time := float(first["time"])
	var first_position: Vector2 = first["position"]
	var first_rotation := float(first["rotation"])
	if network_transform_buffer.size() >= 2:
		var second: Dictionary = network_transform_buffer[1]
		var second_time := float(second["time"])
		var span := maxf(second_time - first_time, 0.001)
		var weight := clampf((render_time - first_time) / span, 0.0, 1.0)
		global_position = first_position.lerp(second["position"], weight)
		visuals.rotation = lerp_angle(first_rotation, float(second["rotation"]), weight)
		return
	var extrapolation := clampf(render_time - first_time, 0.0, 0.05)
	global_position = first_position + velocity * extrapolation
	visuals.rotation = first_rotation

func _emit_health_and_shield_changed(
	current_health: float,
	max_health: float,
	current_shield: float,
	max_shield: float
) -> void:
	health_changed.emit(current_health, max_health)
	shield_changed.emit(current_shield, max_shield)

func _emit_damage_taken(amount: float) -> void:
	damage_taken.emit(amount)

func _emit_died_signal() -> void:
	died.emit()

func _emit_death_signals(killer: Node) -> void:
	died.emit()
	death_reported.emit(killer, self)

func _on_health_changed(current_health: float, max_health: float) -> void:
	_damage_controller.on_health_changed(current_health, max_health)

func _on_damage_taken(amount: float) -> void:
	_damage_controller.on_damage_taken(amount)

func _on_died() -> void:
	_damage_controller.on_died()

func _on_weapon_changed(weapon: WeaponData, slot: int) -> void:
	weapon_changed.emit(weapon, slot)
	visuals.queue_redraw()

