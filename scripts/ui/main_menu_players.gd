extends Control

const REFRESH_INTERVAL := 0.25

@onready var attackers_container: Control = $Positions/Attackers
@onready var defenders_container: Control = $Positions/Defenders
@onready var observers_container: Control = $Positions/Observers

var _refresh_elapsed := REFRESH_INTERVAL
var _normal_textures: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	attackers_container.mouse_filter = Control.MOUSE_FILTER_STOP
	defenders_container.mouse_filter = Control.MOUSE_FILTER_STOP
	NetworkManager.skirmish_teams_changed.connect(_on_skirmish_teams_changed)
	NetworkManager.lobby_players_updated.connect(_on_lobby_players_updated)
	_connect_team_slots(attackers_container, 0)
	_connect_team_slots(defenders_container, 1)
	_connect_team_slots(observers_container, -1)
	_refresh_player_slots()

func _process(delta: float) -> void:
	_process_hover_state()
	_refresh_elapsed += delta
	if _refresh_elapsed < REFRESH_INTERVAL:
		return
	_refresh_elapsed = 0.0
	_refresh_player_slots()

func _connect_team_slots(container: Control, team: int) -> void:
	var slots := _get_slots(container)
	for index in slots.size():
		var slot := slots[index]
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.disabled = false
		_normal_textures[slot] = slot.texture_normal
		_set_slot_children_mouse_filter(slot)
		slot.pressed.connect(_on_team_slot_pressed.bind(team, index))

func _set_slot_children_mouse_filter(slot: TextureButton) -> void:
	for child in slot.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_control_descendants_mouse_filter(child)

func _set_control_descendants_mouse_filter(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_control_descendants_mouse_filter(child)

func _on_team_slot_pressed(team: int, position: int) -> void:
	if team < 0:
		return
	NetworkManager.set_local_skirmish_position(team, position)

func _process_hover_state() -> void:
	var mouse_position := get_global_mouse_position()
	for container in [attackers_container, defenders_container, observers_container]:
		for slot in _get_slots(container):
			var normal_texture: Texture2D = _normal_textures.get(slot)
			var hovered := slot.get_global_rect().has_point(mouse_position)
			slot.texture_normal = slot.texture_hover if hovered else normal_texture

func _on_skirmish_teams_changed(_team_assignments: Dictionary) -> void:
	_refresh_player_slots()

func _on_lobby_players_updated(_player_names: Dictionary) -> void:
	_refresh_player_slots()

func _refresh_player_slots() -> void:
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
			var position := int(position_assignments.get(peer_id, -1))
			if position >= 0 and position < team_slots.size():
				_update_slot(team_slots[position], peer_id)

func _get_room_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = [1]
	var multiplayer_api := get_tree().get_multiplayer()
	for peer_id_value in multiplayer_api.get_peers():
		var peer_id := int(peer_id_value)
		if not peer_ids.has(peer_id):
			peer_ids.append(peer_id)
	var local_peer_id := multiplayer_api.get_unique_id()
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

func _clear_slots(slots_by_team: Dictionary) -> void:
	for team_slots in slots_by_team.values():
		for slot in team_slots:
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
		name_label.text = NetworkManager.get_player_display_name(peer_id)
		name_label.show()
	if ping_label:
		var ping := _get_peer_ping(peer_id)
		ping_label.text = "%d ms" % ping if ping >= 0 else "-- ms"
		ping_label.show()
	if ready_label:
		ready_label.text = "READY" if _is_peer_ready(peer_id) else "CONNECTING"
		ready_label.show()

func _is_peer_ready(peer_id: int) -> bool:
	if not NetworkManager.is_networked():
		return peer_id == get_tree().get_multiplayer().get_unique_id()
	return NetworkManager.lobby_player_names.has(peer_id)

func _get_peer_ping(peer_id: int) -> int:
	var multiplayer_api := get_tree().get_multiplayer()
	var local_peer_id := multiplayer_api.get_unique_id()
	if peer_id == local_peer_id:
		return 0
	var network_peer := multiplayer_api.multiplayer_peer
	if not network_peer is ENetMultiplayerPeer or not multiplayer_api.get_peers().has(peer_id):
		return -1
	var enet_peer: ENetPacketPeer = network_peer.get_peer(peer_id)
	if not enet_peer or enet_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return -1
	var round_trip_time := enet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
	return maxi(roundi(round_trip_time), 1) if round_trip_time > 0.0 else -1
