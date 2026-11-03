extends RefCounted

func is_actor_ally(actor: Node) -> bool:
	if not is_instance_valid(actor) or not NetworkManager.is_skirmish_mode():
		return false
	var local_team := NetworkManager.get_skirmish_team_for_peer(_get_local_peer_id())
	return local_team >= 0 and int(actor.get("skirmish_team")) == local_team

func is_peer_ally(peer_id: int) -> bool:
	if not NetworkManager.is_skirmish_mode():
		return false
	var local_team := NetworkManager.get_skirmish_team_for_peer(_get_local_peer_id())
	var owner_team := NetworkManager.get_skirmish_team_for_peer(peer_id)
	return local_team >= 0 and owner_team == local_team

func _get_local_peer_id() -> int:
	var multiplayer_api := NetworkManager.get_multiplayer()
	if multiplayer_api.has_multiplayer_peer():
		var network_peer := multiplayer_api.multiplayer_peer
		if network_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			return multiplayer_api.get_unique_id()
	return 1
