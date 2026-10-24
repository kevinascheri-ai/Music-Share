extends Node
## Autoload: connection to the room-code relay server (see server/).
##
## The relay only pairs two players and forwards messages between them. The
## host runs the match; the guest sends rod inputs and draws the snapshots it
## gets back. Messages are JSON over a WebSocket.

signal room_created(code: String)
signal joined(code: String)
signal peer_joined
signal peer_left
signal message(data: Dictionary)
signal connection_lost
signal failed(reason: String)

enum Role { NONE, HOST, GUEST }

const PROTOCOL_VERSION := 1
const CONNECT_TIMEOUT := 8.0

var role: Role = Role.NONE
var code := ""
var connected := false

var _ws: WebSocketPeer
var _pending: Dictionary = {}
var _connect_time := 0.0
var _was_open := false


func is_online() -> bool:
	return role != Role.NONE


func host_room() -> void:
	_open({"t": "create", "v": PROTOCOL_VERSION})
	role = Role.HOST


func join_room(room_code: String) -> void:
	_open({"t": "join", "code": room_code.strip_edges().to_upper(), "v": PROTOCOL_VERSION})
	role = Role.GUEST


## Rejoins the last room after a dropped connection (guest only).
func rejoin() -> void:
	if code != "":
		join_room(code)


func send(data: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify({"t": "msg", "d": data}))


func leave() -> void:
	if _ws:
		if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_ws.send_text(JSON.stringify({"t": "leave"}))
		_ws.close()
	_ws = null
	role = Role.NONE
	code = ""
	connected = false
	_was_open = false


func _open(first_message: Dictionary) -> void:
	if _ws:
		_ws.close()
	_ws = WebSocketPeer.new()
	_was_open = false
	connected = false
	_pending = first_message
	_connect_time = 0.0
	var err := _ws.connect_to_url(Settings.server_url)
	if err != OK:
		_ws = null
		role = Role.NONE
		failed.emit("Couldn't reach the game server.")


func _process(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			_connect_time += delta
			if _connect_time > CONNECT_TIMEOUT:
				_ws.close()
				_ws = null
				role = Role.NONE
				failed.emit("Couldn't reach the game server.")
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				_ws.send_text(JSON.stringify(_pending))
			while _ws and _ws.get_available_packet_count() > 0:
				_handle(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			var had_room := connected
			_ws = null
			connected = false
			if had_room:
				connection_lost.emit()
			elif role != Role.NONE:
				role = Role.NONE
				failed.emit("Couldn't reach the game server.")


func _handle(text: String) -> void:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var m: Dictionary = parsed
	match m.get("t", ""):
		"created":
			code = m.code
			connected = true
			room_created.emit(code)
		"joined":
			code = m.code
			connected = true
			joined.emit(code)
		"peer_joined":
			peer_joined.emit()
		"peer_left":
			peer_left.emit()
		"msg":
			if typeof(m.get("d")) == TYPE_DICTIONARY:
				message.emit(m.d)
		"error":
			var reason: String = {
				"not_found": "No game with that code. Check it and try again.",
				"full": "That game already has two players.",
				"version": "Your opponent is on a different version of the game.",
				"rate_limited": "Too many messages. Connection closed.",
			}.get(m.get("code", ""), "Something went wrong with the game server.")
			var was_connected := connected
			leave()
			if was_connected:
				connection_lost.emit()
			else:
				failed.emit(reason)
