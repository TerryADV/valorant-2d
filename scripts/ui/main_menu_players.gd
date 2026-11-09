extends Control

const ADD_PLAYER_TEXTURE: Texture2D = preload("res://assets/ui/main/custom/invite_player.png")
const REMOVE_PLAYER_TEXTURE: Texture2D = preload("res://assets/ui/main/custom/remove_player.png")
const REFRESH_INTERVAL := 0.25

@onready var attackers_container: Control = $Positions/Attackers
@onready var defenders_container: Control = $Positions/Defenders
@onready var observers_container: Control = $Positions/Observers
@onready var positions_container: Control = $Positions
@onready var ip_label: Label = $IP
@onready var room_players_label: Label = $Players
@onready var dummy_difficulty_option: OptionButton = $Dificulty
@onready var fill_button: Button = $Fill

var _refresh_elapsed := REFRESH_INTERVAL
var _normal_textures: Dictionary = {}
var _original_slot_disabled: Dictionary = {}
var _original_change_visibility: Dictionary = {}
var _pending_team := -2
var _pending_slot_index := -1

func _ready() -> void:
	_set_mouse_filter_recursive(positions_container)
	NetworkManager.connected.connect(_on_network_connected)
	NetworkManager.connection_failed.connect(_clear_pending_position)
	NetworkManager.room_mode_mismatch.connect(_clear_pending_position)
	NetworkManager.skirmish_teams_changed.connect(_on_skirmish_teams_changed)
	NetworkManager.skirmish_dummy_slots_changed.connect(_on_skirmish_dummy_slots_changed)
	NetworkManager.lobby_players_updated.connect(_on_lobby_players_updated)
	fill_button.pressed.connect(_on_fill_pressed)
	for container in [attackers_container, defenders_container, observers_container]:
		for slot in _get_slots(container):
			_normal_textures[slot] = slot.texture_normal
			_original_slot_disabled[slot] = slot.disabled
			var change_indicator := slot.get_node_or_null("Change") as CanvasItem
			if change_indicator:
				_original_change_visibility[change_indicator] = change_indicator.visible
			var slot_index := _get_slots(container).find(slot)
			var team := 0 if container == attackers_container else (1 if container == defenders_container else -1)
			var add_button := slot.get_node_or_null("Add") as TextureButton
			if add_button and team >= 0:
				add_button.mouse_filter = Control.MOUSE_FILTER_STOP
				add_button.z_index = 2
				add_button.pressed.connect(_on_dummy_add_pressed.bind(team, slot_index))
	dummy_difficulty_option.mouse_filter = Control.MOUSE_FILTER_STOP
	dummy_difficulty_option.item_selected.connect(_on_dummy_difficulty_selected)
	_refresh_player_slots()
	_update_room_display()
	_update_dummy_difficulty()
	_update_skirmish_slot_availability()

func _set_mouse_filter_recursive(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_set_mouse_filter_recursive(child as Control)

func _process(delta: float) -> void:
	_process_hover_state()
	_refresh_elapsed += delta
	if _refresh_elapsed < REFRESH_INTERVAL:
		return
	_refresh_elapsed = 0.0
	_refresh_player_slots()
	_update_room_display()
	_update_dummy_difficulty()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	var pointer_position := get_global_mouse_position()
	if dummy_difficulty_option.visible and dummy_difficulty_option.get_global_rect().has_point(pointer_position):
		return
	for team_data in [
		{"container": attackers_container, "team": 0},
		{"container": defenders_container, "team": 1},
	]:
		var team := int(team_data["team"])
		var team_slots := _get_slots(team_data["container"] as Control)
		for slot_index in team_slots.size():
			var add_button := team_slots[slot_index].get_node_or_null("Add") as TextureButton
			if (
				not add_button
				or not add_button.visible
				or not Rect2(Vector2.ZERO, add_button.size).has_point(add_button.get_local_mouse_position())
			):
				continue
			if not add_button.disabled:
				_on_dummy_add_pressed(team, slot_index)
			get_viewport().set_input_as_handled()
			return
	for team_data in [
		{"container": attackers_container, "team": 0},
		{"container": defenders_container, "team": 1},
		{"container": observers_container, "team": -1},
	]:
		var team_container: Control = team_data["container"]
		var team := int(team_data["team"])
		var slots := _get_slots(team_container)
		for slot_index in slots.size():
			if _is_skirmish_slot_locked(team, slot_index):
				continue
			if not slots[slot_index].get_global_rect().has_point(pointer_position):
				continue
			_assign_local_player(team, slot_index)
			get_viewport().set_input_as_handled()
			return

func _on_dummy_add_pressed(team: int, slot_index: int) -> void:
	if NetworkManager.match_started:
		return
	if _is_local_player_at_position(team, slot_index):
		NetworkManager.clear_local_skirmish_position()
		_refresh_player_slots()
		return
	if not _can_manage_dummy_slots() or _slot_has_player(team, slot_index):
		return
	var dummy_slots: Dictionary = NetworkManager.skirmish_dummy_slots
	var slot_key := _dummy_slot_key(team, slot_index)
	NetworkManager.set_skirmish_dummy_slot(team, slot_index, not dummy_slots.has(slot_key))
	_refresh_player_slots()

func _on_fill_pressed() -> void:
	if not _can_manage_dummy_slots() or NetworkManager.match_started:
		return
	NetworkManager.fill_room_with_dummies()
	_refresh_player_slots()

func _assign_local_player(team: int, slot_index: int) -> void:
	if NetworkManager.is_networked():
		if NetworkManager.connection_pending:
			_pending_team = team
			_pending_slot_index = slot_index
			return
		NetworkManager.set_local_skirmish_position(team, slot_index)
		return
	var local_peer_id := _get_local_peer_id()
	if (
		_is_skirmish_room()
		and team >= 0
		and NetworkManager.skirmish_dummy_slots.has(_dummy_slot_key(team, slot_index))
	):
		return
	for assigned_peer_id in NetworkManager.skirmish_position_assignments:
		if int(assigned_peer_id) == local_peer_id:
			continue
		if (
			int(NetworkManager.skirmish_team_assignments.get(assigned_peer_id, -1)) == team
			and int(NetworkManager.skirmish_position_assignments[assigned_peer_id]) == slot_index
		):
			return
	NetworkManager.skirmish_team_assignments[local_peer_id] = team
	NetworkManager.skirmish_position_assignments[local_peer_id] = slot_index
	_refresh_player_slots()

func _on_network_connected() -> void:
	if _pending_team == -2 or _pending_slot_index < 0:
		return
	NetworkManager.set_local_skirmish_position(_pending_team, _pending_slot_index)
	_clear_pending_position()

func _clear_pending_position(_unused_argument = null) -> void:
	_pending_team = -2
	_pending_slot_index = -1

func _process_hover_state() -> void:
	var mouse_position := get_global_mouse_position()
	for container in [attackers_container, defenders_container, observers_container]:
		for slot in _get_slots(container):
			if slot.disabled:
				continue
			var normal_texture: Texture2D = _normal_textures.get(slot)
			var hovered := slot.get_global_rect().has_point(mouse_position)
			slot.texture_normal = slot.texture_hover if hovered else normal_texture

func _on_skirmish_teams_changed(_team_assignments: Dictionary) -> void:
	_refresh_player_slots()

func _on_skirmish_dummy_slots_changed(_dummy_slots: Dictionary) -> void:
	_refresh_player_slots()

func _on_lobby_players_updated(_player_names: Dictionary) -> void:
	_refresh_player_slots()

func _refresh_player_slots() -> void:
	_update_skirmish_slot_availability()
	var slots_by_team := {
		"Attackers": _get_slots(attackers_container),
		"Defenders": _get_slots(defenders_container),
		"Observers": _get_slots(observers_container),
	}
	_clear_slots(slots_by_team)

	var peer_ids := _get_room_peer_ids()
	var assignments: Dictionary = NetworkManager.skirmish_team_assignments
	var peer_ids_by_team := {
		"Attackers": [],
		"Defenders": [],
		"Observers": [],
	}
	for peer_id in peer_ids:
		var team := int(assignments.get(peer_id, -1))
		var team_name := "Observers"
		if team == 0:
			team_name = "Attackers"
		elif team == 1:
			team_name = "Defenders"
		peer_ids_by_team[team_name].append(peer_id)

	var position_assignments: Dictionary = NetworkManager.skirmish_position_assignments
	for team_name in peer_ids_by_team:
		var team_slots: Array[TextureButton] = slots_by_team[team_name]
		for peer_id_value in peer_ids_by_team[team_name]:
			var peer_id := int(peer_id_value)
			var slot_index := int(position_assignments.get(peer_id, -1))
			if slot_index >= 0 and slot_index < team_slots.size():
				_update_slot(team_slots[slot_index], peer_id)
	var dummy_slots: Dictionary = NetworkManager.skirmish_dummy_slots
	for team_data in [
		{"container": attackers_container, "team": 0},
		{"container": defenders_container, "team": 1},
	]:
		var team := int(team_data["team"])
		var team_slots := _get_slots(team_data["container"] as Control)
		for slot_index in team_slots.size():
			var dummy_name := str(dummy_slots.get(_dummy_slot_key(team, slot_index), ""))
			if not dummy_name.is_empty() and not _slot_has_player(team, slot_index):
				_update_dummy_slot(team_slots[slot_index], dummy_name)
	_update_dummy_add_buttons()

func _get_room_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = [1]
	var multiplayer_api := get_tree().get_multiplayer()
	if multiplayer_api.has_multiplayer_peer():
		for peer_id_value in multiplayer_api.get_peers():
			var peer_id := int(peer_id_value)
			if not peer_ids.has(peer_id):
				peer_ids.append(peer_id)
		if not multiplayer_api.is_server() and not NetworkManager.connection_pending:
			var local_peer_id := _get_local_peer_id()
			if not peer_ids.has(local_peer_id):
				peer_ids.append(local_peer_id)
	peer_ids.sort()
	return peer_ids

func _get_slots(container: Control) -> Array[TextureButton]:
	var slots: Array[TextureButton] = []
	for child in container.get_children():
		if child is TextureButton:
			slots.append(child as TextureButton)
	return slots

func _update_skirmish_slot_availability() -> void:
	for team_data in [
		{"container": attackers_container, "team": 0},
		{"container": defenders_container, "team": 1},
	]:
		var team := int(team_data["team"])
		var team_slots := _get_slots(team_data["container"] as Control)
		for slot_index in team_slots.size():
			var slot := team_slots[slot_index]
			var locked := _is_skirmish_slot_locked(team, slot_index)
			slot.disabled = locked or bool(_original_slot_disabled.get(slot, false))
			var change_indicator := slot.get_node_or_null("Change") as CanvasItem
			if change_indicator:
				var name_label := slot.get_node_or_null("Name") as Label
				var is_occupied := name_label != null and name_label.visible
				change_indicator.visible = (
					false if locked or is_occupied
					else bool(_original_change_visibility.get(change_indicator, true))
				)

func _is_skirmish_slot_locked(team: int, slot_index: int) -> bool:
	return (
		_is_skirmish_room()
		and team >= 0
		and (
			slot_index >= 2
			or slot_index >= NetworkManager.skirmish_team_size
		)
	)

func _update_dummy_add_buttons() -> void:
	var dummy_slots: Dictionary = NetworkManager.skirmish_dummy_slots
	var room_mode := _get_room_mode()
	var supports_dummy_invites := room_mode == "skirmish" or room_mode == "deathmatch"
	var can_manage := supports_dummy_invites and _can_manage_dummy_slots() and not NetworkManager.match_started
	var deathmatch_capacity: int = NetworkManager.get_max_deathmatch_dummy_count()
	var has_fillable_slot := false
	for team_data in [
		{"container": attackers_container, "team": 0},
		{"container": defenders_container, "team": 1},
	]:
		var team := int(team_data["team"])
		var team_slots := _get_slots(team_data["container"] as Control)
		for slot_index in team_slots.size():
			var slot := team_slots[slot_index]
			var add_button := slot.get_node_or_null("Add") as TextureButton
			if not add_button:
				continue
			var has_player := _slot_has_player(team, slot_index)
			var is_local_player := _is_local_player_at_position(team, slot_index)
			var has_dummy := dummy_slots.has(_dummy_slot_key(team, slot_index))
			var locked := room_mode == "skirmish" and _is_skirmish_slot_locked(team, slot_index)
			var full_deathmatch := room_mode == "deathmatch" and not has_dummy and dummy_slots.size() >= deathmatch_capacity
			if not has_player and not has_dummy and not locked and not full_deathmatch:
				has_fillable_slot = true
			add_button.visible = supports_dummy_invites and not locked and (not has_player or is_local_player)
			add_button.disabled = NetworkManager.match_started or (not is_local_player and not can_manage) or locked or (has_player and not is_local_player) or (full_deathmatch and not is_local_player)
			add_button.texture_normal = REMOVE_PLAYER_TEXTURE if has_dummy or is_local_player else ADD_PLAYER_TEXTURE
	fill_button.disabled = not can_manage or not has_fillable_slot

func _update_dummy_slot(slot: TextureButton, dummy_name: String) -> void:
	var name_label := slot.get_node_or_null("Name") as Label
	if name_label:
		name_label.text = dummy_name
		name_label.show()
	var ping_label := slot.get_node_or_null("Ping") as Label
	if ping_label:
		ping_label.hide()
	var ready_label := slot.get_node_or_null("Ready") as Label
	if ready_label:
		ready_label.text = "READY"
		ready_label.show()
	var change_indicator := slot.get_node_or_null("Change") as CanvasItem
	if change_indicator:
		change_indicator.hide()

func _slot_has_player(team: int, slot_index: int) -> bool:
	var assignments: Dictionary = NetworkManager.skirmish_team_assignments
	var positions: Dictionary = NetworkManager.skirmish_position_assignments
	for peer_id_value in positions:
		var peer_id := int(peer_id_value)
		if (
			int(assignments.get(peer_id, -1)) == team
			and int(positions[peer_id_value]) == slot_index
		):
			return true
	return false

func _is_local_player_at_position(team: int, slot_index: int) -> bool:
	var local_peer_id := _get_local_peer_id()
	return (
		int(NetworkManager.skirmish_team_assignments.get(local_peer_id, -1)) == team
		and int(NetworkManager.skirmish_position_assignments.get(local_peer_id, -1)) == slot_index
	)

func _dummy_slot_key(team: int, slot_index: int) -> String:
	return "%d:%d" % [team, slot_index]

func _get_room_mode() -> String:
	if _is_skirmish_room():
		return "skirmish"
	if NetworkManager.hosted_room_mode == "deathmatch" or NetworkManager.expected_room_mode == "deathmatch":
		return "deathmatch"
	var current_scene := get_tree().current_scene
	if current_scene and current_scene.has_method("is_skirmish_mode_selected"):
		return "deathmatch"
	return ""
func _can_manage_dummy_slots() -> bool:
	return not NetworkManager.is_networked() or get_tree().get_multiplayer().is_server()

func _clear_slots(slots_by_team: Dictionary) -> void:
	for team_slots in slots_by_team.values():
		for slot in team_slots:
			var change_indicator := slot.get_node_or_null("Change") as CanvasItem
			if change_indicator:
				change_indicator.visible = (
					false
					if slot.disabled
					else bool(_original_change_visibility.get(change_indicator, true))
				)
			for field_name in ["Name", "Ping", "Ready"]:
				var field := slot.get_node_or_null(field_name) as Label
				if field:
					field.text = ""
					field.hide()

func _update_slot(slot: TextureButton, peer_id: int) -> void:
	var name_label := slot.get_node_or_null("Name") as Label
	var ping_label := slot.get_node_or_null("Ping") as Label
	var ready_label := slot.get_node_or_null("Ready") as Label
	if name_label:
		name_label.text = _get_player_name(peer_id)
		name_label.show()
	var add_button := slot.get_node_or_null("Add") as TextureButton
	if add_button:
		add_button.hide()
	var change_indicator := slot.get_node_or_null("Change") as CanvasItem
	if change_indicator:
		change_indicator.hide()
	if ping_label:
		var ping := _get_peer_ping(peer_id)
		ping_label.text = "%d ms" % ping if ping >= 0 else "-- ms"
		ping_label.show()
	if ready_label:
		ready_label.text = "READY"
		ready_label.show()

func _get_player_name(peer_id: int) -> String:
	if not NetworkManager.is_networked() and peer_id == _get_local_peer_id():
		return NetworkManager.player_display_name
	return NetworkManager.get_player_display_name(peer_id)

func _get_peer_ping(peer_id: int) -> int:
	var multiplayer_api := get_tree().get_multiplayer()
	var local_peer_id := _get_local_peer_id()
	if peer_id == local_peer_id:
		return 0
	if not multiplayer_api.has_multiplayer_peer():
		return -1
	var network_peer := multiplayer_api.multiplayer_peer
	if not network_peer is ENetMultiplayerPeer:
		return -1
	if not multiplayer_api.get_peers().has(peer_id):
		return -1
	var enet_peer: ENetPacketPeer = network_peer.get_peer(peer_id)
	if not enet_peer or enet_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return -1
	var round_trip_time := enet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
	return maxi(roundi(round_trip_time), 1) if round_trip_time > 0.0 else -1

func _get_local_peer_id() -> int:
	var multiplayer_api := get_tree().get_multiplayer()
	if not multiplayer_api.has_multiplayer_peer():
		return 1
	return multiplayer_api.get_unique_id()

func _update_room_display() -> void:
	ip_label.text = "IP: %s" % _get_room_ip_text()
	ip_label.show()
	var room_size := 3 if _is_skirmish_room() else NetworkManager.MAX_DEATHMATCH_PARTICIPANTS
	room_players_label.text = "PLAYERS %d/%d" % [
		_get_display_player_count(),
		room_size
	]
	room_players_label.show()

func _update_dummy_difficulty() -> void:
	var can_configure := (
		not NetworkManager.is_networked()
		or get_tree().get_multiplayer().is_server()
	)
	dummy_difficulty_option.disabled = not can_configure
	if _is_skirmish_room():
		_select_dummy_difficulty(NetworkManager.skirmish_dummy_difficulty)
	else:
		_select_dummy_difficulty(NetworkManager.deathmatch_room_dummy_difficulty)

func _on_dummy_difficulty_selected(item_index: int) -> void:
	var difficulty := dummy_difficulty_option.get_item_id(item_index)
	if _is_skirmish_room():
		NetworkManager.publish_skirmish_config(NetworkManager.skirmish_team_size, difficulty)
	else:
		NetworkManager.set_deathmatch_room_dummy_difficulty(difficulty)
func _select_dummy_difficulty(difficulty: int) -> void:
	for item_index in dummy_difficulty_option.item_count:
		if dummy_difficulty_option.get_item_id(item_index) == difficulty:
			dummy_difficulty_option.select(item_index)
			return

func _get_display_player_count() -> int:
	if NetworkManager.connection_pending or (NetworkManager.is_networked() and NetworkManager.lobby_human_count <= 0):
		return 1
	if NetworkManager.is_networked():
		return maxi(1, maxi(NetworkManager.lobby_human_count, _get_room_peer_ids().size()))
	return maxi(NetworkManager.lobby_human_count, 1)

func _get_room_ip_text() -> String:
	if not NetworkManager.room_ip_address.is_empty():
		return NetworkManager.room_ip_address.get_slice(",", 0).strip_edges()
	var local_address := "127.0.0.1"
	for address in IP.get_local_addresses():
		if address.contains(":") or address == "127.0.0.1" or address.begins_with("169.254."):
			continue
		local_address = address
		break
	return "%s:%d" % [local_address, NetworkManager.room_port]

func _is_skirmish_room() -> bool:
	var current_scene := get_tree().current_scene
	if current_scene and current_scene.has_method("is_skirmish_mode_selected"):
		if bool(current_scene.call("is_skirmish_mode_selected")):
			return true
	return (
		NetworkManager.is_networked()
		and (
			NetworkManager.hosted_room_mode == "skirmish"
			or NetworkManager.expected_room_mode == "skirmish"
		)
	)
