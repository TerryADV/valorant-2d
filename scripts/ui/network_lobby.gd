extends CanvasLayer

@onready var address_input: LineEdit = $Panel/Content/Address
@onready var status_label: Label = $Panel/Content/Status
@onready var participants_label: Label = $Panel/Content/Participants
@onready var host_button: Button = $Panel/Content/Host
@onready var join_button: Button = $Panel/Content/Join
@onready var back_button: Button = $Panel/Content/Back
@onready var roster_label: Label = $RosterPanel/Content/RosterTitle
@onready var player_names_container: VBoxContainer = $RosterPanel/Content/PlayerNames
@onready var bot_settings: VBoxContainer = $Panel/Content/BotSettings
@onready var bot_count_spin_box: SpinBox = $Panel/Content/BotSettings/BotCount
@onready var difficulty_option: OptionButton = $Panel/Content/BotSettings/Difficulty

var connection_attempt_id := 0
var is_host := false
var is_client := false
var lobby_human_count := 0

func _ready() -> void:
	host_button.pressed.connect(_on_host_or_start_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	NetworkManager.connected.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.lobby_state_changed.connect(_on_lobby_state_changed)
	NetworkManager.lobby_players_updated.connect(_on_lobby_players_updated)
	difficulty_option.add_item("Fácil (25%)", BaseAgent.Difficulty.EASY)
	difficulty_option.add_item("Medio (50%)", BaseAgent.Difficulty.MEDIUM)
	difficulty_option.add_item("Difícil (100%)", BaseAgent.Difficulty.HARD)
	difficulty_option.select(BaseAgent.Difficulty.HARD)
	bot_count_spin_box.max_value = NetworkManager.MAX_DEATHMATCH_PARTICIPANTS - 1
	participants_label.text = "Jugadores: --/12"
	_on_lobby_players_updated(NetworkManager.lobby_player_names)
	bot_settings.hide()
	host_button.show()
	host_button.text = "Crear sala"
	join_button.show()

func _on_host_or_start_pressed() -> void:
	if is_host:
		var start_error: int = NetworkManager.start_lan_match(
			int(bot_count_spin_box.value),
			difficulty_option.get_selected_id()
		)
		if start_error != OK:
			status_label.text = "No se pudo iniciar la partida: %s" % start_error
		return

	var host_error: int = NetworkManager.host_game()
	if host_error != OK:
		status_label.text = (
			"No hay un punto de aparición disponible."
			if host_error == ERR_DOES_NOT_EXIST
			else "Error al crear partida: %s" % host_error
		)
		return
	is_host = true
	NetworkManager.set_local_player_name(NetworkManager.player_display_name)
	var local_addresses := _get_local_ipv4_addresses()
	if local_addresses.is_empty():
		status_label.text = "Sala creada. No se detectó una IPv4 local; revisa la configuración de red."
	else:
		status_label.text = "Comparte esta IP con el otro jugador: %s" % ", ".join(local_addresses)
	_update_lobby_controls(NetworkManager.get_connected_peer_ids().size(), false)

func _on_join_pressed() -> void:
	var error := NetworkManager.join_game(address_input.text)
	if error != OK:
		status_label.text = (
			"Escribe la IPv4 local del host; 127.0.0.1 solo conecta a esta misma PC."
			if address_input.text.strip_edges().is_empty()
			else (
				"Ya hay una conexión activa o en curso."
				if error == ERR_BUSY
				else "Error al conectar: %s" % error
			)
		)
		return
	_set_connection_controls_disabled(true)
	connection_attempt_id += 1
	status_label.text = "Conectando..."
	_wait_for_connection(connection_attempt_id)

func _on_back_pressed() -> void:
	connection_attempt_id += 1
	NetworkManager.disconnect_game()
	var error := get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	if error != OK:
		status_label.text = "No se pudo volver al menú: %s" % error

func _on_connected() -> void:
	connection_attempt_id += 1
	NetworkManager.set_local_player_name(NetworkManager.player_display_name)
	if not multiplayer.is_server():
		is_client = true
		is_host = false
		status_label.text = "Conectado. Esperando a que el host inicie la partida..."
		_set_connection_controls_disabled(true)
		_update_lobby_controls(lobby_human_count, false)

func _on_connection_failed() -> void:
	connection_attempt_id += 1
	is_client = false
	status_label.text = "No se pudo conectar"
	_set_connection_controls_disabled(false)

func _on_lobby_state_changed(human_count: int, host_started: bool) -> void:
	lobby_human_count = human_count
	_update_lobby_controls(human_count, host_started)

func _on_lobby_players_updated(player_names: Dictionary) -> void:
	for child in player_names_container.get_children():
		child.queue_free()
	var peer_ids: Array = player_names.keys()
	peer_ids.sort()
	roster_label.text = "En la sala (%d)" % peer_ids.size()
	for peer_id_value in peer_ids:
		var peer_id := int(peer_id_value)
		var player_label := Label.new()
		var player_name := str(player_names[peer_id_value])
		player_label.text = "%s%s" % [player_name, " (Tú)" if peer_id == multiplayer.get_unique_id() else ""]
		player_names_container.add_child(player_label)

func _update_lobby_controls(human_count: int, host_started: bool) -> void:
	var maximum_bots: int = NetworkManager.get_max_bot_count(human_count)
	bot_count_spin_box.max_value = maximum_bots
	bot_count_spin_box.value = mini(int(bot_count_spin_box.value), maximum_bots)
	participants_label.text = "Jugadores: %d/12" % human_count
	bot_settings.visible = is_host and not host_started
	host_button.visible = is_host or not is_client
	host_button.text = "Iniciar partida" if is_host else "Crear sala"
	host_button.disabled = (host_started or NetworkManager.connection_pending) and not is_host
	join_button.visible = not is_host and not is_client
	join_button.disabled = NetworkManager.connection_pending or host_started
	address_input.visible = not is_host and not is_client
	address_input.editable = not is_host and not is_client and not NetworkManager.connection_pending
	if is_client and not host_started and not NetworkManager.connection_pending:
		status_label.text = "Conectado. Esperando a que el host inicie la partida..."
	if host_started:
		visible = false

func _wait_for_connection(attempt_id: int) -> void:
	await get_tree().create_timer(12.0).timeout
	if attempt_id != connection_attempt_id or not NetworkManager.is_networked():
		return
	if status_label.text != "Conectando...":
		return
	NetworkManager.disconnect_game()
	status_label.text = "Tiempo agotado. Verifica la IPv4 del host y permite UDP 7000 en el firewall."
	_set_connection_controls_disabled(false)

func _set_connection_controls_disabled(disabled: bool) -> void:
	host_button.disabled = disabled
	join_button.disabled = disabled
	address_input.editable = not disabled

func _get_local_ipv4_addresses() -> PackedStringArray:
	var addresses := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		addresses.append(address)
	return addresses
