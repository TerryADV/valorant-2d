class_name InteractionController
extends Node

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent
@onready var weapon_controller = get_parent().get_node_or_null("WeaponController")

func process_interaction() -> void:
	if not weapon_controller:
		return
	if Input.is_action_just_pressed("drop"):
		weapon_controller.drop_current_weapon()
	if Input.is_action_just_pressed("interact"):
		weapon_controller.try_pickup_weapon()
	if Input.is_action_just_pressed("reload"):
		weapon_controller.start_reload()
