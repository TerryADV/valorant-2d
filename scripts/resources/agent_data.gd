class_name AgentData
extends Resource

@export var agent_name: String = "Agent"
@export var agent_id: String
@export var agent_sprite: Texture2D
@export var agent_color: Color = Color(0.0, 1.0, 1.0, 1.0)
@export var loadout_scene: PackedScene
@export var flash_effect_texture: Texture2D
@export var show_ability_bar: bool = true
@export var ability_names: Array[String] = []
@export var ability_component_ids: Array[String] = []
@export var ability_component_paths: Array[NodePath] = []
@export var ability_input_actions: Array[String] = []
@export var ultimate_input_action: String = "ability_ultimate"
@export var ability_icons: Array[Texture2D] = []
@export var ability_key_labels: Array[String] = []
@export var ability_charge_keys: Array[String] = []
@export var ability_max_charges: Array[int] = []
@export var ability_recharge_times: Array[float] = []
@export var ability_kill_progress_keys: Array[String] = []
@export var ability_kills_per_charge: Array[int] = []
@export var ability_kill_markers_always_visible: Array[bool] = []
@export var ultimate_charge_key: String = ""
@export var ultimate_charges_required: int = 0

@export_group("Movement")
@export var run_speed: float = 65.0
@export_range(0.0, 1.0, 0.01) var walk_speed_ratio: float = 0.6
@export var acceleration: float = 2500.0
@export var friction: float = 2200.0

@export_group("Survivability")
@export var max_health: float = 100.0
@export var max_shield: float = 50.0
