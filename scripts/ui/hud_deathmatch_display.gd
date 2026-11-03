extends RefCounted

var _hud: CanvasLayer
var deathmatch_scores: Dictionary = {}
var deathmatch_deaths: Dictionary = {}
var kill_streaks: Dictionary = {}
var scoreboard_rows: Array[Control] = []
var scoreboard_background_alphas: Dictionary = {}

var player: BaseAgent:
	get:
		return _hud.get("player") as BaseAgent
var is_deathmatch_mode: bool:
	get:
		return bool(_hud.get("is_deathmatch_mode"))
var deathmatch_kill_target: int:
	get:
		return int(_hud.get("deathmatch_kill_target"))
	set(value):
		_hud.set("deathmatch_kill_target", value)
var scoreboard_rows_container: VBoxContainer:
	get:
		return _hud.get("scoreboard_rows_container") as VBoxContainer
var scoreboard_row_template: Control:
	get:
		return _hud.get("scoreboard_row_template") as Control
var kills_list: VBoxContainer:
	get:
		return _hud.get("kills_list") as VBoxContainer
var kill_entry_template: Control:
	get:
		return _hud.get("kill_entry_template") as Control
var first_deathmatch_players: HBoxContainer:
	get:
		return _hud.get("first_deathmatch_players") as HBoxContainer
var last_deathmatch_players: HBoxContainer:
	get:
		return _hud.get("last_deathmatch_players") as HBoxContainer

const SHIELD_EMPTY_TEXTURE: Texture2D = preload("res://assets/sprites/ui/main/shield1off.png")
const SCOREBOARD_SHIELD_TEXTURE: Texture2D = preload("res://assets/sprites/ui/guns/shieldLarge.png")
const SCOREBOARD_ALLY_BACKGROUND: Texture2D = preload("res://assets/sprites/ui/scoreboard/backgroundAlly.png")
const SCOREBOARD_ENEMY_BACKGROUND: Texture2D = preload("res://assets/sprites/ui/scoreboard/backgroundEnemy.png")
const CHARACTER_CONTAINER_TEXTURE: Texture2D = preload("res://assets/sprites/ui/main/Deathmach/characterContainer.png")
const ENEMY_CONTAINER_TEXTURE: Texture2D = preload("res://assets/sprites/ui/main/Deathmach/characterContainerEnemy.png")
const PLAYER_BAR_TEXTURE: Texture2D = preload("res://assets/sprites/ui/main/Deathmach/playerBar.png")
const ENEMY_BAR_TEXTURE: Texture2D = preload("res://assets/sprites/ui/main/Deathmach/enemyBar.png")
const BEST_TEXTURE: Texture2D = preload("res://assets/sprites/ui/main/Deathmach/bestPlayers.png")
const LOCAL_KILL_BACKGROUND: Texture2D = preload("res://assets/sprites/ui/main/Deathmach/backgroundKillEnemy.png")
const OTHER_PLAYERS_KILL_BACKGROUND: Texture2D = preload("res://assets/sprites/ui/main/Deathmach/backgroundEnemyEnemy.png")
const LOCAL_DEATH_BACKGROUND: Texture2D = preload("res://assets/sprites/ui/main/Deathmach/backgroundEnemyKill.png")
const STREAK_TEXTURE: Texture2D = preload("res://assets/sprites/ui/main/Deathmach/streak.png")
const STREAK_ENEMY_TEXTURE: Texture2D = preload("res://assets/sprites/ui/main/Deathmach/streakEnemy.png")
const WEAPON_UI_TEXTURES: Dictionary = {
	"Classic": preload("res://assets/sprites/ui/guns/classic.png"),
	"Vandal": preload("res://assets/sprites/ui/guns/vandal.png"),
	"Knife": preload("res://assets/sprites/ui/guns/knife.png"),
	"Spectre": preload("res://assets/sprites/ui/guns/spectre.png"),
	"Judge": preload("res://assets/sprites/ui/guns/judge.png"),
	"Operator": preload("res://assets/sprites/ui/guns/operator.png"),
	"Odin": preload("res://assets/sprites/ui/guns/odin.png"),
}

func setup(hud: CanvasLayer) -> void:
	_hud = hud

func sync_scores_from_network() -> void:
	deathmatch_scores = NetworkManager.deathmatch_scores.duplicate(true)
	deathmatch_deaths = NetworkManager.deathmatch_deaths.duplicate(true)

func _get_ability_icon(ability_name: String) -> Texture2D:
	return _hud.call("_get_ability_icon", ability_name) as Texture2D

func get_tree() -> SceneTree:
	return _hud.get_tree()

func create_tween() -> Tween:
	return _hud.create_tween()
func on_scores_updated(scores: Dictionary, deaths: Dictionary) -> void:
	deathmatch_scores = scores.duplicate(true)
	deathmatch_deaths = deaths.duplicate(true)
	update_deathmatch_hud()
	update_scoreboard()

func prepare_kill_feed() -> void:
	if not kills_list or not kill_entry_template:
		return
	for child in kills_list.get_children():
		if child != kill_entry_template:
			kills_list.remove_child(child)
			child.free()
	kill_entry_template.visible = false

func show_kill_feed(killer_peer_id: int, victim_peer_id: int, weapon_name: String = "") -> void:
	if not kills_list or not kill_entry_template:
		return
	var killer := NetworkManager.find_deathmatch_actor(killer_peer_id)
	var victim := NetworkManager.find_deathmatch_actor(victim_peer_id)
	var is_local_killer: bool = player and killer == player
	var is_local_victim: bool = player and victim == player

	var streak: int = int(kill_streaks.get(killer_peer_id, 0)) + 1
	kill_streaks[killer_peer_id] = streak
	kill_streaks.erase(victim_peer_id)

	var entry := kill_entry_template.duplicate() as Control
	entry.name = "Kill" if is_local_killer else "KillEnemy"
	entry.custom_minimum_size = Vector2(180.0, 18.0)
	entry.modulate.a = 0.0
	entry.visible = true
	kills_list.add_child(entry)

	var background := entry.get_node_or_null("Bakcground") as TextureRect
	var killer_icon := entry.get_node_or_null("Bakcground/Killer") as TextureRect
	var killer_label := entry.get_node_or_null("Bakcground/Killer/Label") as Label
	var victim_icon := entry.get_node_or_null("Bakcground/Dead") as TextureRect
	var victim_label := entry.get_node_or_null("Bakcground/Dead/Label") as Label
	var weapon_icon := entry.get_node_or_null("Bakcground/Weapon") as TextureRect
	var streak_icon := entry.get_node_or_null("Bakcground/Streak") as TextureRect
	var streak_label := entry.get_node_or_null("Bakcground/Streak/Label") as Label

	if background:
		background.texture = LOCAL_KILL_BACKGROUND if is_local_killer else (LOCAL_DEATH_BACKGROUND if is_local_victim else OTHER_PLAYERS_KILL_BACKGROUND)
	if killer:
		_set_kill_feed_agent(killer_icon, killer_label, killer)
	if victim:
		_set_kill_feed_agent(victim_icon, victim_label, victim)
	if weapon_icon:
		weapon_icon.texture = WEAPON_UI_TEXTURES.get(
			weapon_name,
			_get_ability_icon(weapon_name)
		)
		weapon_icon.visible = weapon_name != "" and weapon_icon.texture != null
	if streak_icon:
		streak_icon.visible = streak >= 3
		streak_icon.z_index = 2
		streak_icon.texture = STREAK_TEXTURE if is_local_killer else STREAK_ENEMY_TEXTURE
	if streak_label:
		streak_label.visible = streak >= 3
		streak_label.text = _to_roman(streak)

	var entrance := create_tween()
	entrance.tween_property(entry, "modulate:a", 1.0, 0.18)
	entrance.tween_interval(5.0)
	entrance.tween_property(entry, "modulate:a", 0.0, 0.25)
	entrance.tween_callback(entry.queue_free)

	while kills_list.get_child_count() > 5:
		var oldest := kills_list.get_child(0)
		if oldest != kill_entry_template:
			oldest.queue_free()
		else:
			break

func _set_kill_feed_agent(icon: TextureRect, label: Label, agent: Node) -> void:
	if icon:
		icon.texture = _participant_sprite(agent)
	if label:
		label.text = _participant_name(agent, _participant_id(agent))

func _to_roman(value: int) -> String:
	var numerals := [
		[1000, "M"], [900, "CM"], [500, "D"], [400, "CD"],
		[100, "C"], [90, "XC"], [50, "L"], [40, "XL"],
		[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"],
	]
	var number := maxi(value, 1)
	var result := ""
	for numeral in numerals:
		while number >= numeral[0]:
			result += numeral[1]
			number -= numeral[0]
	return result

func _agent_name(agent: Node, peer_id: int) -> String:
	if agent is BaseAgent and agent.is_ai_dummy:
		return agent.display_name
	return NetworkManager.get_player_display_name(peer_id)

func _participant_id(participant: Node) -> int:
	return NetworkManager.get_deathmatch_actor_id(participant)

func _participant_name(participant: Node, participant_id: int) -> String:
	return _agent_name(participant, participant_id)

func _participant_sprite(participant: Node) -> Texture2D:
	if participant is BaseAgent:
		return participant.agent_data.agent_sprite if participant.agent_data else null
	return null

func _participant_weapon(participant: Node) -> WeaponData:
	if participant is BaseAgent:
		if participant.is_ai_dummy:
			var displayed_weapon := _dummy_displayed_weapon(participant)
			return displayed_weapon if displayed_weapon else participant.current_weapon
		return participant.weapon_controller.current_weapon
	return null

func _dummy_displayed_weapon(dummy: BaseAgent) -> WeaponData:
	var weapon_sprite := dummy.weapon_sprite as Sprite2D
	if not weapon_sprite or not weapon_sprite.texture:
		return null
	for weapon in BaseAgent.AVAILABLE_WEAPONS:
		if weapon.weapon_sprite == weapon_sprite.texture:
			return weapon
	return null

func _participant_is_dead(participant: Node) -> bool:
	if participant is BaseAgent:
		return participant.is_dead
	return false

func set_deathmatch_kills(kills: int, target: int = -1) -> void:
	if not player:
		return
	set_deathmatch_score(player.get_multiplayer_authority(), kills, target)

func set_deathmatch_score(peer_id: int, kills: int, target: int = -1) -> void:
	deathmatch_scores[peer_id] = maxi(kills, 0)
	if target > 0:
		deathmatch_kill_target = target
	update_deathmatch_hud()
	update_scoreboard()

func prepare_deathmatch_cards() -> void:
	_prepare_deathmatch_row(first_deathmatch_players)
	_prepare_deathmatch_row(last_deathmatch_players)

func update_deathmatch_hud() -> void:
	if not player or not first_deathmatch_players or not last_deathmatch_players:
		return

	var agents: Array[Node] = _get_sorted_agents()
	_update_deathmatch_row(first_deathmatch_players, agents, 0)
	_update_deathmatch_row(last_deathmatch_players, agents, 6)

func _get_sorted_agents() -> Array[Node]:
	var agents: Array[Node] = []
	for child in get_tree().current_scene.get_children():
		if child is BaseAgent and not child.is_ai_dummy and (child.visible or child.is_dead):
			agents.append(child)
		elif child is BaseAgent and child.is_ai_dummy and child.is_in_match:
			agents.append(child)
	agents.sort_custom(func(first: Node, second: Node) -> bool:
		var first_id := _participant_id(first)
		var second_id := _participant_id(second)
		var first_score: int = int(deathmatch_scores.get(first_id, 0))
		var second_score: int = int(deathmatch_scores.get(second_id, 0))
		if first_score == second_score:
			if (first as BaseAgent).is_ai_dummy != (second as BaseAgent).is_ai_dummy:
				return not (first as BaseAgent).is_ai_dummy
			return first_id < second_id
		return first_score > second_score
	)
	return agents

func prepare_scoreboard_rows() -> void:
	if not scoreboard_rows_container or not scoreboard_row_template:
		push_error("Deathmatch scoreboard is missing its player row template.")
		return

	scoreboard_rows.append(scoreboard_row_template)
	for row_index in range(1, NetworkManager.MAX_DEATHMATCH_PARTICIPANTS):
		var row := scoreboard_row_template.duplicate() as Control
		row.name = "Player%d" % (row_index + 1)
		scoreboard_rows_container.add_child(row)
		scoreboard_rows.append(row)

func update_scoreboard() -> void:
	if not is_deathmatch_mode or not player or scoreboard_rows.is_empty():
		return

	var agents := _get_sorted_agents()
	while scoreboard_rows.size() < agents.size():
		var row := scoreboard_row_template.duplicate() as Control
		row.name = "Player%d" % (scoreboard_rows.size() + 1)
		scoreboard_rows_container.add_child(row)
		scoreboard_rows.append(row)
	for row_index in scoreboard_rows.size():
		var agent: Node = agents[row_index] if row_index < agents.size() else null
		_update_scoreboard_row(scoreboard_rows[row_index], agent)

func _update_scoreboard_row(row: Control, agent: Node) -> void:
	row.visible = agent != null
	if not agent:
		return

	var peer_id := _participant_id(agent)
	var name_label := row.get_node_or_null("Name") as Label
	var ultimate_label := row.get_node_or_null("Ult") as Label
	var kills_label := row.get_node_or_null("KDA/Kill") as Label
	var deaths_label := row.get_node_or_null("KDA/Dead") as Label
	var assists_label := row.get_node_or_null("KDA/Assits") as Label
	var background := row.get_node_or_null("Background") as TextureRect
	var weapon_icon := row.get_node_or_null("Weapon") as TextureRect
	var row_shield_icon := row.get_node_or_null("Shield") as TextureRect
	var credits_label := row.get_node_or_null("Creds/Label") as Label
	var ping_label := row.get_node_or_null("Ping") as Label

	if name_label:
		name_label.text = _agent_name(agent, peer_id)
	if ultimate_label:
		ultimate_label.text = "--"
	if kills_label:
		kills_label.text = str(int(deathmatch_scores.get(peer_id, 0)))
	if deaths_label:
		deaths_label.text = str(int(deathmatch_deaths.get(peer_id, 0)))
	if assists_label:
		assists_label.text = "--"
	if background:
		var background_id: int = background.get_instance_id()
		if not scoreboard_background_alphas.has(background_id):
			scoreboard_background_alphas[background_id] = background.modulate.a
		background.texture = (
			SCOREBOARD_ALLY_BACKGROUND
			if agent == player
			else SCOREBOARD_ENEMY_BACKGROUND
		)
		var base_alpha: float = scoreboard_background_alphas[background_id]
		background.modulate.a = base_alpha * (
			0.6 if _participant_is_dead(agent) and agent != player else 1.0
		)
	if weapon_icon:
		var weapon := _participant_weapon(agent)
		weapon_icon.texture = weapon.ui_sprite if weapon else null
		weapon_icon.visible = weapon_icon.texture != null
	if row_shield_icon:
		var shield: float = agent.get_current_shield() if agent is BaseAgent else 0.0
		row_shield_icon.texture = (
			SCOREBOARD_SHIELD_TEXTURE
			if shield > 0.0
			else SHIELD_EMPTY_TEXTURE
		)
	if credits_label:
		credits_label.text = (
			str(agent.credits_component.current_credits)
			if agent is BaseAgent
			else "--"
		)
	if ping_label:
		var ping: int = _get_peer_ping(peer_id) if peer_id > 0 else -1
		ping_label.text = str(ping) if ping >= 0 else "--"

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

func _prepare_deathmatch_row(row: HBoxContainer) -> void:
	if not row:
		return
	var template := row.get_node_or_null("Player") as Control
	if not template:
		return
	for child in row.get_children():
		if child != template:
			row.remove_child(child)
			child.free()
	for index in range(1, 6):
		var card := template.duplicate() as Control
		card.name = "Player%d" % (index + 1)
		row.add_child(card)

func _update_deathmatch_row(row: HBoxContainer, agents: Array[Node], start_index: int) -> void:
	for row_index in row.get_child_count():
		var card := row.get_child(row_index) as Control
		var global_index: int = start_index + row_index
		var agent: Node = agents[global_index] if global_index < agents.size() else null
		card.visible = agent != null
		if not agent:
			continue

		var is_local_player: bool = agent == player
		var background := card.get_node_or_null("CharacterContainer") as TextureRect
		if not background:
			background = card.get_node_or_null("Background") as TextureRect
		var agent_icon := card.get_node_or_null("Agent") as TextureRect
		var kill_label := card.get_node_or_null("Kill") as Label
		var best_icon := card.get_node_or_null("Best") as TextureRect
		var progress := card.get_node_or_null("TextureProgressBar") as TextureProgressBar
		if not progress:
			progress = card.get_node_or_null("KillProgress") as TextureProgressBar

		if background:
			background.texture = CHARACTER_CONTAINER_TEXTURE if is_local_player else ENEMY_CONTAINER_TEXTURE
		if agent_icon:
			agent_icon.texture = _participant_sprite(agent)
			agent_icon.flip_h = false
			agent_icon.rotation = 0.0

		var kills: int = int(deathmatch_scores.get(_participant_id(agent), 0))
		if kill_label:
			kill_label.text = str(kills)
		if best_icon:
			best_icon.texture = BEST_TEXTURE
			best_icon.visible = global_index < 3
		if progress:
			progress.max_value = maxi(deathmatch_kill_target, 1)
			progress.value = clampi(kills, 0, deathmatch_kill_target)
			progress.texture_progress = PLAYER_BAR_TEXTURE if is_local_player else ENEMY_BAR_TEXTURE

