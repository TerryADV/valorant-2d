extends RefCounted

var _hud: CanvasLayer
var _allies_container: VBoxContainer
var _enemies_container: VBoxContainer
var _ally_template: Control
var _enemy_template: Control
var _ally_rows: Array[Control] = []
var _enemy_rows: Array[Control] = []
var _ally_agent_icons: Array[TextureRect] = []
var _enemy_agent_icons: Array[TextureRect] = []
var _ally_health_bars: Array[TextureProgressBar] = []
var _ally_health_default_tints: Dictionary = {}
var _ally_agent_icon_container: HBoxContainer
var _enemy_agent_icon_container: HBoxContainer
var _ally_round_label: Label
var _enemy_round_label: Label
var _timer_label: Label
var _round_number := 0
var _team_round_wins := [0, 0]
var _round_is_preparation := false
var _round_seconds_remaining := 0.0
var _displayed_round_second := -1

const SHIELD_EMPTY_TEXTURE: Texture2D = preload("res://assets/sprites/ui/main/shield1off.png")
const SHIELD_TEXTURE: Texture2D = preload("res://assets/sprites/ui/guns/shieldLarge.png")

func setup(hud: CanvasLayer) -> void:
	_hud = hud
	_allies_container = hud.get_node("Control/Scoreboard/Skirmish/Allies") as VBoxContainer
	_enemies_container = hud.get_node("Control/Scoreboard/Skirmish/Enemies") as VBoxContainer
	_ally_template = _allies_container.get_node("Player") as Control
	_enemy_template = _enemies_container.get_node("Player") as Control
	_ally_rows.append(_ally_template)
	_enemy_rows.append(_enemy_template)
	_ally_round_label = hud.get_node("Control/Main/Top/Normal/AllysContainer/Round/Label") as Label
	_enemy_round_label = hud.get_node("Control/Main/Top/Normal/EnemyContainer/Round/Label") as Label
	_timer_label = hud.get_node("Control/Main/Top/Normal/Timer/Label") as Label
	_ally_agent_icon_container = hud.get_node(
		"Control/Main/Top/Normal/AllysContainer/AgentContainer/HBoxContainer"
	) as HBoxContainer
	_enemy_agent_icon_container = hud.get_node(
		"Control/Main/Top/Normal/EnemyContainer/AgentContainer/HBoxContainer"
	) as HBoxContainer
	_ally_agent_icons.append(_ally_agent_icon_container.get_node("Player1") as TextureRect)
	_enemy_agent_icons.append(_enemy_agent_icon_container.get_node("Player1") as TextureRect)
	_ally_health_bars.append(_ally_agent_icons[0].get_node("Health") as TextureProgressBar)
	_ally_health_default_tints[_ally_health_bars[0]] = _ally_health_bars[0].tint_progress
	_ensure_row_count(NetworkManager.skirmish_team_size)
	_ensure_agent_icon_count(NetworkManager.skirmish_team_size)

func show_round_state(round_number: int, is_preparation: bool, duration: float) -> void:
	_round_number = round_number
	_round_is_preparation = is_preparation
	_round_seconds_remaining = duration
	_displayed_round_second = -1
	_update_round_display()

func process_round_countdown(delta: float) -> void:
	if not _timer_label or _round_seconds_remaining <= 0.0:
		return
	_round_seconds_remaining = maxf(_round_seconds_remaining - delta, 0.0)
	var seconds := ceili(_round_seconds_remaining)
	if seconds != _displayed_round_second:
		_update_round_display()

func _update_round_display() -> void:
	if not _ally_round_label or not _enemy_round_label or not _timer_label:
		return
	_displayed_round_second = ceili(_round_seconds_remaining)
	var minutes: int = floori(float(_displayed_round_second) / 60.0)
	var seconds: int = _displayed_round_second % 60
	_ally_round_label.text = str(_team_round_wins[0])
	_enemy_round_label.text = str(_team_round_wins[1])
	_timer_label.text = "%02d:%02d" % [minutes, seconds]

func show_round_result(team_wins: Array) -> void:
	if team_wins.size() != 2:
		return
	_team_round_wins = [int(team_wins[0]), int(team_wins[1])]
	var player := _hud.get("player") as BaseAgent
	var ally_team := player.skirmish_team if player and player.skirmish_team >= 0 else 0
	var enemy_team := 1 - ally_team
	_ally_round_label.text = str(_team_round_wins[ally_team])
	_enemy_round_label.text = str(_team_round_wins[enemy_team])

func update_scoreboard() -> void:
	if not bool(_hud.get("is_skirmish_mode")) or not _hud.get("player"):
		return
	_ensure_row_count(NetworkManager.skirmish_team_size)
	var teams := _collect_team_players()
	var player := _hud.get("player") as BaseAgent
	var ally_team := player.skirmish_team
	var ally_players: Array = teams[ally_team] if ally_team >= 0 and ally_team < teams.size() else []
	var enemy_team := 1 - ally_team if ally_team >= 0 and ally_team <= 1 else 1
	var enemy_players: Array = teams[enemy_team]
	_update_team_agent_icons(ally_players, enemy_players)
	_update_team_rows(_ally_rows, ally_players, true)
	_update_team_rows(_enemy_rows, enemy_players, false)

func update_team_agent_icons() -> void:
	if not bool(_hud.get("is_skirmish_mode")) or not _hud.get("player"):
		return
	_ensure_agent_icon_count(NetworkManager.skirmish_team_size)
	var teams := _collect_team_players()
	var player := _hud.get("player") as BaseAgent
	var ally_team := player.skirmish_team
	var allies: Array = teams[ally_team] if ally_team >= 0 and ally_team < teams.size() else []
	var enemy_team := 1 - ally_team if ally_team >= 0 and ally_team <= 1 else 1
	_update_team_agent_icons(allies, teams[enemy_team])
	_update_ally_health_bars(allies)

func _ensure_agent_icon_count(required_count: int) -> void:
	var icon_count := clampi(required_count, 1, 2)
	while _ally_agent_icons.size() < icon_count:
		_ally_agent_icons.append(_duplicate_agent_icon(
			_ally_agent_icons[0], _ally_agent_icon_container, "Player%d" % (_ally_agent_icons.size() + 1)
		))
	while _enemy_agent_icons.size() < icon_count:
		_enemy_agent_icons.append(_duplicate_agent_icon(
			_enemy_agent_icons[0], _enemy_agent_icon_container, "Player%d" % (_enemy_agent_icons.size() + 1)
		))
	while _ally_health_bars.size() < icon_count:
		var icon := _ally_agent_icons[_ally_health_bars.size()]
		var health_bar := icon.get_node("Health") as TextureProgressBar
		_ally_health_bars.append(health_bar)
		_ally_health_default_tints[health_bar] = health_bar.tint_progress

func _duplicate_agent_icon(
	template: TextureRect,
	container: HBoxContainer,
	icon_name: String
) -> TextureRect:
	var icon := template.duplicate() as TextureRect
	icon.name = icon_name
	container.add_child(icon)
	return icon

func _update_team_agent_icons(allies: Array, enemies: Array) -> void:
	_update_agent_icon_row(_ally_agent_icons, allies)
	_update_agent_icon_row(_enemy_agent_icons, enemies)

func _update_agent_icon_row(icons: Array[TextureRect], actors: Array) -> void:
	for index in icons.size():
		var icon := icons[index]
		var actor: Node = actors[index] if index < actors.size() else null
		var actor_is_alive := actor != null and not _is_actor_dead(actor)
		icon.visible = actor_is_alive
		icon.texture = _get_agent_texture(actor) if actor_is_alive else null
		icon.modulate.a = 1.0
		_update_ultimate_indicators(icon, actor if actor_is_alive else null)

func _update_ally_health_bars(allies: Array) -> void:
	for index in _ally_health_bars.size():
		var health_bar := _ally_health_bars[index]
		var actor: Node = allies[index] if index < allies.size() else null
		if not health_bar:
			continue
		health_bar.visible = actor is BaseAgent and not _is_actor_dead(actor)
		if actor is BaseAgent:
			var health_component := actor.get("health_component") as HealthComponent
			if health_component:
				health_bar.max_value = health_component.max_health
				health_bar.value = health_component.current_health
				var default_tint: Color = _ally_health_default_tints.get(health_bar, Color.WHITE)
				if _is_actor_healing(actor):
					health_bar.tint_progress = Color("22ffc5", default_tint.a)
				elif health_component.max_health > 0.0 and health_component.current_health / health_component.max_health < 0.25:
					health_bar.tint_progress = Color("f05c56", default_tint.a)
				else:
					health_bar.tint_progress = default_tint

func _update_ultimate_indicators(icon: TextureRect, actor: Node) -> void:
	var inactive_icon := icon.get_node_or_null("UltimateInactive") as TextureRect
	var active_icon := icon.get_node_or_null("UltimateActive") as TextureRect
	if not inactive_icon or not active_icon:
		return
	var ultimate_active := false
	var ultimate_ready := false
	if actor is BaseAgent:
		ultimate_ready = actor.has_ultimate_charge()
		var components := actor.get_node_or_null("Components")
		if components:
			for component in components.get_children():
				if component.has_method("is_ultimate_active") and component.call("is_ultimate_active"):
					ultimate_active = true
					break
	active_icon.visible = ultimate_active
	inactive_icon.visible = ultimate_ready and not ultimate_active

func _is_actor_healing(actor: BaseAgent) -> bool:
	var incoming_statuses: Dictionary = actor.get("incoming_healing_statuses")
	if not incoming_statuses.is_empty():
		return true
	var current_scene := _hud.get_tree().current_scene
	if not current_scene:
		return false
	for candidate in current_scene.get_children():
		if not candidate is BaseAgent:
			continue
		var components := candidate.get_node_or_null("Components")
		if not components:
			continue
		for component in components.get_children():
			if not _has_property(component, "healing_effects"):
				continue
			var effects: Dictionary = component.get("healing_effects")
			for effect in effects.values():
				if _healing_effect_targets_actor(candidate, effect, actor):
					return true
	if actor.has_local_authority():
		var local_healing_states: Dictionary = _hud.get("healing_state_entries")
		return not local_healing_states.is_empty()
	return false

func _healing_effect_targets_actor(
	healer: BaseAgent,
	effect: Dictionary,
	target: BaseAgent
) -> bool:
	var target_peer_id := int(effect.get("target_peer_id", -1))
	if target_peer_id > 0:
		return target_peer_id == target.get_multiplayer_authority()
	if target_peer_id < 0:
		return target == NetworkManager.call("find_deathmatch_actor", target_peer_id)
	return target == healer

func _has_property(object: Object, property_name: String) -> bool:
	for property_info in object.get_property_list():
		if String(property_info.get("name", "")) == property_name:
			return true
	return false

func _ensure_row_count(required_count: int) -> void:
	var row_count := clampi(required_count, 1, 2)
	while _ally_rows.size() < row_count:
		_ally_rows.append(_duplicate_row(_ally_template, _allies_container, "Player%d" % (_ally_rows.size() + 1)))
	while _enemy_rows.size() < row_count:
		_enemy_rows.append(_duplicate_row(_enemy_template, _enemies_container, "Player%d" % (_enemy_rows.size() + 1)))
	for index in _ally_rows.size():
		_ally_rows[index].visible = index < row_count
	for index in _enemy_rows.size():
		_enemy_rows[index].visible = index < row_count

func _duplicate_row(template: Control, container: VBoxContainer, row_name: String) -> Control:
	var row := template.duplicate() as Control
	row.name = row_name
	container.add_child(row)
	return row

func _collect_team_players() -> Array:
	var teams: Array = [[], []]
	var current_scene := _hud.get_tree().current_scene
	if not current_scene:
		return teams
	for actor in current_scene.get_children():
		if not actor is BaseAgent:
			continue
		if actor is BaseAgent and not actor.is_ai_dummy and not (actor.visible or actor.is_dead):
			continue
		if actor is BaseAgent and actor.is_ai_dummy and not actor.is_in_match:
			continue
		var team := int(actor.get("skirmish_team"))
		if team >= 0 and team < teams.size():
			teams[team].append(actor)
	for team_players in teams:
		team_players.sort_custom(func(first: Node, second: Node) -> bool:
			if first == second:
				return false
			var local_player := _hud.get("player") as BaseAgent
			if local_player:
				if first == local_player:
					return true
				if second == local_player:
					return false
			if (first is BaseAgent) != (second is BaseAgent):
				return first is BaseAgent
			return NetworkManager.get_deathmatch_actor_id(first) < NetworkManager.get_deathmatch_actor_id(second)
		)
	return teams

func _update_team_rows(rows: Array[Control], actors: Array, show_weapons: bool) -> void:
	for index in rows.size():
		var actor: Node = actors[index] if index < actors.size() else null
		_update_row(rows[index], actor, show_weapons)

func _update_row(row: Control, actor: Node, show_weapon: bool) -> void:
	row.visible = actor != null
	if not actor:
		return
	var actor_id := NetworkManager.get_deathmatch_actor_id(actor)
	var agent_texture := _get_agent_texture(actor)
	var weapon := _get_weapon(actor)
	var name_label := row.get_node_or_null("Name") as Label
	var agent_icon := row.get_node_or_null("Agent") as TextureRect
	var ultimate_label := row.get_node_or_null("Ult") as Label
	var kills_label := row.get_node_or_null("KDA/Kill") as Label
	var deaths_label := row.get_node_or_null("KDA/Dead") as Label
	var assists_label := row.get_node_or_null("KDA/Assits") as Label
	var weapon_icon := row.get_node_or_null("Weapon") as TextureRect
	var shield_icon := row.get_node_or_null("Shield") as TextureRect
	var credits_label := row.get_node_or_null("Creds/Label") as Label
	var ping_label := row.get_node_or_null("Ping") as Label
	var background := row.get_node_or_null("Background") as TextureRect
	if name_label:
		name_label.text = _get_actor_name(actor, actor_id)
	if agent_icon:
		agent_icon.texture = agent_texture
		agent_icon.visible = agent_texture != null
	if ultimate_label:
		ultimate_label.text = _get_ultimate_text(actor)
	if kills_label:
		kills_label.text = str(int(NetworkManager.deathmatch_scores.get(actor_id, 0)))
	if deaths_label:
		deaths_label.text = str(int(NetworkManager.deathmatch_deaths.get(actor_id, 0)))
	if assists_label:
		assists_label.text = "--"
	if weapon_icon:
		weapon_icon.texture = weapon.ui_sprite if show_weapon and weapon else null
		weapon_icon.visible = show_weapon and weapon_icon.texture != null
	if shield_icon:
		var shield: float = actor.get_current_shield() if actor is BaseAgent else 0.0
		shield_icon.texture = SHIELD_TEXTURE if shield > 0.0 else SHIELD_EMPTY_TEXTURE
	if credits_label:
		credits_label.text = str(actor.credits_component.current_credits) if actor is BaseAgent else "--"
	if ping_label:
		var ping := _get_peer_ping(actor_id) if actor_id > 0 else -1
		ping_label.text = str(ping) if ping >= 0 else "--"
	if background:
		background.modulate.a = 0.55 if _is_actor_dead(actor) else 1.0

func _get_actor_name(actor: Node, actor_id: int) -> String:
	if actor is BaseAgent and actor.is_ai_dummy:
		return actor.display_name
	return NetworkManager.get_player_display_name(actor_id)

func _get_agent_texture(actor: Node) -> Texture2D:
	if actor is BaseAgent:
		return actor.agent_data.agent_sprite if actor.agent_data else null
	return null

func _get_weapon(actor: Node) -> WeaponData:
	if actor is BaseAgent:
		if actor.is_ai_dummy:
			var displayed_weapon := _dummy_displayed_weapon(actor)
			return displayed_weapon if displayed_weapon else actor.current_weapon
		return actor.weapon_controller.current_weapon
	return null

func _dummy_displayed_weapon(dummy: BaseAgent) -> WeaponData:
	var weapon_sprite := dummy.weapon_sprite as Sprite2D
	if not weapon_sprite or not weapon_sprite.texture:
		return null
	for weapon in BaseAgent.AVAILABLE_WEAPONS:
		if weapon.weapon_sprite == weapon_sprite.texture:
			return weapon
	return null

func _get_ultimate_text(actor: Node) -> String:
	if not actor is BaseAgent:
		return "--"
	var charges: Node = actor.get("ability_charges")
	if not charges or not charges.has_method("get_charge_state"):
		return "--"
	var charge_state: Dictionary = charges.call("get_charge_state")
	return "%d / 7" % int(charge_state.get("ultimate", 0))

func _is_actor_dead(actor: Node) -> bool:
	return bool(actor.get("is_dead"))

func _get_peer_ping(peer_id: int) -> int:
	var multiplayer_api := _hud.get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer():
		return -1
	if peer_id == 1:
		return 0
	var measured_peer_id := peer_id
	if peer_id == multiplayer_api.get_unique_id():
		measured_peer_id = 1
	var network_peer := multiplayer_api.multiplayer_peer
	if (
		not network_peer is ENetMultiplayerPeer
		or not multiplayer_api.get_peers().has(measured_peer_id)
	):
		return -1
	var enet_peer: ENetPacketPeer = network_peer.get_peer(measured_peer_id)
	if not enet_peer or enet_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return -1
	var round_trip_time := enet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
	if round_trip_time <= 0.0:
		return -1
	return maxi(roundi(round_trip_time), 1)
