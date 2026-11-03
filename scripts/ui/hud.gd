class_name GameHud
extends CanvasLayer

const DEATHMATCH_DISPLAY_SCRIPT := preload("res://scripts/ui/hud_deathmatch_display.gd")
var _deathmatch_display = DEATHMATCH_DISPLAY_SCRIPT.new()
const ABILITY_DISPLAY_SCRIPT := preload("res://scripts/ui/hud_ability_display.gd")
var _ability_display = ABILITY_DISPLAY_SCRIPT.new()
const SKIRMISH_DISPLAY_SCRIPT := preload("res://scripts/ui/hud_skirmish_display.gd")
var _skirmish_display = SKIRMISH_DISPLAY_SCRIPT.new()
const TRAINING_CHEATS_CONTROLLER_SCRIPT := preload("res://scripts/ui/training_cheats_controller.gd")
var _training_cheats_controller = TRAINING_CHEATS_CONTROLLER_SCRIPT.new()
const LOW_STATUS_DISPLAY_SCRIPT := preload("res://scripts/ui/hud_low_status_controller.gd")
var _low_status_display = LOW_STATUS_DISPLAY_SCRIPT.new()
const KILL_STREAK_DISPLAY_SCRIPT := preload("res://scripts/ui/hud_kill_streak_display.gd")
var _kill_streak_display = KILL_STREAK_DISPLAY_SCRIPT.new()
const REGENERATIVE_SHIELD_DISPLAY_SCRIPT := preload("res://scripts/ui/hud_regenerative_shield_display.gd")
var _regenerative_shield_display = REGENERATIVE_SHIELD_DISPLAY_SCRIPT.new()

@export var player_path: NodePath

@onready var health_label: Label = $Control/Main/Bottom/HealthContainer/Health/Label
@onready var shield_icon: TextureRect = $Control/Main/Bottom/HealthContainer/Shield/Shield1
@onready var shield_label: Label = $Control/Main/Bottom/HealthContainer/Shield/Label
@onready var ammo_label: Label = $Control/Main/Bottom/BulletContainer/Bullets
@onready var reserve_ammo_label: Label = $Control/Main/Bottom/BulletContainer/Ammunition
@onready var health_decor: TextureRect = $Control/Main/Bottom/HealthContainer/Decor
@onready var bullet_decor: TextureRect = $Control/Main/Bottom/BulletContainer/Decor
@onready var kill_streak_base: TextureRect = $Control/Main/Kill
@onready var kill_streak_count: TextureRect = $Control/Main/Kill/Count
@onready var ability_timer: TextureProgressBar = get_node(
	"Control/Main/Bottom/Ability&Bar/AbilityTimer"
) as TextureProgressBar
@onready var ability_timer_name: Label = get_node(
	"Control/Main/Bottom/Ability&Bar/AbilityTimer/Name"
) as Label
@onready var main_container: Control = $Control/Main
@onready var cheats_panel: PanelContainer = $Control/CheatsPanel
@onready var infinite_abilities_button: CheckButton = $Control/CheatsPanel/Margin/VBox/InfiniteAbilities
@onready var infinite_ammo_button: CheckButton = $Control/CheatsPanel/Margin/VBox/InfiniteAmmo
@onready var infinite_credits_button: CheckButton = $Control/CheatsPanel/Margin/VBox/InfiniteCredits
@onready var invulnerability_button: CheckButton = $Control/CheatsPanel/Margin/VBox/Invulnerability
@onready var alert_label: Label = get_node_or_null("Control/Alert") as Label
@onready var flashes_container: Control = $Control/States
@onready var flash_overlay: ColorRect = $Control/States/Background
@onready var flash_effect: Sprite2D = $Control/States/Flash
@onready var healing_overlay: TextureRect = $Control/States/Healing
@onready var jett_dash_overlay: Control = $Control/States/Jett
@onready var sage_resurrection_overlay: Control = $Control/States/Sage
@onready var healing_states: VBoxContainer = $Control/Main/Bottom/States/Good
@onready var healing_state_template: TextureRect = get_node(
	"Control/Main/Bottom/States/Good/1"
) as TextureRect
@onready var bad_states: VBoxContainer = $Control/Main/Bottom/States/Bad
@onready var bad_state_template: TextureRect = get_node(
	"Control/Main/Bottom/States/Bad/1"
) as TextureRect
@onready var ally_agent_icon: TextureRect = $Control/Main/Top/Normal/AllysContainer/AgentContainer/HBoxContainer/Player1
@onready var ally_health_progress: TextureProgressBar = $Control/Main/Top/Normal/AllysContainer/AgentContainer/HBoxContainer/Player1/Health
@onready var ally_ultimate_inactive: TextureRect = $Control/Main/Top/Normal/AllysContainer/AgentContainer/HBoxContainer/Player1/UltimateInactive
@onready var ally_ultimate_active: TextureRect = $Control/Main/Top/Normal/AllysContainer/AgentContainer/HBoxContainer/Player1/UltimateActive
@onready var normal_container: Control = $Control/Main/Top/Normal
@onready var deathmatch_container: Control = $Control/Main/Top/Deathmatch
@onready var kills_container: Control = $Control/Main/Top/KillsContainer
@onready var scoreboard_container: Control = $Control/Scoreboard
@onready var deathmatch_scoreboard: Control = $Control/Scoreboard/Deathmatch
@onready var skirmish_scoreboard: Control = $Control/Scoreboard/Skirmish
@onready var agent_select_panel: Control = get_node("Control/Select Agent") as Control
@onready var phoenix_select_button: Button = get_node("Control/Select Agent/Phoenix") as Button
@onready var jett_select_button: Button = get_node("Control/Select Agent/Jett") as Button
@onready var sage_select_button: Button = get_node("Control/Select Agent/Sage") as Button
@onready var combat_report: Control = get_node("Control/Combat Report") as Control
@onready var combat_report_outgoing: Label = get_node("Control/Combat Report/Report/Container/Outgoing") as Label
@onready var combat_report_outgoing_caption: Label = get_node("Control/Combat Report/Report/Container/Outgoing/Label") as Label
@onready var combat_report_incoming: Label = get_node("Control/Combat Report/Report/Container/Incoming") as Label
@onready var combat_report_incoming_caption: Label = get_node("Control/Combat Report/Report/Container/Incoming/Label") as Label
@onready var combat_report_outgoing_header: Label = get_node("Control/Combat Report/Tittles/Label") as Label
@onready var combat_report_incoming_header: Label = get_node("Control/Combat Report/Tittles/Label3") as Label
@onready var combat_report_agent: TextureRect = get_node("Control/Combat Report/Report/Container/Agent") as TextureRect
@onready var combat_report_weapon: TextureRect = get_node("Control/Combat Report/Report/Container/Weapon") as TextureRect
@onready var combat_report_rows_container: VBoxContainer = get_node("Control/Combat Report/Report") as VBoxContainer
@onready var combat_report_killer: Label = get_node("Control/Combat Report/Murdered/Kill") as Label
@onready var combat_report_killer_icon: TextureRect = get_node("Control/Combat Report/Murdered/Icon") as TextureRect
@onready var combat_report_murdered: Control = get_node("Control/Combat Report/Murdered") as Control
@onready var scoreboard_rows_container: VBoxContainer = $Control/Scoreboard/Deathmatch/VBoxContainer
@onready var scoreboard_row_template: Control = $Control/Scoreboard/Deathmatch/VBoxContainer/Player
@onready var kills_list: VBoxContainer = $Control/Main/Top/KillsContainer/VBoxContainer
@onready var kill_entry_template: Control = $Control/Main/Top/KillsContainer/VBoxContainer/Control
@onready var first_deathmatch_players: HBoxContainer = $Control/Main/Top/Deathmatch/FirstPlayers/PlayersContainer/HBoxContainer
@onready var last_deathmatch_players: HBoxContainer = $Control/Main/Top/Deathmatch/LastPlayers/PlayersContainer/HBoxContainer
@onready var weapon_slots: Array[Control] = [
	$Control/Main/Guns/Gun1,
	$Control/Main/Guns/Gun2,
	$Control/Main/Guns/Knife,
]
@onready var weapon_slot_icons: Array[TextureRect] = [
	$Control/Main/Guns/Gun1/Image/TextureRect,
	$Control/Main/Guns/Gun2/Image/TextureRect,
	$Control/Main/Guns/Knife/Image/TextureRect,
]
@onready var weapon_slot_names: Array[Label] = [
	$Control/Main/Guns/Gun1/Name,
	$Control/Main/Guns/Gun2/Name,
	$Control/Main/Guns/Knife/Name,
]

var player: BaseAgent
var _combat_report_agent_icons: Array[TextureRect] = []
var _combat_report_rows: Array[Control] = []
var _skirmish_combat_outcomes: Dictionary = {}
var _skirmish_round_stats: Dictionary = {}
var _skirmish_death_report_pending := false
var weapon_controller
var blade_storm_equipped := false
var is_deathmatch_mode := false
var is_skirmish_mode := false
var _skirmish_initial_selection_shown := false
var flash_tween: Tween
var flash_effect_tween: Tween
var healing_state_entries: Dictionary = {}
var slow_state_entry: TextureRect
var alert_tween: Tween
var ability_timer_tween: Tween
var flash_default_color := Color.WHITE
var ally_health_default_tint := Color.WHITE
var flash_effect_base_scale := Vector2.ONE
@export var deathmatch_kill_target: int = 30
var deathmatch_scores: Dictionary:
	get:
		return _deathmatch_display.deathmatch_scores
	set(value):
		_deathmatch_display.deathmatch_scores = value
var deathmatch_deaths: Dictionary:
	get:
		return _deathmatch_display.deathmatch_deaths
	set(value):
		_deathmatch_display.deathmatch_deaths = value

const SHIELD_EMPTY_TEXTURE: Texture2D = preload("res://assets/sprites/ui/main/shield1off.png")

const SHIELD_TEXTURE: Texture2D = preload("res://assets/sprites/ui/main/shield1.png")
const REGENERATIVE_SHIELD_TEXTURE: Texture2D = preload("res://assets/sprites/ui/main/shield_ren.png")
const REGENERATIVE_SHIELD_EMPTY_TEXTURE: Texture2D = preload("res://assets/sprites/ui/main/shield_ren_off.png")
const ULTIMATE_MAX_CHARGES := 7
const COMBAT_REPORT_WEAPON_ICONS: Dictionary = {
	"Classic": preload("res://assets/sprites/ui/guns/classic.png"),
	"Vandal": preload("res://assets/sprites/ui/guns/vandal.png"),
	"Knife": preload("res://assets/sprites/ui/guns/knife.png"),
	"Spectre": preload("res://assets/sprites/ui/guns/spectre.png"),
	"Judge": preload("res://assets/sprites/ui/guns/judge.png"),
	"Operator": preload("res://assets/sprites/ui/guns/operator.png"),
	"Odin": preload("res://assets/sprites/ui/guns/odin.png"),
	"Blade Storm": preload("res://assets/sprites/ui/abilities/jett/blade_storm.png"),
	"Hot Hands": preload("res://assets/sprites/ui/abilities/phoenix/hot_hands.png"),
	"Blaze": preload("res://assets/sprites/ui/abilities/phoenix/blaze.png"),
}

func _ready() -> void:
	_deathmatch_display.setup(self)
	_ability_display.setup(self)
	_skirmish_display.setup(self)
	_training_cheats_controller.setup(self)
	_low_status_display.setup(health_decor, bullet_decor)
	_kill_streak_display.setup(kill_streak_base, kill_streak_count)
	_regenerative_shield_display.setup(self)
	_combat_report_agent_icons.append(combat_report_agent)
	_combat_report_rows.append(get_node("Control/Combat Report/Report/Container") as Control)
	main_container.visible = true
	ally_health_default_tint = ally_health_progress.tint_progress
	cheats_panel.visible = false
	infinite_abilities_button.toggled.connect(_on_infinite_abilities_toggled)
	infinite_ammo_button.toggled.connect(_on_infinite_ammo_toggled)
	infinite_credits_button.toggled.connect(_on_infinite_credits_toggled)
	invulnerability_button.toggled.connect(_on_invulnerability_toggled)
	combat_report.visible = false
	combat_report_murdered.visible = false
	combat_report_weapon.visible = false
	combat_report_agent.visible = false
	agent_select_panel.visible = false
	phoenix_select_button.pressed.connect(_on_phoenix_select_pressed)
	jett_select_button.pressed.connect(_on_jett_select_pressed)
	sage_select_button.pressed.connect(_on_sage_select_pressed)
	ability_timer.visible = false
	ability_timer_name.visible = false
	_setup_ability_bar()
	flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_overlay.visible = false
	flash_default_color = flash_overlay.color
	flash_effect.visible = false
	jett_dash_overlay.visible = false
	flash_effect_base_scale = flash_effect.scale
	flashes_container.visible = true
	healing_overlay.visible = false
	healing_state_template.visible = false
	bad_state_template.visible = false
	bad_states.visible = false
	clear_alert()
	NetworkManager.kill_feed_received.connect(show_kill_feed)
	if not NetworkManager.combat_report_received.is_connected(_on_combat_report_received):
		NetworkManager.combat_report_received.connect(_on_combat_report_received)
	if not NetworkManager.skirmish_combat_outcome_received.is_connected(_on_skirmish_combat_outcome_received):
		NetworkManager.skirmish_combat_outcome_received.connect(_on_skirmish_combat_outcome_received)
	if not NetworkManager.skirmish_round_result_received.is_connected(_on_skirmish_round_result_received):
		NetworkManager.skirmish_round_result_received.connect(_on_skirmish_round_result_received)
	if not NetworkManager.deathmatch_scores_updated.is_connected(_on_deathmatch_scores_updated):
		NetworkManager.deathmatch_scores_updated.connect(_on_deathmatch_scores_updated)
	var mode_selector := get_tree().current_scene.get_node_or_null("GameModeSelector") as GameModeSelector
	is_deathmatch_mode = mode_selector != null and mode_selector.is_deathmatch()
	is_skirmish_mode = mode_selector != null and mode_selector.is_skirmish()
	normal_container.visible = not is_deathmatch_mode
	deathmatch_container.visible = is_deathmatch_mode
	kills_container.visible = is_deathmatch_mode or is_skirmish_mode
	deathmatch_scoreboard.visible = is_deathmatch_mode
	skirmish_scoreboard.visible = is_skirmish_mode
	scoreboard_container.visible = false
	_prepare_kill_feed()
	_prepare_deathmatch_cards()
	_prepare_scoreboard_rows()
	bind_player()

func refresh_game_mode() -> void:
	var current_scene := get_tree().current_scene
	if not current_scene:
		push_error("Cannot refresh the HUD without an active scene.")
		return
	var mode_selector := current_scene.get_node_or_null("GameModeSelector") as GameModeSelector
	is_deathmatch_mode = mode_selector != null and mode_selector.is_deathmatch()
	is_skirmish_mode = mode_selector != null and mode_selector.is_skirmish()
	normal_container.visible = not is_deathmatch_mode
	deathmatch_container.visible = is_deathmatch_mode
	kills_container.visible = is_deathmatch_mode or is_skirmish_mode
	deathmatch_scoreboard.visible = is_deathmatch_mode
	skirmish_scoreboard.visible = is_skirmish_mode
	update_deathmatch_hud()
	update_scoreboard()

func start_ability_timer(ability_name: String, duration: float) -> void:
	if duration <= 0.0 or not is_finite(duration):
		push_error("Ability timer duration must be a finite, positive value.")
		return
	if ability_timer_tween and ability_timer_tween.is_running():
		ability_timer_tween.kill()
	ability_timer.max_value = duration
	ability_timer.step = 0.001
	ability_timer.value = duration
	ability_timer_name.text = ability_name
	ability_timer_name.visible = true
	ability_timer.visible = true
	ability_timer_tween = create_tween()
	ability_timer_tween.set_trans(Tween.TRANS_LINEAR)
	ability_timer_tween.tween_property(ability_timer, "value", 0.0, duration)

func hide_ability_timer() -> void:
	if ability_timer_tween and ability_timer_tween.is_running():
		ability_timer_tween.kill()
	ability_timer.visible = false
	ability_timer_name.visible = false

func show_jett_dash_effect() -> void:
	jett_dash_overlay.visible = true

func hide_jett_dash_effect() -> void:
	jett_dash_overlay.visible = false

func show_sage_resurrection_effect() -> void:
	sage_resurrection_overlay.visible = true

func hide_sage_resurrection_effect() -> void:
	sage_resurrection_overlay.visible = false

func play_jett_dash_effect() -> void:
	jett_dash_overlay.visible = true
	var tween := create_tween()
	tween.tween_property(jett_dash_overlay, "modulate:a", 0.0, 0.18)
	tween.tween_callback(func() -> void:
		jett_dash_overlay.modulate.a = 1.0
		jett_dash_overlay.visible = false
	)

func show_flash(
	duration: float,
	world_position: Vector2,
	flash_color: Color = Color.TRANSPARENT
) -> void:
	if duration <= 0.0 or not is_finite(duration):
		push_error("Flash duration must be a finite, positive value.")
		return
	if not world_position.is_finite():
		push_error("Flash position must be finite.")
		return
	if flash_tween and flash_tween.is_running():
		flash_tween.kill()
	if flash_effect_tween and flash_effect_tween.is_running():
		flash_effect_tween.kill()

	var fade_in_duration := minf(0.05, duration * 0.1)
	var fade_out_duration := minf(0.65, duration * 0.4)
	var hold_duration := maxf(duration - fade_in_duration - fade_out_duration, 0.0)
	flash_overlay.color = flash_default_color if flash_color.a <= 0.0 else flash_color
	flash_overlay.visible = true
	flash_overlay.modulate.a = 0.0
	flash_tween = create_tween()
	flash_tween.tween_property(flash_overlay, "modulate:a", 1.0, fade_in_duration)
	flash_tween.tween_interval(hold_duration)
	flash_tween.tween_property(flash_overlay, "modulate:a", 0.0, fade_out_duration)
	flash_tween.tween_callback(_finish_flash)

	if not flash_effect.texture:
		return
	flash_effect.position = get_viewport().get_canvas_transform() * world_position
	flash_effect.scale = flash_effect_base_scale
	flash_effect.modulate.a = 1.0
	flash_effect.visible = true
	var scale_duration := minf(0.12, duration * 0.25)
	var explosion_hold_duration := maxf(duration - scale_duration - fade_out_duration, 0.0)
	flash_effect_tween = create_tween()
	flash_effect_tween.tween_property(
		flash_effect,
		"scale",
		flash_effect_base_scale * 1.35,
		scale_duration
	)
	flash_effect_tween.tween_interval(explosion_hold_duration)
	flash_effect_tween.tween_property(
		flash_effect,
		"modulate:a",
		0.0,
		fade_out_duration
	)
	flash_effect_tween.tween_callback(_finish_flash_effect)

func _finish_flash() -> void:
	flash_overlay.visible = false
	flash_overlay.color = flash_default_color

func _finish_flash_effect() -> void:
	flash_effect.visible = false
	flash_effect.scale = flash_effect_base_scale

func add_healing_state(effect_id: int, ability_name: String, duration: float) -> void:
	if effect_id <= 0 or duration <= 0.0 or not is_finite(duration):
		push_error("Healing state requires a positive effect ID and duration.")
		return
	var ability_icon := _get_ability_icon(ability_name)
	if not ability_icon:
		push_error("No ability icon is configured for healing state: %s." % ability_name)
		return
	remove_healing_state(effect_id)

	var state_entry := healing_state_template.duplicate() as TextureRect
	state_entry.name = "Healing_%d" % effect_id
	state_entry.visible = true
	healing_states.add_child(state_entry)
	var effect_label := state_entry.get_node("Effect") as Label
	var ability_icon_node := state_entry.get_node("Icon") as TextureRect
	var time_bar := state_entry.get_node("Time") as TextureProgressBar
	effect_label.text = "HEALING"
	ability_icon_node.texture = ability_icon
	time_bar.min_value = 0.0
	time_bar.max_value = duration
	time_bar.step = 0.0
	time_bar.value = duration
	healing_state_entries[effect_id] = {
		"node": state_entry,
		"duration": duration,
	}
	healing_overlay.visible = true
	_update_ally_health_tint()

func update_healing_state(effect_id: int, remaining: float) -> void:
	if not healing_state_entries.has(effect_id):
		return
	var state: Dictionary = healing_state_entries[effect_id]
	var state_node: Control = state["node"]
	var time_bar := state_node.get_node("Time") as TextureProgressBar
	time_bar.value = clampf(remaining, 0.0, float(state["duration"]))

func remove_healing_state(effect_id: int) -> void:
	if not healing_state_entries.has(effect_id):
		return
	var state: Dictionary = healing_state_entries[effect_id]
	var state_node: Control = state["node"]
	state_node.queue_free()
	healing_state_entries.erase(effect_id)
	healing_overlay.visible = not healing_state_entries.is_empty()
	_update_ally_health_tint()

func clear_healing_states() -> void:
	for effect_id in healing_state_entries.keys():
		remove_healing_state(int(effect_id))

func set_slow_state(active: bool) -> void:
	if active:
		if is_instance_valid(slow_state_entry):
			return
		slow_state_entry = bad_state_template.duplicate() as TextureRect
		slow_state_entry.name = "Slow"
		slow_state_entry.visible = true
		bad_states.add_child(slow_state_entry)
		(slow_state_entry.get_node("Effect") as Label).text = "SLOWED"
		var icon := _ability_display.get_ability_icon("Slow Orb")
		(slow_state_entry.get_node("Icon") as TextureRect).texture = icon
		var time_bar := slow_state_entry.get_node("Time") as TextureProgressBar
		time_bar.min_value = 0.0
		time_bar.max_value = 1.0
		time_bar.value = 1.0
		bad_states.visible = true
		return
	if is_instance_valid(slow_state_entry):
		slow_state_entry.queue_free()
	slow_state_entry = null
	bad_states.visible = false

func clear_alert() -> void:
	if not alert_label:
		return
	alert_label.text = ""
	alert_label.visible = false
	alert_label.modulate.a = 0.0

func show_alert(message: String, duration: float = 2.0, text_color: Color = Color(1.0, 0.82, 0.28, 1.0)) -> void:
	if not alert_label:
		return
	if alert_tween and alert_tween.is_running():
		alert_tween.kill()
	alert_label.text = message
	alert_label.modulate = text_color
	alert_label.visible = true
	alert_label.modulate.a = 0.0
	alert_tween = create_tween()
	alert_tween.tween_property(alert_label, "modulate:a", 1.0, 0.18)
	if duration > 0.0:
		alert_tween.tween_interval(duration)
		alert_tween.tween_property(alert_label, "modulate:a", 0.0, 0.25)
		alert_tween.tween_callback(clear_alert)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_F1:
			if key_event.pressed and not key_event.echo:
				bind_player()
			if key_event.pressed and not key_event.echo and player and player.has_local_authority():
				cheats_panel.visible = not cheats_panel.visible
				if cheats_panel.visible and agent_select_panel.visible:
					_set_agent_select_visible(false)
				player.set_training_menu_open(cheats_panel.visible)
				if cheats_panel.visible:
					_refresh_cheat_controls()
					infinite_abilities_button.grab_focus()
			get_viewport().set_input_as_handled()
			return
		if key_event.keycode == KEY_F2:
			if key_event.pressed and not key_event.echo and player and player.has_local_authority():
				if not player.is_dead and not player.shop_open:
					if is_skirmish_mode and not NetworkManager.can_select_skirmish_agent():
						show_alert("La selección de agente solo está disponible al inicio de la partida", 2.0)
					elif (
						is_deathmatch_mode
						and not agent_select_panel.visible
						and player.get_agent_switch_lock_remaining() > 0.0
					):
						_show_agent_switch_lock_alert()
					else:
						_set_agent_select_visible(not agent_select_panel.visible)
						if agent_select_panel.visible:
							scoreboard_container.visible = false
			get_viewport().set_input_as_handled()
			return
		if (not is_deathmatch_mode and not is_skirmish_mode) or key_event.keycode != KEY_TAB:
			return
		scoreboard_container.visible = key_event.pressed
		get_viewport().set_input_as_handled()

func _on_phoenix_select_pressed() -> void:
	_try_select_agent("phoenix")

func _on_jett_select_pressed() -> void:
	_try_select_agent("jett")

func _on_sage_select_pressed() -> void:
	_try_select_agent("sage")

func _try_select_agent(agent_id: String) -> void:
	if not player:
		return
	if is_skirmish_mode and not NetworkManager.can_select_skirmish_agent():
		show_alert("La selección de agente solo está disponible al inicio de la partida", 2.0)
		return
	if is_deathmatch_mode and player.get_agent_switch_lock_remaining() > 0.0:
		_show_agent_switch_lock_alert()
		return
	if NetworkManager.set_selected_agent(agent_id):
		if not NetworkManager.is_networked() or multiplayer.is_server():
			_set_agent_select_visible(false)
		elif player.agent_data and player.agent_data.agent_id == agent_id:
			_set_agent_select_visible(false)
	else:
		show_alert("Tu equipo ya tiene ese agente", 2.0)

func _show_agent_switch_lock_alert() -> void:
	var remaining_seconds := ceili(player.get_agent_switch_lock_remaining())
	show_alert(
		"No puedes cambiar de agente durante el combate (%d s)" % remaining_seconds,
		2.0,
		Color(0.9, 0.22, 0.22, 1.0)
	)

func _set_agent_select_visible(should_be_visible: bool) -> void:
	agent_select_panel.visible = should_be_visible
	if not player:
		return
	player.agent_select_open = should_be_visible
	player.weapon_controller.suppress_shoot_until_released()

func _on_deathmatch_scores_updated(scores: Dictionary, deaths: Dictionary) -> void:
	_deathmatch_display.on_scores_updated(scores, deaths)

func _prepare_kill_feed() -> void:
	_deathmatch_display.prepare_kill_feed()

func show_kill_feed(killer_peer_id: int, victim_peer_id: int, weapon_name: String = "") -> void:
	if player and killer_peer_id == NetworkManager.get_deathmatch_actor_id(player):
		_kill_streak_display.register_kill()
		if is_skirmish_mode:
			var victim := NetworkManager.find_deathmatch_actor(victim_peer_id) as BaseAgent
			if victim:
				_record_skirmish_combat_outcome(
					"KILL",
					victim_peer_id,
					int(victim.get("combat_life_id"))
				)
	_deathmatch_display.show_kill_feed(killer_peer_id, victim_peer_id, weapon_name)

func set_deathmatch_kills(kills: int, target: int = -1) -> void:
	_deathmatch_display.set_deathmatch_kills(kills, target)

func set_deathmatch_score(peer_id: int, kills: int, target: int = -1) -> void:
	_deathmatch_display.set_deathmatch_score(peer_id, kills, target)

func _prepare_deathmatch_cards() -> void:
	_deathmatch_display.prepare_deathmatch_cards()

func update_deathmatch_hud() -> void:
	_deathmatch_display.update_deathmatch_hud()

func _prepare_scoreboard_rows() -> void:
	_deathmatch_display.prepare_scoreboard_rows()

func update_scoreboard() -> void:
	if is_skirmish_mode:
		_skirmish_display.update_scoreboard()
	else:
		_deathmatch_display.update_scoreboard()

func show_skirmish_round_state(round_number: int, preparing: bool, duration: float) -> void:
	if not preparing:
		combat_report.visible = false
		_skirmish_death_report_pending = false
	elif round_number > 1 and not NetworkManager.is_skirmish_recess():
		_kill_streak_display.reset()
		if not player:
			bind_player()
		if not _skirmish_death_report_pending and player and not player.is_dead:
			_show_skirmish_round_summary()
			_skirmish_round_stats.clear()
			_skirmish_combat_outcomes.clear()
	if (
		preparing
		and round_number == 1
		and NetworkManager.can_select_skirmish_agent()
		and not _skirmish_initial_selection_shown
	):
		_skirmish_initial_selection_shown = true
		bind_player()
		if player and not player.is_dead:
			_set_agent_select_visible(true)
	if not preparing and agent_select_panel.visible:
		_set_agent_select_visible(false)
	_skirmish_display.show_round_state(round_number, preparing, duration)

func bind_player() -> void:
	var current_scene := get_tree().current_scene
	if not current_scene:
		return
	var local_player: BaseAgent
	if multiplayer.has_multiplayer_peer():
		var local_peer_id := multiplayer.get_unique_id()
		if local_peer_id > 0:
			local_player = current_scene.get_node_or_null(
				"Player_%d" % local_peer_id
			) as BaseAgent
		if not local_player and local_peer_id == 1:
			local_player = current_scene.get_node_or_null("BaseAgent") as BaseAgent
	else:
		local_player = get_node_or_null(player_path) as BaseAgent
		if not local_player:
			local_player = get_parent().get_node_or_null("BaseAgent") as BaseAgent
	if not local_player:
		return
	if player != local_player:
		player = local_player
		_bind_player_signals()
	if player.has_local_authority():
		player.set_infinite_credits_enabled(infinite_credits_button.button_pressed)
		player.set_infinite_ammo_enabled(infinite_ammo_button.button_pressed)
		player.set_invulnerable_enabled(invulnerability_button.button_pressed)
	_training_cheats_controller.bind_player()
	weapon_controller = player.weapon_controller
	_deathmatch_display.sync_scores_from_network()

	_on_health_changed(player.get_current_health(), player.get_max_health())
	_on_shield_changed(player.get_current_shield(), player.get_max_shield())
	_regenerative_shield_display.bind_health_component(player.health_component)
	_apply_agent_ability_ui()
	_refresh_ability_charges()
	update_deathmatch_hud()
	update_weapon_info()
	_on_weapon_changed(weapon_controller.current_weapon, weapon_controller.current_weapon_slot)

func _bind_player_signals() -> void:
	if not player.health_changed.is_connected(_on_health_changed):
		player.health_changed.connect(_on_health_changed)
	if not player.shield_changed.is_connected(_on_shield_changed):
		player.shield_changed.connect(_on_shield_changed)
	if not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)
	if not player.respawned.is_connected(_on_player_respawned):
		player.respawned.connect(_on_player_respawned)
	if not player.kill_streak_reset_requested.is_connected(_on_kill_streak_reset_requested):
		player.kill_streak_reset_requested.connect(_on_kill_streak_reset_requested)
	if not player.weapon_changed.is_connected(_on_weapon_changed):
		player.weapon_changed.connect(_on_weapon_changed)
	if not player.agent_data_changed.is_connected(_on_agent_data_changed):
		player.agent_data_changed.connect(_on_agent_data_changed)
	if not player.ultimate_state_changed.is_connected(_on_ultimate_state_changed):
		player.ultimate_state_changed.connect(_on_ultimate_state_changed)

func _refresh_cheat_controls() -> void:
	if not player or not player.has_local_authority():
		return
	_training_cheats_controller.set_infinite_abilities_enabled(infinite_abilities_button.button_pressed)
	player.set_infinite_credits_enabled(infinite_credits_button.button_pressed)
	player.set_infinite_ammo_enabled(infinite_ammo_button.button_pressed)
	player.set_invulnerable_enabled(invulnerability_button.button_pressed)

func _on_infinite_abilities_toggled(enabled: bool) -> void:
	if not player or not player.has_local_authority():
		return
	_training_cheats_controller.set_infinite_abilities_enabled(enabled)

func _on_infinite_ammo_toggled(enabled: bool) -> void:
	if player and player.has_local_authority():
		player.set_infinite_ammo_enabled(enabled)
	if player:
		player.weapon_controller.suppress_shoot_until_released()

func _on_infinite_credits_toggled(enabled: bool) -> void:
	if player and player.has_local_authority():
		player.set_infinite_credits_enabled(enabled)
	if player:
		player.weapon_controller.suppress_shoot_until_released()

func _on_invulnerability_toggled(enabled: bool) -> void:
	if player and player.has_local_authority():
		player.set_invulnerable_enabled(enabled)

func _setup_ability_bar() -> void:
	_ability_display.setup_ability_bar()

func _prepare_ultimate_charge_markers(required_charges: int = ULTIMATE_MAX_CHARGES) -> void:
	_ability_display.prepare_ultimate_charge_markers(required_charges)

func _get_ability_icon(ability_name: String) -> Texture2D:
	return _ability_display.get_ability_icon(ability_name)

func _on_agent_data_changed(data: AgentData) -> void:
	_ability_display.on_agent_data_changed(data)
	if player and player.agent_select_open:
		_set_agent_select_visible(false)

func _apply_agent_ability_ui() -> void:
	_ability_display.apply_agent_ability_ui()

func _refresh_ability_charges() -> void:
	_ability_display.refresh_ability_charges()

func _on_charge_state_changed(charges: Dictionary) -> void:
	_ability_display.on_charge_state_changed(charges)
	var data := player.agent_data if player else null
	var ultimate_ready := false
	if data and data.ultimate_charges_required > 0:
		ultimate_ready = int(charges.get(data.ultimate_charge_key, 0)) >= data.ultimate_charges_required
	var ultimate_active := _is_local_ultimate_active()
	_on_ultimate_state_changed(ultimate_ready, ultimate_active)

func _is_local_ultimate_active() -> bool:
	if not player:
		return false
	for component in player.get_node("Components").get_children():
		if component.has_method("is_ultimate_active") and bool(component.call("is_ultimate_active")):
			return true
	return false

func _on_ultimate_state_changed(is_ready: bool, active: bool) -> void:
	ally_ultimate_active.visible = active
	ally_ultimate_inactive.visible = is_ready and not active

func _process(_delta: float) -> void:
	_training_cheats_controller.process(_delta)
	if is_skirmish_mode:
		_skirmish_display.process_round_countdown(_delta)
		_skirmish_display.update_team_agent_icons()
	if not player:
		bind_player()
	if player:
		_update_spectator_ability_display()
		update_weapon_info()
		update_deathmatch_hud()
		if scoreboard_container.visible:
			update_scoreboard()

func _update_spectator_ability_display() -> void:
	if not player or not player.is_dead or not player.has_local_authority():
		_ability_display.set_display_agent(null)
		return
	var controller: Object = player.get("_spectator_controller")
	if controller and controller.has_method("get_target"):
		_ability_display.set_display_agent(controller.call("get_target") as BaseAgent)

func _on_health_changed(current_health: float, max_health: float) -> void:
	health_label.text = "%d" % roundi(current_health)
	ally_health_progress.value = current_health
	_update_ally_health_tint(current_health, max_health)
	_low_status_display.update_health(current_health, max_health)

func _update_ally_health_tint(current_health: float = -1.0, max_health: float = -1.0) -> void:
	if player:
		if current_health < 0.0:
			current_health = player.get_current_health()
		if max_health < 0.0:
			max_health = player.get_max_health()
	if not healing_state_entries.is_empty():
		ally_health_progress.tint_progress = Color("22ffc5", ally_health_default_tint.a)
		return
	var health_ratio := current_health / max_health if max_health > 0.0 else 0.0
	ally_health_progress.tint_progress = (
		Color("f05c56", ally_health_default_tint.a)
		if health_ratio < 0.25
		else ally_health_default_tint
	)

func _on_shield_changed(current_shield: float, _max_shield: float) -> void:
	shield_label.text = "%d" % roundi(current_shield)
	if player and player.active_shield_item_id == "shield_regen":
		shield_icon.texture = (
			REGENERATIVE_SHIELD_TEXTURE
			if current_shield > 0.0
			else REGENERATIVE_SHIELD_EMPTY_TEXTURE
		)
	else:
		shield_icon.texture = SHIELD_TEXTURE if current_shield > 0.0 else SHIELD_EMPTY_TEXTURE

func update_weapon_info() -> void:
	if not weapon_controller:
		return

	if weapon_controller.current_weapon and weapon_controller.current_weapon.is_melee:
		ammo_label.text = "-"
		reserve_ammo_label.text = "-"
		_low_status_display.update_ammo(0, 0)
		return

	if not weapon_controller.current_weapon:
		ammo_label.text = "0"
		reserve_ammo_label.text = "0"
		_low_status_display.update_ammo(0, 0)
		return

	ammo_label.text = "%d" % weapon_controller.ammo_in_magazine
	reserve_ammo_label.text = "%d" % weapon_controller.reserve_ammo
	_low_status_display.update_ammo(
		weapon_controller.ammo_in_magazine,
		weapon_controller.current_weapon.magazine_size
	)

func _on_weapon_changed(_weapon: WeaponData, active_slot: int) -> void:
	var displayed_active_slot := -1 if blade_storm_equipped else active_slot
	for slot in weapon_slots.size():
		var is_active := slot == displayed_active_slot
		weapon_slots[slot].modulate.a = 1.0 if is_active else 0.35

		if slot == 2:
			weapon_slot_names[slot].text = "MELEE"
			var melee_weapon: WeaponData = weapon_controller.weapon_slots[slot] if slot < weapon_controller.weapon_slots.size() else null
			weapon_slot_icons[slot].texture = melee_weapon.ui_sprite if melee_weapon else null
			continue

		var slot_weapon: WeaponData = weapon_controller.weapon_slots[slot] if slot < weapon_controller.weapon_slots.size() else null
		if slot_weapon:
			weapon_slot_names[slot].text = slot_weapon.weapon_name
			weapon_slot_icons[slot].texture = get_weapon_hud_icon(slot_weapon)
		else:
			weapon_slot_names[slot].text = "EMPTY"
			weapon_slot_icons[slot].texture = null

func set_weapon_slot_selected(slot: int, selected: bool) -> void:
	if slot < 0 or slot >= weapon_slots.size():
		return
	weapon_slots[slot].modulate.a = 1.0 if selected else 0.35

func set_blade_storm_equipped(equipped: bool) -> void:
	blade_storm_equipped = equipped
	_on_weapon_changed(
		weapon_controller.current_weapon if weapon_controller else null,
		weapon_controller.current_weapon_slot if weapon_controller else -1
	)

func get_weapon_hud_icon(weapon: WeaponData) -> Texture2D:
	return weapon.ui_sprite

func _on_player_died() -> void:
	_kill_streak_display.reset()
	ammo_label.text = "-"
	reserve_ammo_label.text = "-"
	show_alert("¡HAS MUERTO!", 2.5, Color(0.9, 0.22, 0.22, 1.0))
	_show_combat_report()
	if is_skirmish_mode:
		_skirmish_death_report_pending = combat_report.visible

func _on_player_respawned() -> void:
	if is_skirmish_mode:
		return
	combat_report.visible = false
	_reset_combat_report_rows()

func _on_kill_streak_reset_requested() -> void:
	if player and player.has_local_authority():
		_kill_streak_display.reset()

func _show_combat_report() -> void:
	if not player:
		return
	var killer := player.last_attacker
	if not is_instance_valid(killer):
		combat_report.visible = false
		return
	if is_skirmish_mode:
		_show_skirmish_death_report(
			player.get_combat_damage_dealt_total(),
			player.get_combat_damage_received_total(),
			_get_combat_actor_name(killer),
			_get_combat_actor_sprite(killer),
			player.last_attacker_weapon_name,
			_get_combat_damage_source_paths(player),
			NetworkManager.call("_get_combat_report_attacker_details", player)
		)
		return

	var attacker_details: Array = NetworkManager.call(
		"_get_combat_report_attacker_details", player
	)
	if not attacker_details.is_empty():
		_show_combat_report_attacker_rows(attacker_details)
		return
	_reset_combat_report_rows()
	combat_report_outgoing.text = "%d" % roundi(player.get_combat_damage_dealt_to(killer))
	combat_report_incoming.text = "%d" % roundi(player.get_combat_damage_received_from(killer))
	combat_report_agent.texture = player.agent_data.agent_sprite if player.agent_data else null
	combat_report_killer.text = "KILLED BY %s" % _get_combat_actor_name(killer)
	combat_report_killer_icon.texture = _get_combat_actor_sprite(killer)
	combat_report_weapon.texture = _get_combat_actor_weapon_icon(killer)
	combat_report_killer_icon.visible = combat_report_killer_icon.texture != null
	combat_report_weapon.visible = combat_report_weapon.texture != null
	combat_report.visible = true

func _on_combat_report_received(
	killer_name: String,
	killer_agent_id: String,
	killer_sprite_path: String,
	weapon_name: String,
	outgoing_damage: float,
	incoming_damage: float,
	damage_source_paths: Array,
	attacker_details: Array
) -> void:
	if is_skirmish_mode:
		var killer_sprite: Texture2D
		if not killer_agent_id.is_empty():
			var killer_data := NetworkManager.get_agent_data(killer_agent_id)
			killer_sprite = killer_data.agent_sprite if killer_data else null
		if not killer_sprite and not killer_sprite_path.is_empty():
			killer_sprite = load(killer_sprite_path) as Texture2D
		_show_skirmish_death_report(
			outgoing_damage,
			incoming_damage,
			killer_name,
			killer_sprite,
			weapon_name,
			damage_source_paths,
			attacker_details
		)
		return
	if not attacker_details.is_empty():
		_show_combat_report_attacker_rows(attacker_details)
		return
	_reset_combat_report_rows()
	combat_report_outgoing.text = "%d" % roundi(outgoing_damage)
	combat_report_incoming.text = "%d" % roundi(incoming_damage)
	combat_report_agent.texture = player.agent_data.agent_sprite if player and player.agent_data else null
	combat_report_killer.text = "KILLED BY %s" % killer_name
	combat_report_murdered.visible = true
	if not killer_agent_id.is_empty():
		var killer_data := NetworkManager.get_agent_data(killer_agent_id)
		combat_report_killer_icon.texture = killer_data.agent_sprite if killer_data else null
	if not combat_report_killer_icon.texture and not killer_sprite_path.is_empty():
		combat_report_killer_icon.texture = load(killer_sprite_path) as Texture2D
	elif killer_agent_id.is_empty() and killer_sprite_path.is_empty():
		combat_report_killer_icon.texture = null
	combat_report_weapon.texture = COMBAT_REPORT_WEAPON_ICONS.get(weapon_name) as Texture2D
	combat_report_killer_icon.visible = combat_report_killer_icon.texture != null
	combat_report_weapon.visible = combat_report_weapon.texture != null
	combat_report.visible = true

func _on_skirmish_round_result_received(
	_winner_team: int,
	team_wins: Array,
	round_stats: Dictionary
) -> void:
	if not is_skirmish_mode:
		return
	if not player:
		bind_player()
	if not player:
		return
	_skirmish_display.show_round_result(team_wins)
	_skirmish_round_stats = round_stats.duplicate(true) if round_stats != null else {}

func _show_skirmish_round_summary() -> void:
	if not player:
		bind_player()
	if not player or player.is_dead or _skirmish_death_report_pending:
		return
	var player_stats: Dictionary = _skirmish_round_stats.get(player.get_multiplayer_authority(), {})
	if player_stats.is_empty():
		player_stats = {
			"damage_dealt": player.get_combat_damage_dealt_total(),
			"damage_received": player.get_combat_damage_received_total(),
		}
	var dealt := float(player_stats.get("damage_dealt", 0.0))
	var received := float(player_stats.get("damage_received", 0.0))
	var damage_by_target: Array = player_stats.get("damage_by_target", [])
	_reset_combat_report_rows()
	combat_report_outgoing_header.visible = true
	combat_report_incoming_header.visible = true
	combat_report_agent.texture = null
	combat_report_agent.visible = false
	combat_report_murdered.visible = false
	combat_report_killer_icon.visible = false
	combat_report_weapon.visible = false
	if damage_by_target.is_empty():
		var summary_row := combat_report_rows_container.get_node("Container") as Control
		if summary_row:
			summary_row.visible = true
		combat_report_outgoing.text = "%d" % roundi(dealt)
		combat_report_outgoing_caption.text = "DAMAGE"
		combat_report_outgoing_caption.visible = true
		combat_report_incoming.text = "%d" % roundi(received)
		combat_report_incoming_caption.text = "DAMAGE"
		combat_report_incoming_caption.visible = true
	else:
		_set_combat_report_attacker_rows(damage_by_target)
	combat_report.visible = true
	combat_report.move_to_front()

func get_skirmish_local_round_stats() -> Dictionary:
	if not player:
		bind_player()
	if not player:
		return {}
	var damage_by_target: Array = []
	var dealt_to_actor: Dictionary = player.combat_damage_dealt_to_actor
	var dealt_weapon_by_actor: Dictionary = player.combat_damage_dealt_weapon_by_actor
	var received_by_actor: Dictionary = player.combat_damage_received_by_actor
	var current_scene := get_tree().current_scene
	if current_scene:
		for target in current_scene.get_children():
			if not target is BaseAgent or target == player:
				continue
			if int(target.skirmish_team) == int(player.skirmish_team):
				continue
			var dealt := float(dealt_to_actor.get(target.get_instance_id(), 0.0))
			var received := float(received_by_actor.get(target.get_instance_id(), 0.0))
			if dealt <= 0.0 and received <= 0.0:
				continue
			var sprite := _get_combat_actor_sprite(target)
			damage_by_target.append({
				"actor_id": NetworkManager.get_deathmatch_actor_id(target),
				"life_id": int(target.get("combat_life_id")),
				"sprite_path": sprite.resource_path if sprite else "",
				"outgoing": dealt,
				"incoming": received,
				"assist_damage": dealt,
				"weapon": str(dealt_weapon_by_actor.get(target.get_instance_id(), "")),
				"is_killer": false,
			})
	return {
		"damage_dealt": player.get_combat_damage_dealt_total(),
		"damage_received": player.get_combat_damage_received_total(),
		"damage_by_target": damage_by_target,
	}

func _show_skirmish_death_report(
	outgoing_damage: float,
	incoming_damage: float,
	killer_name: String,
	killer_sprite: Texture2D,
	weapon_name: String,
	damage_source_paths: Array,
	attacker_details: Array = []
) -> void:
	_reset_combat_report_rows()
	combat_report_outgoing.text = "%d" % roundi(outgoing_damage)
	combat_report_outgoing_caption.text = "DAMAGE"
	combat_report_outgoing_caption.visible = true
	combat_report_outgoing.visible = true
	combat_report_outgoing_header.visible = true
	combat_report_incoming.text = "%d" % roundi(incoming_damage)
	combat_report_incoming_caption.text = "KILLED"
	combat_report_incoming_caption.visible = true
	combat_report_incoming.visible = true
	combat_report_incoming_header.visible = true
	combat_report_killer.text = "KILLED BY %s" % killer_name
	combat_report_killer_icon.texture = killer_sprite
	combat_report_killer_icon.visible = killer_sprite != null
	combat_report_murdered.visible = true
	if attacker_details.is_empty():
		combat_report_weapon.texture = COMBAT_REPORT_WEAPON_ICONS.get(weapon_name) as Texture2D
		combat_report_weapon.visible = combat_report_weapon.texture != null
		_set_combat_report_agent_icons(damage_source_paths, killer_sprite)
	else:
		_set_combat_report_attacker_rows(attacker_details)
	combat_report.visible = true

func _show_combat_report_attacker_rows(attacker_details: Array) -> void:
	combat_report_killer.text = "DAMAGE BY EACH ATTACKER"
	combat_report_murdered.visible = false
	combat_report_weapon.visible = false
	combat_report_killer_icon.visible = false
	combat_report_agent.texture = player.agent_data.agent_sprite if player and player.agent_data else null
	combat_report_outgoing_caption.visible = false
	combat_report_incoming_caption.visible = false
	combat_report_outgoing_header.visible = true
	combat_report_incoming_header.visible = true
	_set_combat_report_attacker_rows(attacker_details)
	combat_report.visible = true

func _reset_combat_report_rows() -> void:
	for row in _combat_report_rows:
		row.visible = false

func _set_combat_report_attacker_rows(attacker_details: Array) -> void:
	if _combat_report_rows.is_empty():
		return
	while _combat_report_rows.size() < attacker_details.size():
		var row := _combat_report_rows[0].duplicate() as Control
		row.name = "Attacker%d" % _combat_report_rows.size()
		combat_report_rows_container.add_child(row)
		_combat_report_rows.append(row)
	for index in _combat_report_rows.size():
		var row := _combat_report_rows[index]
		row.visible = index < attacker_details.size()
		if index >= attacker_details.size():
			continue
		var detail: Dictionary = attacker_details[index]
		var outgoing := row.get_node_or_null("Outgoing") as Label
		var incoming := row.get_node_or_null("Incoming") as Label
		var outgoing_caption := row.get_node_or_null("Outgoing/Label") as Label
		var incoming_caption := row.get_node_or_null("Incoming/Label") as Label
		var agent_icon := row.get_node_or_null("Agent") as TextureRect
		var weapon_icon := row.get_node_or_null("Weapon") as TextureRect
		var actor_id := int(detail.get("actor_id", -1))
		var life_id := int(detail.get("life_id", -1))
		row.set_meta("combat_report_actor_id", actor_id)
		row.set_meta("combat_report_life_id", life_id)
		if outgoing:
			outgoing.text = "%d" % roundi(float(detail.get("outgoing", 0.0)))
		if incoming:
			incoming.text = "%d" % roundi(float(detail.get("incoming", 0.0)))
		if outgoing_caption:
			outgoing_caption.text = str(_skirmish_combat_outcomes.get(_combat_outcome_key(actor_id, life_id), ""))
			if (
				outgoing_caption.text == "ASSIST"
				and float(detail.get("assist_damage", detail.get("incoming", 0.0))) < 50.0
			):
				outgoing_caption.text = ""
			outgoing_caption.visible = not outgoing_caption.text.is_empty()
		if incoming_caption:
			incoming_caption.text = "KILLED" if bool(detail.get("is_killer", false)) else ""
			incoming_caption.visible = bool(detail.get("is_killer", false))
		var sprite_path := str(detail.get("sprite_path", ""))
		if agent_icon:
			agent_icon.texture = load(sprite_path) as Texture2D if ResourceLoader.exists(sprite_path) else null
			agent_icon.visible = agent_icon.texture != null
		var weapon_name := str(detail.get("weapon", ""))
		if weapon_icon:
			weapon_icon.texture = COMBAT_REPORT_WEAPON_ICONS.get(weapon_name) as Texture2D
			weapon_icon.visible = weapon_icon.texture != null

func _on_skirmish_combat_outcome_received(
	outcome: String,
	outgoing_damage: float,
	target_actor_id: int,
	target_life_id: int
) -> void:
	if not is_skirmish_mode or not ["KILL", "ASSIST"].has(outcome):
		return
	if outcome == "ASSIST" and outgoing_damage < 50.0:
		return
	_record_skirmish_combat_outcome(outcome, target_actor_id, target_life_id)

func _record_skirmish_combat_outcome(
	outcome: String,
	target_actor_id: int,
	target_life_id: int
) -> void:
	var outcome_key := _combat_outcome_key(target_actor_id, target_life_id)
	var previous_outcome := str(_skirmish_combat_outcomes.get(outcome_key, ""))
	if previous_outcome == "KILL" or (previous_outcome == "ASSIST" and outcome != "KILL"):
		return
	_skirmish_combat_outcomes[outcome_key] = outcome
	for row in _combat_report_rows:
		if (
			int(row.get_meta("combat_report_actor_id", -1)) == target_actor_id
			and int(row.get_meta("combat_report_life_id", -1)) == target_life_id
		):
			var outgoing_caption := row.get_node_or_null("Outgoing/Label") as Label
			if outgoing_caption:
				outgoing_caption.text = outcome
				outgoing_caption.visible = true

func _combat_outcome_key(actor_id: int, life_id: int) -> String:
	return "%d:%d" % [actor_id, life_id]

func _disable_skirmish_combat_report_details() -> void:
	for icon in _combat_report_agent_icons:
		icon.visible = false
	combat_report_weapon.visible = false
	combat_report_killer_icon.visible = false
	combat_report_murdered.visible = false

func _set_combat_report_agent_icons(icon_paths: Array, killer_sprite: Texture2D) -> void:
	var paths := icon_paths.duplicate()
	if killer_sprite and not killer_sprite.resource_path.is_empty() and not paths.has(killer_sprite.resource_path):
		paths.push_front(killer_sprite.resource_path)
	while _combat_report_agent_icons.size() < paths.size():
		var icon := combat_report_agent.duplicate() as TextureRect
		icon.name = "Agent%d" % (_combat_report_agent_icons.size() + 1)
		combat_report_agent.get_parent().add_child(icon)
		_combat_report_agent_icons.append(icon)
	for index in _combat_report_agent_icons.size():
		var icon := _combat_report_agent_icons[index]
		icon.visible = index < paths.size()
		if index >= paths.size():
			continue
		var sprite_path := str(paths[index])
		icon.texture = load(sprite_path) as Texture2D if ResourceLoader.exists(sprite_path) else null
		if paths.size() > 1:
			icon.anchor_left = 0.0
			icon.anchor_right = 0.0
			icon.anchor_top = 0.0
			icon.anchor_bottom = 0.0
			icon.offset_left = 63.0 + (index % 2) * 17.0
			icon.offset_right = icon.offset_left + 15.0
			icon.offset_top = 2.5 + floori(float(index) / 2.0) * 16.0
			icon.offset_bottom = icon.offset_top + 15.0

func _get_combat_damage_source_paths(victim: BaseAgent) -> Array:
	var paths: Array = []
	var current_scene := get_tree().current_scene
	if not current_scene:
		return paths
	for actor in current_scene.get_children():
		if not actor is BaseAgent:
			continue
		if victim.get_combat_damage_received_from(actor) <= 0.0:
			continue
		var sprite := _get_combat_actor_sprite(actor)
		if sprite and not sprite.resource_path.is_empty() and not paths.has(sprite.resource_path):
			paths.append(sprite.resource_path)
	return paths

func _get_combat_actor_name(actor: Node) -> String:
	if actor is BaseAgent and actor.is_ai_dummy:
		return str(actor.get("display_name"))
	if actor is BaseAgent:
		var peer_id := actor.get_multiplayer_authority()
		var player_name := NetworkManager.get_player_display_name(peer_id)
		if not player_name.is_empty() and player_name != "Player":
			return player_name
		if actor.agent_data:
			return actor.agent_data.agent_name.to_upper()
	return actor.name

func _get_combat_actor_sprite(actor: Node) -> Texture2D:
	if actor is BaseAgent and actor.agent_data:
		return actor.agent_data.agent_sprite
	return null

func _get_combat_actor_weapon_icon(actor: Node) -> Texture2D:
	var weapon: WeaponData
	if actor is BaseAgent and actor.is_ai_dummy:
		weapon = actor.get("current_weapon") as WeaponData
	elif actor is BaseAgent:
		var actor_weapon_controller: Node = actor.get("weapon_controller")
		if actor_weapon_controller:
			weapon = actor_weapon_controller.get("current_weapon") as WeaponData
	return weapon.ui_sprite if weapon else null
