extends Control

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

func _ready() -> void:
	$LogIn.show()
	loading_screen.hide()
	main_screen.hide()
	username_input.text_changed.connect(_on_username_changed)
	login_button.pressed.connect(_on_login_pressed)
	mode_button.pressed.connect(_on_mode_button_pressed)
	deathmatch_option.pressed.connect(_on_deathmatch_option_pressed)
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
	loading_bar_label.text = "0%"
	_load_deathmatch_resources()

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
			loading_info.text = "Game files loaded."
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
