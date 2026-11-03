extends RefCounted

var peer: ENetMultiplayerPeer
var connection_pending := false

func host(port: int, max_players: int, multiplayer_api: MultiplayerAPI) -> Error:
	if peer != null or connection_pending:
		return ERR_BUSY
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port, max_players)
	if error != OK:
		peer.close()
		peer = null
		return error
	multiplayer_api.multiplayer_peer = peer
	return OK

func join(address: String, port: int, multiplayer_api: MultiplayerAPI) -> Error:
	var ip := address.strip_edges()
	if peer != null or connection_pending:
		return ERR_BUSY
	if ip.is_empty():
		return ERR_INVALID_PARAMETER
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, port)
	if error != OK:
		peer = null
		return error
	multiplayer_api.multiplayer_peer = peer
	connection_pending = true
	return OK

func disconnect_session(multiplayer_api: MultiplayerAPI) -> void:
	if multiplayer_api.multiplayer_peer:
		multiplayer_api.multiplayer_peer.close()
	multiplayer_api.multiplayer_peer = null
	peer = null
	connection_pending = false

func clear_connection_pending() -> void:
	connection_pending = false
