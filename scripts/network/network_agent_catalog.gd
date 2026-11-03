extends RefCounted

const AGENT_DATA_RESOURCES: Array[AgentData] = [
	preload("res://resources/agents/phoenix.tres"),
	preload("res://resources/agents/jett.tres"),
	preload("res://resources/agents/sage.tres"),
]

var agent_data_catalog: Dictionary = {}

func load_catalog() -> void:
	for data in AGENT_DATA_RESOURCES:
		if not data:
			push_error("An agent data resource could not be loaded.")
			continue
		if data.agent_id.is_empty() or agent_data_catalog.has(data.agent_id):
			push_error("Agent resource has an empty or duplicate ID: %s" % data.resource_path)
			continue
		agent_data_catalog[data.agent_id] = data

func get_agent_data(agent_id: String) -> AgentData:
	return agent_data_catalog.get(agent_id) as AgentData
