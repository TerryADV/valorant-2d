class_name AgentVisualController
extends Node2D

@onready var agent: Node2D = get_parent() as Node2D
@onready var body_sprite: Sprite2D = get_node_or_null("BodySprite") as Sprite2D
@onready var lights: Node2D = get_node_or_null("Lights") as Node2D
@onready var vision_light: PointLight2D = get_node_or_null("Lights/Vision") as PointLight2D
@onready var agent_circle: AgentCircleVisual = get_node_or_null("AgentCircle") as AgentCircleVisual
@onready var agent_polygon: Polygon2D = get_node_or_null("Polygon2D") as Polygon2D
@onready var resurrection_gradient: Sprite2D = (
	get_node_or_null("BodySprite/ResurrectionGradient") as Sprite2D
)

var vision_texture: GradientTexture2D
var vision_base_width: int = 2048
var current_vision_zoom: float = -1.0

func _ready() -> void:
	if resurrection_gradient and resurrection_gradient.material is ShaderMaterial:
		resurrection_gradient.material = (
			(resurrection_gradient.material as ShaderMaterial).duplicate() as ShaderMaterial
		)
		_update_resurrection_mask(body_sprite.texture if body_sprite else null)
	if vision_light and vision_light.texture is GradientTexture2D:
		vision_texture = vision_light.texture.duplicate() as GradientTexture2D
		vision_base_width = vision_texture.width
		vision_light.texture = vision_texture

func apply_agent_data(data: AgentData) -> void:
	if not data:
		return
	if data.agent_sprite and body_sprite:
		body_sprite.texture = data.agent_sprite
		_update_resurrection_mask(data.agent_sprite)
	if agent_circle:
		agent_circle.set_agent_color(data.agent_color)
	if agent_polygon:
		agent_polygon.color = data.agent_color

func _update_resurrection_mask(agent_texture: Texture2D) -> void:
	if not resurrection_gradient or not agent_texture:
		return
	var shader_material := resurrection_gradient.material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("agent_texture", agent_texture)

func set_lights_visible(visible_state: bool) -> void:
	if lights:
		lights.visible = visible_state

func update_vision_width(zoom_multiplier: float) -> void:
	if not vision_texture:
		return
	var safe_zoom: float = maxf(zoom_multiplier, 1.0)
	if is_equal_approx(current_vision_zoom, safe_zoom):
		return
	current_vision_zoom = safe_zoom
	var target_width: int = maxi(1, roundi(vision_base_width / safe_zoom))
	if vision_texture.width != target_width:
		vision_texture.width = target_width

func process_visuals() -> void:
	if not agent:
		return
	rotation = (agent.get_global_mouse_position() - agent.global_position).angle() + PI / 2.0
	var vision_zoom: float = 1.0
	var weapon_controller := agent.get("weapon_controller") as Node
	if (
		weapon_controller
		and bool(weapon_controller.call("is_aiming"))
		and weapon_controller.get("current_weapon")
	):
		vision_zoom = float(weapon_controller.call("get_current_aim_zoom"))
	update_vision_width(vision_zoom)
	queue_redraw()
