extends Node
## End-to-end online check: two copies of the game play through a real relay.
## Start the relay (cd server && npm start), then run a host and a guest:
##   godot --path . res://tests/online_smoke.tscn -- host <server_url> <code_file> <out_dir>
##   godot --path . res://tests/online_smoke.tscn -- guest <server_url> <code_file> <out_dir>
## Each prints PASS/FAIL lines and exits 0 when all of its checks pass.

var _role := ""
var _code_file := ""
var _out := ""
var _main: Control
var _failures := 0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	_role = a[0]
	Settings.server_url = a[1]
	_code_file = a[2]
	_out = a[3] if a.size() > 3 else ""
	Settings.tutorial_seen = true
	Settings.sound = false
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	if _role == "host":
		_host.call_deferred()
	else:
		_guest.call_deferred()


func _check(cond: bool, msg: String) -> void:
	print("%s  [%s] %s" % ["PASS" if cond else "FAIL", _role, msg])
	if not cond:
		_failures += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _wait_for(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
	return cond.call()


func _shot(name: String) -> void:
	if _out == "" or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(_out.path_join(name + ".png"))


func _finish() -> void:
	print("%s done: %d failures" % [_role, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _host() -> void:
	_main.show_online()
	Net.host_room()
	_check(await _wait_for(func(): return Net.code != "", 5.0), "room created")
	var f := FileAccess.open(_code_file, FileAccess.WRITE)
	f.store_string(Net.code)
	f.close()
	_check(await _wait_for(func(): return _main._game != null, 15.0), "match starts when the friend joins")
	var game: GameScreen = _main._game
	await _wait(4.0)
	_check(game._remote_input != null, "receives the guest's rod input")
	var guest_fwd: Rod = game.match_.sim.team_rods(1)[2]
	_check(absf(guest_fwd.x) > 10.0, "guest's drag moved their rod on the host (x=%.1f)" % guest_fwd.x)
	_check(game._rtt_ms >= 0 and game._rtt_ms < 500, "ping round trip measured (%d ms)" % game._rtt_ms)
	await _shot("online_host")
	_check(await _wait_for(func(): return game._waiting_for_peer, 8.0), "pauses and waits when the guest drops")
	var frozen_puck := game.match_.sim.puck_pos
	_check(await _wait_for(func(): return not game._waiting_for_peer, 10.0), "resumes when the guest rejoins")
	await _wait(1.0)
	_check(game.match_.sim.puck_pos != frozen_puck or game.match_.phase != Match.Phase.PLAYING, "match is running again")

	# End the match, rematch, then the guest quits for good.
	await _wait(1.0)
	game.match_.end_by_forfeit(0)
	game._present_events([{"type": "final", "winner": 0}])
	_check(await _wait_for(func(): return game._results_shown, 5.0), "host sees the results screen")
	game._on_rematch_pressed()
	_check(await _wait_for(func(): return not game.match_.is_over(), 10.0), "rematch restarts once both agree")
	_check(game.match_.score == [0, 0], "rematch starts at 0-0")
	_check(await _wait_for(func(): return game._peer_gone, 10.0), "notices the guest quitting")
	_check(game.match_.is_over() and game.match_.winner == 0, "guest quitting mid-match is a forfeit win")
	_finish()


func _guest() -> void:
	_main.show_online()
	var code := ""
	var t := 0.0
	while code == "" and t < 10.0:
		if FileAccess.file_exists(_code_file):
			code = FileAccess.get_file_as_string(_code_file).strip_edges()
		await _wait(0.1)
		t += 0.1
	_check(code.length() == 5, "got the room code (%s)" % code)
	Net.join_room(code)
	_check(await _wait_for(func(): return _main._game != null, 10.0), "match starts after joining")
	var game: GameScreen = _main._game
	_check(game.view.flipped, "guest sees the table from their own end")
	await _wait(2.0)
	_check(game._snapshots.size() > 5, "receives host snapshots (%d buffered)" % game._snapshots.size())

	# Drag our forward rod sideways and make sure our own view reacts at once.
	var fwd: Rod = game._predicted.team_rods(1)[2]
	var grab: Vector2 = game.view.get_global_transform_with_canvas() * Vector2(game.match_.sim.center_x, fwd.y)
	_touch(grab, true)
	for i in 10:
		_drag(grab + Vector2(-12 * i, 0))
		await get_tree().process_frame
	_touch(grab + Vector2(-120, 0), false)
	await _wait(0.3)
	# Dragging left on a flipped screen is +x on the table.
	_check(fwd.x > 10.0, "local prediction moves our rod immediately (x=%.1f)" % fwd.x)
	await _wait(1.5)
	await _shot("online_guest")
	_check(game.match_.time_left < 180.0 or game.match_.rules.mode == "goals", "clock is running from host state")

	# Simulate a dropped connection, then use the Reconnect path.
	Net._ws.close()
	_check(await _wait_for(func(): return game._overlay.visible, 5.0), "shows the connection-lost overlay")
	await _wait(1.0)
	Net.rejoin()
	_check(await _wait_for(func(): return not game._overlay.visible, 10.0), "rejoins and the overlay clears")
	await _wait(1.0)
	_check(game._snapshots.size() > 0 and Net.connected, "snapshots flow again after rejoining")

	_check(await _wait_for(func(): return game._results_shown, 10.0), "guest sees the results when the host's match ends")
	await _wait(0.5)
	game._on_rematch_pressed()
	_check(await _wait_for(func(): return not game.match_.is_over() and not game._overlay.visible, 10.0), "guest's rematch starts")
	await _wait(1.5)
	game._quit()
	await get_tree().process_frame
	_check(_main._game == null and not Net.is_online(), "quitting returns to the menu and leaves the room")
	await _wait(0.5)
	_finish()


func _touch(pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = pos
	Input.parse_input_event(e)
