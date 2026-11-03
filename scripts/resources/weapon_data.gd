class_name WeaponData
extends Resource

const PIXELS_PER_METER: float = 10.0

@export_group("Identity")
@export var weapon_name: String = "Vandal"
@export var weapon_type: String = "Rifle" # Rifle, Sidearm, SMG, Sniper, Shotgun, Heavy
@export var is_automatic: bool = true
@export var is_melee: bool = false
@export var can_aim: bool = false
@export_range(1.0, 4.0, 0.05) var aim_zoom: float = 1.0
@export_range(1.0, 6.0, 0.05) var aim_zoom_secondary: float = 1.0
@export var wall_penetration: String = "Medium" # Low, Medium, High

@export_group("Damage")
@export_range(0.0, 180.0, 0.5, "suffix:m") var short_range: float = 15.0
@export_range(0.0, 180.0, 0.5, "suffix:m") var medium_range: float = 30.0
@export var short_damage: float = 40.0
@export var medium_damage: float = 34.0
@export var long_damage: float = 27.0
@export var melee_range: float = 24.0
@export var melee_light_damage: float = 50.0
@export var melee_light_cooldown: float = 0.3
@export var melee_heavy_damage: float = 75.0
@export var melee_heavy_cooldown: float = 0.75

@export_group("Ammo")
@export var fire_rate: float = 9.75 # Balas por segundo (RDS/SEC)
@export_range(1, 32, 1) var pellets_per_shot: int = 1
@export_range(0.0, 45.0, 0.1) var pellet_spread_degrees: float = 0.0
@export_range(1, 32, 1) var secondary_fire_pellets: int = 1
@export_range(0.0, 45.0, 0.1) var secondary_pellet_spread_degrees: float = 0.0
@export_range(1, 32, 1) var secondary_fire_ammo_cost: int = 1
@export_range(0.0, 3.0, 0.01) var secondary_fire_cooldown: float = 0.0
@export_range(0.0, 45.0, 0.1) var hipfire_spread_degrees: float = 0.0
@export var magazine_size: int = 25
@export var reserve_ammo: int = 75
@export var reload_time: float = 2.5 # Segundos

@export_group("Audio")
@export var shot_audio: AudioCue
@export var shot_local_audio: AudioCue
@export var secondary_shot_audio: AudioCue
@export var melee_light_audio: AudioCue
@export var melee_heavy_audio: AudioCue
@export var reload_audio: AudioCue
@export var equip_audio: AudioCue

@export_group("Movement")
@export_range(0.0, 1.0, 0.01) var run_speed_multiplier: float = 0.9

@export_group("Aim")
@export_range(0.1, 3.0, 0.01) var aim_fire_rate_multiplier: float = 1.0
@export_range(0.1, 1.0, 0.01) var aim_move_speed_multiplier: float = 1.0
@export_range(0.1, 1.0, 0.01) var aim_recoil_multiplier: float = 1.0

@export_group("Equip")
@export_range(0.01, 2.0, 0.01) var equip_time: float = 0.12

@export_group("Recoil")
@export var recoil_per_shot_degrees: float = 1.5
@export var max_recoil_degrees: float = 8.0
@export var recoil_recovery_speed: float = 8.0
@export var recoil_randomness_degrees: float = 0.35

@export_group("Visuals")
@export var tracer_enabled: bool = true
@export var weapon_sprite: Texture2D
@export var ui_sprite: Texture2D
