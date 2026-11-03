extends RefCounted

var _hud: CanvasLayer
var _display_agent: BaseAgent

var player: BaseAgent:
	get:
		return _display_agent if is_instance_valid(_display_agent) else _hud.get("player") as BaseAgent
var ability_bar: Control
var ability_images: Array[TextureRect] = []
var ability_key_labels: Array[Label] = []
var ability_slots: Array[Control] = []
var ability_charge_images: Array[TextureRect] = []
var ability_cooldown_labels: Array[Label] = []
var ability_kill_markers: Array[HBoxContainer] = []
var ultimate_charge_markers: HBoxContainer
var flash_effect: Sprite2D:
	get:
		return _hud.get("flash_effect") as Sprite2D
var ally_agent_icon: TextureRect:
	get:
		return _hud.get("ally_agent_icon") as TextureRect

const CHARGE_ONE_TEXTURE: Texture2D = preload("res://assets/sprites/ui/abilities/charge1.png")
const CHARGE_ONE_EMPTY_TEXTURE: Texture2D = preload("res://assets/sprites/ui/abilities/charge1off.png")
const CHARGE_TWO_TEXTURE: Texture2D = preload("res://assets/sprites/ui/abilities/charge2.png")
const CHARGE_TWO_ONE_TEXTURE: Texture2D = preload("res://assets/sprites/ui/abilities/charge2_1.png")
const CHARGE_TWO_EMPTY_TEXTURE: Texture2D = preload("res://assets/sprites/ui/abilities/charge2off.png")
const ULTIMATE_CHARGE_TEXTURE: Texture2D = preload("res://assets/sprites/ui/abilities/charge_ult.png")
const ULTIMATE_CHARGE_EMPTY_TEXTURE: Texture2D = preload("res://assets/sprites/ui/abilities/charge_ult_off.png")
const ABILITY_KILL_TEXTURE: Texture2D = preload("res://assets/sprites/ui/abilities/kill.png")
const ULTIMATE_MAX_CHARGES := 7

func setup(hud: CanvasLayer) -> void:
	_hud = hud
	ability_bar = hud.get_node("Control/Main/Bottom/Ability&Bar/Bar") as Control
	ability_images = [
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability1/Image") as TextureRect,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability2/Image") as TextureRect,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability3/Image") as TextureRect,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ultimate/Image") as TextureRect,
	]
	ability_key_labels = [
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability1/Key") as Label,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability2/Key") as Label,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability3/Key") as Label,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ultimate/Key") as Label,
	]
	ability_slots = [
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability1") as Control,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability2") as Control,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability3") as Control,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ultimate") as Control,
	]
	ability_charge_images = [
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability1/Charge") as TextureRect,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability2/Charge") as TextureRect,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability3/Charge") as TextureRect,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ultimate/Charge") as TextureRect,
	]
	ability_cooldown_labels = [
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability1/Cooldown") as Label,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability2/Cooldown") as Label,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability3/Cooldown") as Label,
	]
	ability_kill_markers = [
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability1/Kill") as HBoxContainer,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability2/Kill") as HBoxContainer,
		hud.get_node("Control/Main/Bottom/Ability&Bar/AbilityContainer/Ability3/Kill") as HBoxContainer,
	]
	ultimate_charge_markers = hud.get_node(
		"Control/Main/Bottom/Ability&Bar/AbilityContainer/Ultimate/HBoxContainer"
	) as HBoxContainer
func setup_ability_bar() -> void:
	for cooldown_label in ability_cooldown_labels:
		cooldown_label.visible = false
	prepare_ultimate_charge_markers()

func set_display_agent(agent: BaseAgent) -> void:
	if _display_agent == agent:
		return
	var previous := player
	if previous and previous.ability_charges and previous.ability_charges.has_signal("charge_state_changed"):
		var callback := Callable(self, "on_charge_state_changed")
		if previous.ability_charges.is_connected("charge_state_changed", callback):
			previous.ability_charges.disconnect("charge_state_changed", callback)
	_display_agent = agent
	if player:
		apply_agent_ability_ui()
		refresh_ability_charges()

func prepare_ultimate_charge_markers(required_charges: int = ULTIMATE_MAX_CHARGES) -> void:
	var marker_template := ultimate_charge_markers.get_child(0) as TextureRect
	if not marker_template:
		push_error("Ultimate charge marker template is missing from the HUD.")
		return
	while ultimate_charge_markers.get_child_count() < required_charges:
		var marker := marker_template.duplicate() as TextureRect
		marker.name = "Charge%d" % (ultimate_charge_markers.get_child_count() + 1)
		ultimate_charge_markers.add_child(marker)
	for index in range(ultimate_charge_markers.get_child_count()):
		var marker := ultimate_charge_markers.get_child(index) as TextureRect
		if marker:
			marker.visible = index < required_charges

func get_ability_icon(ability_name: String) -> Texture2D:
	for data in NetworkManager.agent_data_catalog.values():
		if not data is AgentData:
			continue
		for index in range(data.ability_names.size()):
			if data.ability_names[index] == ability_name and index < data.ability_icons.size():
				return data.ability_icons[index]
	return null

func on_agent_data_changed(_data: AgentData) -> void:
	apply_agent_ability_ui()
	refresh_ability_charges()

func apply_agent_ability_ui() -> void:
	if not player or not player.agent_data:
		return
	var data := player.agent_data
	flash_effect.texture = data.flash_effect_texture
	ally_agent_icon.texture = data.agent_sprite
	ability_bar.visible = data.show_ability_bar
	for index in range(ability_slots.size()):
		var has_ability := index < data.ability_icons.size()
		ability_slots[index].visible = has_ability
		ability_images[index].texture = data.ability_icons[index] if has_ability else null
		if index < data.ability_key_labels.size():
			ability_key_labels[index].text = data.ability_key_labels[index]
	if data.ultimate_charges_required > 0:
		prepare_ultimate_charge_markers(data.ultimate_charges_required)
		ability_charge_images[3].visible = true
		ultimate_charge_markers.visible = true
		for index in range(ultimate_charge_markers.get_child_count()):
			var marker := ultimate_charge_markers.get_child(index) as TextureRect
			if marker:
				marker.visible = index < data.ultimate_charges_required
				marker.texture = ULTIMATE_CHARGE_EMPTY_TEXTURE
	else:
		ability_charge_images[3].visible = true
		ability_charge_images[3].texture = CHARGE_ONE_EMPTY_TEXTURE
		ultimate_charge_markers.visible = false
	for index in range(ability_charge_images.size() - 1):
		var has_charge_ui := index < data.ability_max_charges.size() and data.ability_max_charges[index] > 0
		ability_charge_images[index].visible = has_charge_ui
		ability_kill_markers[index].visible = (
			(index < data.ability_kill_markers_always_visible.size()
			and data.ability_kill_markers_always_visible[index])
			or (
				index < data.ability_kills_per_charge.size()
				and data.ability_kills_per_charge[index] > 0
			)
		)
		for marker in ability_kill_markers[index].get_children():
			var kill_icon := marker as TextureRect
			if kill_icon:
				kill_icon.texture = ABILITY_KILL_TEXTURE
	var charge_component := player.ability_charges
	if charge_component and charge_component.has_signal("charge_state_changed"):
		var callback := Callable(self, "on_charge_state_changed")
		if not charge_component.is_connected("charge_state_changed", callback):
			charge_component.connect("charge_state_changed", callback)
	else:
		for index in range(ability_charge_images.size() - 1):
			var has_configured_charges := (
				index < data.ability_max_charges.size()
				and data.ability_max_charges[index] > 0
				and ability_slots[index].visible
			)
			ability_charge_images[index].visible = has_configured_charges
			if has_configured_charges:
				ability_charge_images[index].texture = (
					CHARGE_TWO_TEXTURE
					if data.ability_max_charges[index] == 2
					else CHARGE_ONE_TEXTURE
				)
			ability_images[index].modulate = Color.WHITE
		for index in range(ability_kill_markers.size()):
			ability_kill_markers[index].visible = false
		ability_charge_images[3].visible = true
		ability_charge_images[3].texture = CHARGE_ONE_EMPTY_TEXTURE
		ultimate_charge_markers.visible = data.ultimate_charges_required > 0
		for index in range(ultimate_charge_markers.get_child_count()):
			var marker := ultimate_charge_markers.get_child(index) as TextureRect
			if marker:
				marker.visible = index < data.ultimate_charges_required
				marker.texture = ULTIMATE_CHARGE_EMPTY_TEXTURE

func refresh_ability_charges() -> void:
	if not player or not player.ability_charges:
		return
	var charges: Dictionary = player.get_ability_charge_state()
	on_charge_state_changed(charges)

func on_charge_state_changed(charges: Dictionary) -> void:
	if not player or not player.agent_data:
		return
	var data := player.agent_data
	for index in range(mini(3, ability_images.size())):
		var charge_key := data.ability_charge_keys[index] if index < data.ability_charge_keys.size() else ""
		var maximum := data.ability_max_charges[index] if index < data.ability_max_charges.size() else 0
		var charge_component := player.ability_charges
		if charge_component and not charge_key.is_empty():
			var configured_maximum_property := "%s_max_charges" % charge_key
			if _has_property(charge_component, configured_maximum_property):
				maximum = int(charge_component.get(configured_maximum_property))
		if charge_key.is_empty() or maximum <= 0 or not ability_slots[index].visible:
			ability_images[index].modulate = Color.WHITE
			ability_charge_images[index].visible = false
			continue
		var current := int(charges.get(charge_key, maximum))
		ability_images[index].modulate = Color.WHITE if current > 0 else Color(1.0, 1.0, 1.0, 0.4)
		ability_charge_images[index].visible = true
		match maximum:
			1:
				ability_charge_images[index].texture = CHARGE_ONE_TEXTURE if current > 0 else CHARGE_ONE_EMPTY_TEXTURE
			2:
				match current:
					2:
						ability_charge_images[index].texture = CHARGE_TWO_TEXTURE
					1:
						ability_charge_images[index].texture = CHARGE_TWO_ONE_TEXTURE
					_:
						ability_charge_images[index].texture = CHARGE_TWO_EMPTY_TEXTURE
			_:
				ability_charge_images[index].visible = false
		var progress_key := data.ability_kill_progress_keys[index] if index < data.ability_kill_progress_keys.size() else ""
		var kills_required := data.ability_kills_per_charge[index] if index < data.ability_kills_per_charge.size() else 0
		var always_show_markers := (
			index < data.ability_kill_markers_always_visible.size()
			and data.ability_kill_markers_always_visible[index]
		)
		var kill_markers := ability_kill_markers[index]
		kill_markers.visible = always_show_markers or (kills_required > 0 and current < maximum)
		var progress := int(charges.get(progress_key, 0)) if not progress_key.is_empty() else 0
		for marker_index in range(kill_markers.get_child_count()):
			var marker := kill_markers.get_child(marker_index) as TextureRect
			if marker:
				marker.modulate.a = 1.0 if marker_index < progress else 0.35
	var ultimate_required := data.ultimate_charges_required
	if ultimate_required <= 0:
		ability_images[3].modulate = Color.WHITE
		_refresh_ally_ultimate_indicator(false)
		return
	var ultimate_charges := int(charges.get(data.ultimate_charge_key, 0))
	_refresh_ally_ultimate_indicator(ultimate_charges >= ultimate_required)
	ability_images[3].modulate = Color.WHITE if ultimate_charges >= ultimate_required else Color(1.0, 1.0, 1.0, 0.4)
	ability_charge_images[3].visible = true
	ability_charge_images[3].texture = (
		CHARGE_ONE_TEXTURE if ultimate_charges >= ultimate_required else CHARGE_ONE_EMPTY_TEXTURE
	)
	for index in range(ultimate_charge_markers.get_child_count()):
		var marker := ultimate_charge_markers.get_child(index) as TextureRect
		if marker:
			marker.texture = (
				ULTIMATE_CHARGE_TEXTURE
				if index < ultimate_charges
				else ULTIMATE_CHARGE_EMPTY_TEXTURE
			)

func _refresh_ally_ultimate_indicator(ready: bool) -> void:
	var active := false
	if player:
		var components := player.get_node_or_null("Components")
		if components:
			for component in components.get_children():
				if component.has_method("is_ultimate_active") and component.call("is_ultimate_active"):
					active = true
					break
	_hud.call("_on_ultimate_state_changed", ready, active)

func _has_property(object: Object, property_name: String) -> bool:
	for property_info in object.get_property_list():
		if String(property_info.get("name", "")) == property_name:
			return true
	return false

