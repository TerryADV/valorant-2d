class_name ShopController
extends Control

@onready var credits_label: Label = $"../Main/Credits/Label"
@onready var classic_button: TextureButton = $Classic
@onready var vandal_button: TextureButton = $Vandal
@onready var judge_button: TextureButton = $Judge
@onready var spectre_button: TextureButton = $Spectre
@onready var odin_button: TextureButton = $Odin
@onready var operator_button: TextureButton = $Operator
@onready var light_armor_button: TextureButton = $LightArmor
@onready var shield_regen_button: TextureButton = $ShieldRegen
@onready var heavy_armor_button: TextureButton = $HeavyArmor

var player: BaseAgent
var _mouse_mode_before_shop := Input.MOUSE_MODE_CAPTURED
var _pressed_item_id := ""
var _shop_buttons: Array[TextureButton] = []
var _normal_button_textures: Dictionary = {}

func _ready() -> void:
	visible = false
	_update_price_labels()
	shield_regen_button.disabled = false
	_shop_buttons = [
		classic_button,
		vandal_button,
		judge_button,
		spectre_button,
		odin_button,
		operator_button,
		light_armor_button,
		shield_regen_button,
		heavy_armor_button,
	]
	for button in _shop_buttons:
		_normal_button_textures[button] = button.texture_normal
		for child in button.get_children():
			if child is Control:
				(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not NetworkManager.shop_purchase_rejected.is_connected(_on_shop_purchase_rejected):
		NetworkManager.shop_purchase_rejected.connect(_on_shop_purchase_rejected)
	_bind_player()

func _process(_delta: float) -> void:
	if not visible:
		return
	var mouse_position := get_global_mouse_position()
	for button in _shop_buttons:
		var normal_texture: Texture2D = _normal_button_textures.get(button)
		var texture := normal_texture
		if _is_item_purchased(button):
			texture = button.texture_pressed if button.texture_pressed else normal_texture
		elif not button.disabled and button.get_global_rect().has_point(mouse_position):
			texture = button.texture_hover if button.texture_hover else normal_texture
		button.texture_normal = texture

func _is_item_purchased(button: TextureButton) -> bool:
	if not is_instance_valid(player) or not button:
		return false
	if button == light_armor_button:
		return player.active_shield_item_id == "shield_small"
	if button == heavy_armor_button:
		return (
			player.active_shield_item_id == "shield_large"
			or (
				player.active_shield_item_id.is_empty()
				and not player.health_component.regenerative_shield_active
				and player.get_max_shield() >= 50.0
			)
		)
	if button == shield_regen_button:
		return player.active_shield_item_id == "shield_regen"
	var weapon_controller: Node = player.get("weapon_controller")
	if not weapon_controller:
		return false
	var weapon_slots: Array = weapon_controller.get("weapon_slots")
	for weapon_value in weapon_slots:
		var weapon := weapon_value as WeaponData
		if weapon and not weapon.is_melee and weapon.weapon_name.to_lower() == button.name.to_lower():
			return true
	return false

func _update_price_labels() -> void:
	var item_buttons: Dictionary = {
		"classic": classic_button,
		"vandal": vandal_button,
		"judge": judge_button,
		"spectre": spectre_button,
		"odin": odin_button,
		"operator": operator_button,
		"shield_small": light_armor_button,
		"shield_regen": shield_regen_button,
		"shield_large": heavy_armor_button,
	}
	for item_id in item_buttons:
		var button: TextureButton = item_buttons[item_id]
		var price_label := button.get_node_or_null("Price") as Label
		if not price_label:
			continue
		var price: int = NetworkManager.get_shop_item_price(item_id)
		price_label.text = "FREE" if price == 0 else _format_credits(price)

func _unhandled_input(event: InputEvent) -> void:
	var is_key_echo: bool = event is InputEventKey and (event as InputEventKey).echo
	if event.is_action_pressed("shop") and not is_key_echo:
		_bind_player()
		if (
			player
			and player.has_local_authority()
			and not player.is_dead
			and not player.agent_select_open
			and (not NetworkManager.is_skirmish_mode() or NetworkManager.is_skirmish_preparation())
		):
			_set_shop_open(not visible)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		_set_shop_open(false)
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse_event.pressed:
		_pressed_item_id = _get_item_at_position(mouse_event.position)
		return
	if _pressed_item_id.is_empty():
		return
	var item_id := _pressed_item_id
	_pressed_item_id = ""
	var button := _get_item_button(item_id)
	if button and not button.disabled and button.get_global_rect().has_point(mouse_event.position):
		_purchase_item(item_id)

func _get_item_at_position(click_position: Vector2) -> String:
	var item_buttons: Dictionary = {
		"classic": classic_button,
		"vandal": vandal_button,
		"judge": judge_button,
		"spectre": spectre_button,
		"odin": odin_button,
		"operator": operator_button,
		"shield_small": light_armor_button,
		"shield_regen": shield_regen_button,
		"shield_large": heavy_armor_button,
	}
	for item_id in item_buttons:
		var button: TextureButton = item_buttons[item_id]
		if not button.disabled and button.get_global_rect().has_point(click_position):
			return item_id
	return ""

func _bind_player() -> void:
	var current_scene := get_tree().current_scene
	if not current_scene:
		return
	var local_player: BaseAgent
	if multiplayer.has_multiplayer_peer():
		var local_peer_id := multiplayer.get_unique_id()
		local_player = current_scene.get_node_or_null(
			"Player_%d" % local_peer_id
		) as BaseAgent
		if not local_player and local_peer_id == 1:
			local_player = current_scene.get_node_or_null("BaseAgent") as BaseAgent
	else:
		local_player = current_scene.get_node_or_null("BaseAgent") as BaseAgent
	if not local_player or not local_player.has_local_authority():
		return
	if player == local_player:
		return
	player = local_player
	player.credits_component.credits_changed.connect(_on_credits_changed)
	player.died.connect(_on_player_died)
	player.set_shop_open(visible)
	_on_credits_changed(player.credits_component.current_credits)

func _set_shop_open(is_open: bool) -> void:
	if is_open and NetworkManager.is_skirmish_mode() and not NetworkManager.is_skirmish_preparation():
		return
	if is_open and (not is_instance_valid(player) or not player.has_local_authority()):
		return
	if is_open and not visible:
		_mouse_mode_before_shop = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not is_open and visible:
		Input.mouse_mode = _mouse_mode_before_shop
	visible = is_open
	if is_instance_valid(player) and player.has_local_authority():
		player.set_shop_open(is_open)

func _purchase_item(item_id: String) -> void:
	_bind_player()
	if not player:
		return
	if not NetworkManager.purchase_shop_item(player, item_id):
		_on_shop_purchase_rejected(item_id)

func _on_shop_purchase_rejected(item_id: String) -> void:
	var button: BaseButton = _get_item_button(item_id)
	if button:
		button.tooltip_text = "Compra rechazada: revisa tus créditos o el escudo actual."

func _get_item_button(item_id: String) -> TextureButton:
	match item_id:
		"classic":
			return classic_button
		"vandal":
			return vandal_button
		"judge":
			return judge_button
		"spectre":
			return spectre_button
		"odin":
			return odin_button
		"operator":
			return operator_button
		"shield_small":
			return light_armor_button
		"shield_regen":
			return shield_regen_button
		"shield_large":
			return heavy_armor_button
		_:
			return null

func _on_credits_changed(current_credits: int) -> void:
	credits_label.text = _format_credits(current_credits)

func _on_player_died() -> void:
	_set_shop_open(false)

func _format_credits(amount: int) -> String:
	var digits := str(amount)
	var formatted := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			formatted += ","
		formatted += digits[index]
	return formatted
