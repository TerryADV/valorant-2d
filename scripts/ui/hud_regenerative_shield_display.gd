extends RefCounted

var _bar: TextureProgressBar
var _reserve_label: Label
var _health_component: HealthComponent

func setup(hud: CanvasLayer) -> void:
	_bar = hud.get_node(
		"Control/Main/Bottom/HealthContainer/Shield/Bar"
	) as TextureProgressBar
	_reserve_label = hud.get_node(
		"Control/Main/Bottom/HealthContainer/Shield/Bar/Label"
	) as Label
	_bar.max_value = HealthComponent.REGENERATIVE_RESERVE_CAPACITY
	_bar.visible = false
	_reserve_label.visible = false

func bind_health_component(health_component: HealthComponent) -> void:
	if _health_component and _health_component.regenerative_shield_state_changed.is_connected(
		_on_regenerative_shield_state_changed
	):
		_health_component.regenerative_shield_state_changed.disconnect(
			_on_regenerative_shield_state_changed
		)
	_health_component = health_component
	if not _health_component:
		_update_display(false, false, 0.0, HealthComponent.REGENERATIVE_RESERVE_CAPACITY)
		return
	if not _health_component.regenerative_shield_state_changed.is_connected(
		_on_regenerative_shield_state_changed
	):
		_health_component.regenerative_shield_state_changed.connect(
			_on_regenerative_shield_state_changed
		)
	var state := _health_component.get_regenerative_shield_state()
	_update_display(
		bool(state.get("active", false)),
		bool(state.get("regenerating", false)),
		float(state.get("reserve", 0.0)),
		float(state.get("max_reserve", HealthComponent.REGENERATIVE_RESERVE_CAPACITY))
	)

func _on_regenerative_shield_state_changed(
	active: bool,
	regenerating: bool,
	reserve: float,
	max_reserve: float
) -> void:
	_update_display(active, regenerating, reserve, max_reserve)

func _update_display(active: bool, regenerating: bool, reserve: float, max_reserve: float) -> void:
	_bar.max_value = max_reserve
	_bar.value = reserve
	_bar.visible = active
	_reserve_label.text = str(ceili(reserve))
	_reserve_label.visible = active and regenerating
