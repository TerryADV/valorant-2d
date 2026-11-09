extends Control

const GAME_UPDATE_SERVICE_SCRIPT := preload("res://scripts/systems/game_update_service.gd")
const PLAYER_SETTINGS_PATH := "user://player_settings.cfg"
const PLAYER_SETTINGS_SECTION := "player"
const PLAYER_NAME_KEY := "display_name"
const MODE_CHECK_HOVER_COLOR := Color(0.13333334, 1.0, 0.77254903, 1.0)
const MAPS_ROOT := "res://scenes/maps"
const FALLBACK_MAP_PATHS: Array[String] = [
	"res://scenes/maps/ascent.tscn",
	"res://scenes/maps/skirmish/skirmish_a.tscn",
]

@onready var username_input: TextEdit = $LogIn/Username
@onready var login_button: TextureButton = $LogIn/TextureButton
@onready var loading_screen: Control = $LoadingScreen
@onready var loading_bar: TextureProgressBar = $LoadingScreen/Bar
@onready var loading_bar_label: Label = $LoadingScreen/Bar/LabelBar
@onready var loading_info: Label = $LoadingScreen/Info
@onready var copyright_label: Label = $LoadingScreen/Copyright
@onready var main_screen: Control = $Main
@onready var mode_button: Button = $Main/Custom/Mode
@onready var map_button: Button = $Main/Custom/Map
@onready var server_button: Button = $Main/Custom/Server
@onready var start_button: TextureButton = $Main/Custom/Start
@onready var start_label: Label = $Main/Custom/Start/Label
@onready var mode_options: Control = $Main/Custom/Options
@onready var connect_options: Control = $Main/Custom/Options/Connect
@onready var connect_ip_input: TextEdit = $Main/Custom/Options/Connect/IP
@onready var connect_button: Button = $Main/Custom/Options/Connect/Button
@onready var deathmatch_option: Button = $Main/Custom/Options/VBoxContainer/Deathmatch
@onready var selected_mode_indicator: TextureRect = $Main/Custom/Options/VBoxContainer/Deathmatch/Selected
@onready var skirmish_option: Button = $Main/Custom/Options/VBoxContainer/Skirmish
@onready var skirmish_mode_indicator: TextureRect = $Main/Custom/Options/VBoxContainer/Skirmish/Selected
@onready var options_container: VBoxContainer = $Main/Custom/Options/VBoxContainer

var _game_update_service = GAME_UPDATE_SERVICE_SCRIPT.new()
var _update_notice := ""
var _window_tweens: Dictionary = {}
var _selected_mode := "DEATHMATCH"
var _selected_map_path := ""
var _active_options_kind := ""
var _map_option_buttons: Array[Button] = []
var _connection_elapsed := 0.0

func _ready() -> void:
	loading_screen.hide()
	main_screen.hide()
	mode_options.hide()
	connect_options.hide()
	username_input.text = _load_saved_player_name()
	if not username_input.text.strip_edges().is_empty():
		NetworkManager.player_display_name = username_input.text.strip_edges()
	username_input.text_changed.connect(_on_username_changed)
	login_button.pressed.connect(_on_login_pressed)
	start_button.pressed.connect(_on_start_pressed)
	_game_update_service.setup(self)
	_game_update_service.download_progress.connect(_on_update_download_progress)
	NetworkManager.connected.connect(_on_lan_connected)
	NetworkManager.connection_failed.connect(_on_lan_connection_failed)
	NetworkManager.room_mode_mismatch.connect(_on_lan_room_mode_mismatch)
	loading_bar_label.hide()
	copyright_label.text = "A fan-made project. Not affiliated with or endorsed by Riot Games."
	_on_username_changed()
	_select_mode("DEATHMATCH")
	_animate_window($LogIn, true)

func _input(event: InputEvent) -> void:
	if not main_screen.visible or not mode_button.visible:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	if server_button.get_global_rect().has_point(mouse_event.position):
		_toggle_options("server")
		get_viewport().set_input_as_handled()
		return
	if mode_button.get_global_rect().has_point(mouse_event.position):
		_toggle_options("mode")
		get_viewport().set_input_as_handled()
		return
	if map_button.get_global_rect().has_point(mouse_event.position):
		_toggle_options("map")
		get_viewport().set_input_as_handled()
		return
	if not mode_options.visible:
		return
	if not mode_options.get_global_rect().has_point(mouse_event.position):
		_hide_options()
		get_viewport().set_input_as_handled()
		return
	if _active_options_kind == "mode":
		if deathmatch_option.get_global_rect().has_point(mouse_event.position):
			_select_mode("DEATHMATCH")
		elif skirmish_option.get_global_rect().has_point(mouse_event.position):
			_select_mode("SKIRMISH")
		else:
			return
		_hide_options()
		get_viewport().set_input_as_handled()
		return
	if _active_options_kind == "map":
		for map_option in _map_option_buttons:
			if not map_option.visible or not map_option.get_global_rect().has_point(mouse_event.position):
				continue
			var map_path := str(map_option.get_meta("map_path", ""))
			if map_path.is_empty():
				return
			_select_map(map_path)
			_hide_options()
			get_viewport().set_input_as_handled()
			return
	if _active_options_kind == "server":
		if connect_button.get_global_rect().has_point(mouse_event.position):
			_connect_or_host_lan_room()
			get_viewport().set_input_as_handled()
			return

func _process(_delta: float) -> void:
	var mouse_position := get_global_mouse_position()
	selected_mode_indicator.modulate = _mode_check_color(deathmatch_option, mouse_position, "mode")
	skirmish_mode_indicator.modulate = _mode_check_color(skirmish_option, mouse_position, "mode")
	for map_option in _map_option_buttons:
		var check := map_option.get_node_or_null("Selected") as TextureRect
		if check:
			check.modulate = _mode_check_color(map_option, mouse_position, "map")
	_update_lan_menu_status(_delta)
	_update_start_button()

func _update_start_button() -> void:
	var can_start := (
		not NetworkManager.connection_pending
		and not NetworkManager.match_started
		and _are_all_room_players_seated()
	)
	if NetworkManager.is_networked():
		can_start = can_start and get_tree().get_multiplayer().is_server()
	start_button.disabled = not can_start

func _are_all_room_players_seated() -> bool:
	return NetworkManager.are_all_room_players_seated()

func _on_start_pressed() -> void:
	if NetworkManager.connection_pending or NetworkManager.match_started:
		return
	if NetworkManager.is_networked() and not get_tree().get_multiplayer().is_server():
		return
	if not NetworkManager.is_networked():
		_ensure_lan_host()
	if not NetworkManager.is_networked():
		_show_start_error("NO SE PUDO CREAR LA SALA")
		return
	if NetworkManager.hosted_room_mode != _selected_mode.to_lower():
		_show_start_error("LA SALA NO COINCIDE CON EL MODO")
		return
	if not _are_all_room_players_seated():
		_show_start_error("ASIGNA UN LUGAR A CADA JUGADOR")
		return
	if _selected_map_path.is_empty() or not ResourceLoader.exists(_selected_map_path):
		_show_start_error("NO HAY MAPA PARA ESTE MODO")
		return
	var start_error: Error
	if _selected_mode == "SKIRMISH":
		start_error = NetworkManager.start_skirmish_match(_selected_map_path)
	else:
		start_error = NetworkManager.start_lan_match(
			NetworkManager.deathmatch_room_dummy_count,
			NetworkManager.deathmatch_room_dummy_difficulty
		)
	if start_error != OK:
		if start_error == ERR_INVALID_DATA:
			_show_start_error("ASIGNA A TODOS LOS JUGADORES")
		else:
			_show_start_error("NO SE PUDO INICIAR: %d" % start_error)
		push_warning("Could not start %s: %s" % [_selected_mode, error_string(start_error)])

func _show_start_error(message: String) -> void:
	start_label.text = message
	var reset_timer := get_tree().create_timer(2.5)
	reset_timer.timeout.connect(func() -> void:
		if is_instance_valid(start_label) and not NetworkManager.match_started:
			start_label.text = "START"
	)

func _mode_check_color(button: Control, mouse_position: Vector2, options_kind: String) -> Color:
	if (
		mode_options.visible
		and _active_options_kind == options_kind
		and button.get_global_rect().has_point(mouse_position)
	):
		return MODE_CHECK_HOVER_COLOR
	return Color.WHITE

func _on_username_changed() -> void:
	var player_name := username_input.text.strip_edges()
	login_button.disabled = player_name.is_empty()
	if not player_name.is_empty():
		_save_player_name(player_name)
		NetworkManager.player_display_name = player_name

func _on_login_pressed() -> void:
	var player_name := username_input.text.strip_edges()
	if player_name.is_empty():
		return
	_save_player_name(player_name)
	NetworkManager.player_display_name = player_name
	await _animate_window($LogIn, false)
	await _animate_window(loading_screen, true)
	loading_info.text = "Checking for updates..."
	loading_bar.value = 0.0
	loading_bar_label.hide()
	_check_for_updates_and_load()

func _load_saved_player_name() -> String:
	var settings := ConfigFile.new()
	if settings.load(PLAYER_SETTINGS_PATH) != OK:
		return ""
	return str(settings.get_value(PLAYER_SETTINGS_SECTION, PLAYER_NAME_KEY, ""))

func _save_player_name(player_name: String) -> void:
	var settings := ConfigFile.new()
	settings.load(PLAYER_SETTINGS_PATH)
	settings.set_value(PLAYER_SETTINGS_SECTION, PLAYER_NAME_KEY, player_name)
	settings.save(PLAYER_SETTINGS_PATH)

func _check_for_updates_and_load() -> void:
	var project_version := str(ProjectSettings.get_setting("application/config/version", "0.2.2"))
	var installed_version := _game_update_service.get_installed_version(project_version)
	var result: Dictionary = await _game_update_service.check_and_download_update(installed_version)
	_update_notice = str(result.get("message", ""))
	loading_info.text = _update_notice
	if result.get("status", "") == "downloaded" and _restart_after_update():
		return
	if result.get("status", "") != "downloaded" or Engine.is_editor_hint():
		loading_bar.value = 0.0
		loading_bar_label.hide()
	_load_selected_map_resources()

func _restart_after_update() -> bool:
	if Engine.is_editor_hint():
		return false
	var executable_path := OS.get_executable_path()
	var process_id := OS.create_process(executable_path, PackedStringArray())
	if process_id == -1:
		push_error("Could not restart the game after downloading the update.")
		return false
	get_tree().quit()
	return true

func _on_update_download_progress(bytes_received: int, total_bytes: int) -> void:
	loading_bar_label.show()
	if total_bytes > 0:
		loading_bar.value = float(bytes_received) / float(total_bytes) * 100.0
		loading_bar_label.text = "%s / %s" % [
			_format_file_size(bytes_received),
			_format_file_size(total_bytes)
		]
	else:
		loading_bar_label.text = _format_file_size(bytes_received)

func _format_file_size(byte_count: int) -> String:
	if byte_count < 1048576:
		return "%.0f KB" % (float(byte_count) / 1024.0)
	return "%.1f MB" % (float(byte_count) / 1048576.0)

func _load_selected_map_resources() -> void:
	if _selected_map_path.is_empty():
		_show_loading_error("No map is available for the selected mode.")
		return
	var request_error := ResourceLoader.load_threaded_request(_selected_map_path)
	if request_error != OK:
		_show_loading_error("Could not start loading game files.")
		return
	while true:
		var progress: Array = []
		var load_status := ResourceLoader.load_threaded_get_status(_selected_map_path, progress)
		if not progress.is_empty():
			var percentage := int(round(float(progress[0]) * 100.0))
			loading_bar.value = percentage
		match load_status:
			ResourceLoader.THREAD_LOAD_LOADED:
				ResourceLoader.load_threaded_get(_selected_map_path)
				loading_bar.value = 100.0
				loading_info.text = _update_notice
				await get_tree().create_timer(0.35).timeout
				await _animate_window(loading_screen, false)
				await _animate_window(main_screen, true)
				call_deferred("_ensure_lan_host")
				return
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_show_loading_error("Could not load game files.")
				return
		await get_tree().process_frame

func _show_loading_error(message: String) -> void:
	loading_info.text = message
	loading_bar_label.hide()
	loading_bar.value = 0.0

func _toggle_options(options_kind: String) -> void:
	if mode_options.visible and _active_options_kind == options_kind:
		_hide_options()
		return
	_active_options_kind = options_kind
	connect_options.hide()
	if options_kind == "mode":
		options_container.show()
		deathmatch_option.show()
		skirmish_option.show()
		_update_mode_indicators()
		_clear_map_options()
	elif options_kind == "map":
		options_container.show()
		deathmatch_option.hide()
		skirmish_option.hide()
		_populate_map_options()
	else:
		options_container.hide()
		deathmatch_option.hide()
		skirmish_option.hide()
		_clear_map_options()
		connect_options.show()
	_animate_window(mode_options, true)

func _hide_options() -> void:
	_active_options_kind = ""
	_animate_window(mode_options, false)

func _select_mode(mode_name: String) -> void:
	if NetworkManager.is_networked():
		if not get_tree().get_multiplayer().is_server():
			return
		if (
			NetworkManager.hosted_room_mode != mode_name.to_lower()
			and not get_tree().get_multiplayer().get_peers().is_empty()
		):
			return
	var restart_lan_host := (
		NetworkManager.is_networked()
		and get_tree().get_multiplayer().is_server()
		and NetworkManager.hosted_room_mode != mode_name.to_lower()
	)
	_selected_mode = mode_name
	mode_button.text = "MODE: %s" % mode_name
	_update_mode_indicators()
	var allowed_maps := _get_maps_for_selected_mode()
	if not allowed_maps.has(_selected_map_path):
		_selected_map_path = str(allowed_maps[0]) if not allowed_maps.is_empty() else ""
	_update_map_button_text()
	if restart_lan_host:
		NetworkManager.disconnect_game()
		call_deferred("_ensure_lan_host")

func _update_mode_indicators() -> void:
	selected_mode_indicator.visible = _selected_mode == "DEATHMATCH"
	skirmish_mode_indicator.visible = _selected_mode == "SKIRMISH"

func is_skirmish_mode_selected() -> bool:
	return _selected_mode == "SKIRMISH"

func _connect_or_host_lan_room() -> void:
	if NetworkManager.connection_pending:
		return
	var requested_ip := connect_ip_input.text.strip_edges()
	if requested_ip.is_empty():
		return
	if NetworkManager.is_networked():
		NetworkManager.disconnect_game()
	var join_error := NetworkManager.join_game(requested_ip, _selected_mode.to_lower())
	if join_error != OK:
		call_deferred("_ensure_lan_host")
		return
	NetworkManager.room_ip_address = requested_ip
	_connection_elapsed = 0.0

func _on_lan_connected() -> void:
	_connection_elapsed = 0.0
	NetworkManager.set_local_player_name(NetworkManager.player_display_name)

func _on_lan_connection_failed() -> void:
	call_deferred("_ensure_lan_host")

func _on_lan_room_mode_mismatch(_hosted_mode: String) -> void:
	call_deferred("_ensure_lan_host")

func _update_lan_menu_status(delta: float) -> void:
	if NetworkManager.connection_pending:
		_connection_elapsed += delta
		if _connection_elapsed >= 8.0:
			NetworkManager.disconnect_game()
			call_deferred("_ensure_lan_host")
	if NetworkManager.connection_pending:
		server_button.text = "SERVER: CONNECTING"
	elif NetworkManager.is_networked():
		var role := "HOST" if get_tree().get_multiplayer().is_server() else "CLIENT"
		server_button.text = "SERVER: %s" % role
	else:
		server_button.text = "SERVER: HOST"
	server_button.show()
	connect_button.text = "CONNECT"

func _ensure_lan_host() -> void:
	if (
		NetworkManager.is_networked()
		or NetworkManager.connection_pending
	):
		return
	for port_offset in range(32):
		var port := NetworkManager.PORT + port_offset
		var host_error := (
			NetworkManager.create_skirmish_room(port)
			if _selected_mode == "SKIRMISH"
			else NetworkManager.create_deathmatch_room(port)
		)
		if host_error == OK:
			NetworkManager.room_ip_address = _get_local_lan_endpoint(port)
			return
		if host_error != ERR_ALREADY_IN_USE and host_error != ERR_CANT_CREATE:
			return

func _get_local_lan_endpoint(port: int) -> String:
	var addresses := _get_local_ipv4_addresses()
	addresses.append("127.0.0.1")
	var endpoints := PackedStringArray()
	for address in addresses:
		endpoints.append("%s:%d" % [address, port])
	return ", ".join(endpoints)

func _get_local_ipv4_addresses() -> PackedStringArray:
	var addresses := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.contains(":") or address == "127.0.0.1" or address.begins_with("169.254."):
			continue
		if not addresses.has(address):
			addresses.append(address)
	return addresses

func _select_map(map_path: String) -> void:
	if not _get_maps_for_selected_mode().has(map_path):
		return
	_selected_map_path = map_path
	_update_map_button_text()
	for map_option in _map_option_buttons:
		var check := map_option.get_node_or_null("Selected") as CanvasItem
		if check:
			check.visible = str(map_option.get_meta("map_path", "")) == _selected_map_path

func _update_map_button_text() -> void:
	if _selected_map_path.is_empty():
		map_button.text = "MAP: NONE"
		return
	var display_name := _selected_map_path.get_file().get_basename().replace("_", " ").to_upper()
	map_button.text = "MAP: %s" % display_name

func _get_maps_for_selected_mode() -> Array[String]:
	var all_maps: Array[String] = []
	_collect_maps(MAPS_ROOT, all_maps)
	for fallback_map in FALLBACK_MAP_PATHS:
		if ResourceLoader.exists(fallback_map) and not all_maps.has(fallback_map):
			all_maps.append(fallback_map)
	all_maps.sort()
	var matching_maps: Array[String] = []
	for map_path in all_maps:
		var is_skirmish_map := map_path.get_file().get_basename().to_lower().begins_with("skirmish")
		if is_skirmish_map == (_selected_mode == "SKIRMISH"):
			matching_maps.append(map_path)
	return matching_maps

func _collect_maps(directory_path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if not directory:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = directory.get_next()
			continue
		var entry_path := directory_path.path_join(entry)
		if directory.current_is_dir():
			_collect_maps(entry_path, output)
		elif entry.get_extension().to_lower() == "tscn":
			output.append(entry_path)
		entry = directory.get_next()
	directory.list_dir_end()

func _populate_map_options() -> void:
	_clear_map_options()
	var matching_maps := _get_maps_for_selected_mode()
	for index in matching_maps.size():
		var map_path := matching_maps[index]
		var map_option := deathmatch_option.duplicate() as Button
		map_option.name = "MapOption%d" % index
		map_option.show()
		map_option.text = map_path.get_file().get_basename().replace("_", " ").to_upper()
		map_option.set_meta("map_path", map_path)
		var check := map_option.get_node_or_null("Selected") as CanvasItem
		if check:
			check.visible = map_path == _selected_map_path
		options_container.add_child(map_option)
		_map_option_buttons.append(map_option)
	if matching_maps.is_empty():
		var empty_option := deathmatch_option.duplicate() as Button
		empty_option.name = "NoMapsAvailable"
		empty_option.show()
		empty_option.text = "NO MAPS AVAILABLE"
		empty_option.disabled = true
		var check := empty_option.get_node_or_null("Selected") as CanvasItem
		if check:
			check.hide()
		options_container.add_child(empty_option)
		_map_option_buttons.append(empty_option)

func _clear_map_options() -> void:
	for map_option in _map_option_buttons:
		options_container.remove_child(map_option)
		map_option.queue_free()
	_map_option_buttons.clear()

func _animate_window(window: Control, should_show: bool, duration: float = 0.2) -> void:
	var previous_tween: Tween = _window_tweens.get(window)
	if previous_tween and previous_tween.is_running():
		previous_tween.kill()
	if should_show:
		window.show()
		window.modulate.a = 0.0
	var tween := create_tween()
	_window_tweens[window] = tween
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(window, "modulate:a", 1.0 if should_show else 0.0, duration)
	if not should_show:
		tween.tween_callback(func() -> void:
			window.hide()
			window.modulate.a = 1.0
		)
	await tween.finished
	if _window_tweens.get(window) == tween:
		_window_tweens.erase(window)
