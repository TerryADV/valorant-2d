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
@onready var mode_options: Control = $Main/Custom/Options
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

func _ready() -> void:
	loading_screen.hide()
	main_screen.hide()
	username_input.text = _load_saved_player_name()
	if not username_input.text.strip_edges().is_empty():
		NetworkManager.player_display_name = username_input.text.strip_edges()
	username_input.text_changed.connect(_on_username_changed)
	login_button.pressed.connect(_on_login_pressed)
	_game_update_service.setup(self)
	_game_update_service.download_progress.connect(_on_update_download_progress)
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

func _process(_delta: float) -> void:
	var mouse_position := get_global_mouse_position()
	selected_mode_indicator.modulate = _mode_check_color(deathmatch_option, mouse_position, "mode")
	skirmish_mode_indicator.modulate = _mode_check_color(skirmish_option, mouse_position, "mode")
	for map_option in _map_option_buttons:
		var check := map_option.get_node_or_null("Selected") as TextureRect
		if check:
			check.modulate = _mode_check_color(map_option, mouse_position, "map")

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
	if result.get("status", "") != "downloaded":
		loading_bar.value = 0.0
	loading_bar_label.hide()
	_load_selected_map_resources()

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
	if options_kind == "mode":
		deathmatch_option.show()
		skirmish_option.show()
		_clear_map_options()
	else:
		deathmatch_option.hide()
		skirmish_option.hide()
		_populate_map_options()
	_animate_window(mode_options, true)

func _hide_options() -> void:
	_active_options_kind = ""
	_animate_window(mode_options, false)

func _select_mode(mode_name: String) -> void:
	_selected_mode = mode_name
	mode_button.text = "MODE: %s" % mode_name
	selected_mode_indicator.visible = mode_name == "DEATHMATCH"
	skirmish_mode_indicator.visible = mode_name == "SKIRMISH"
	var allowed_maps := _get_maps_for_selected_mode()
	if not allowed_maps.has(_selected_map_path):
		_selected_map_path = str(allowed_maps[0]) if not allowed_maps.is_empty() else ""
	_update_map_button_text()

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
