extends Control

const GAME_UPDATE_SERVICE_SCRIPT := preload("res://scripts/systems/game_update_service.gd")

@onready var username_input: TextEdit = $LogIn/Username
@onready var login_button: TextureButton = $LogIn/TextureButton
@onready var loading_screen: Control = $LoadingScreen
@onready var loading_bar: TextureProgressBar = $LoadingScreen/Bar
@onready var loading_bar_label: Label = $LoadingScreen/Bar/LabelBar
@onready var loading_info: Label = $LoadingScreen/Info
@onready var copyright_label: Label = $LoadingScreen/Copyright
@onready var main_screen: Control = $Main
@onready var mode_button: Button = $Main/Custom/Mode
@onready var mode_options: Control = $Main/Custom/Options
@onready var deathmatch_option: Button = $Main/Custom/Options/VBoxContainer/Label
@onready var selected_mode_indicator: TextureRect = $Main/Custom/Options/VBoxContainer/Label/Selected

var _game_update_service = GAME_UPDATE_SERVICE_SCRIPT.new()
var _update_notice := ""

func _ready() -> void:
	$LogIn.show()
	loading_screen.hide()
	main_screen.hide()
	username_input.text_changed.connect(_on_username_changed)
	login_button.pressed.connect(_on_login_pressed)
	mode_button.pressed.connect(_on_mode_button_pressed)
	deathmatch_option.pressed.connect(_on_deathmatch_option_pressed)
	_game_update_service.setup(self)
	_game_update_service.download_progress.connect(_on_update_download_progress)
	copyright_label.text = "A fan-made project. Not affiliated with or endorsed by Riot Games."
	_on_username_changed()

func _on_username_changed() -> void:
	login_button.disabled = username_input.text.strip_edges().is_empty()

func _on_login_pressed() -> void:
	var player_name := username_input.text.strip_edges()
	if player_name.is_empty():
		return
	NetworkManager.player_display_name = player_name
	$LogIn.hide()
	loading_screen.show()
	loading_info.text = "Loading game files..."
	loading_bar.value = 0.0
	loading_bar_label.text = "Checking..."
	_check_for_updates_and_load()

func _check_for_updates_and_load() -> void:
	var project_version := str(ProjectSettings.get_setting("application/config/version", "0.2.2"))
	var installed_version := _game_update_service.get_installed_version(project_version)
	var result: Dictionary = await _game_update_service.check_and_download_update(installed_version)
	_update_notice = str(result.get("message", ""))
	loading_info.text = _update_notice
	if result.get("status", "") != "downloaded":
		loading_bar.value = 0.0
		loading_bar_label.text = "--"
	_load_deathmatch_resources()

func _on_update_download_progress(bytes_received: int, total_bytes: int) -> void:
	if total_bytes > 0:
		loading_bar.value = float(bytes_received) / float(total_bytes) * 100.0
		loading_bar_label.text = "%s / %s" % [
			_format_file_size(bytes_received),
			_format_file_size(total_bytes)
		]
	else:
		loading_bar_label.text = "%s downloaded" % _format_file_size(bytes_received)

func _format_file_size(byte_count: int) -> String:
	return "%.1f MB" % (float(byte_count) / 1048576.0)

func _load_deathmatch_resources() -> void:
	const MAP_PATH := "res://scenes/maps/ascent.tscn"
	var request_error := ResourceLoader.load_threaded_request(MAP_PATH)
	if request_error != OK:
		_show_loading_error("Could not start loading game files.")
		return
	while true:
		var progress: Array = []
		var load_status := ResourceLoader.load_threaded_get_status(MAP_PATH, progress)
		if not progress.is_empty():
			var percentage := int(round(float(progress[0]) * 100.0))
			loading_bar.value = percentage
			loading_bar_label.text = "%d%%" % percentage
		match load_status:
			ResourceLoader.THREAD_LOAD_LOADED:
				ResourceLoader.load_threaded_get(MAP_PATH)
				loading_bar.value = 100.0
				loading_bar_label.text = "100%"
				loading_info.text = _update_notice
				await get_tree().create_timer(0.35).timeout
				loading_screen.hide()
				main_screen.show()
				return
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_show_loading_error("Could not load game files.")
				return
		await get_tree().process_frame

func _show_loading_error(message: String) -> void:
	loading_info.text = message
	loading_bar_label.text = "Error"
	loading_bar.value = 0.0

func _on_mode_button_pressed() -> void:
	mode_options.visible = not mode_options.visible

func _on_deathmatch_option_pressed() -> void:
	mode_button.text = "MODE: DEATHMATCH"
	selected_mode_indicator.show()
	mode_options.hide()
