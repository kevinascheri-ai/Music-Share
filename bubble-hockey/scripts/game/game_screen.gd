class_name GameScreen
extends Control
## One match on screen: owns the Match, the table view, the HUD and overlays,
## and whatever drives each team (touch, computer, or the network).

signal exit_to_menu

enum Mode { AI, LOCAL, ONLINE_HOST, ONLINE_GUEST }

const DT := 1.0 / 60.0
## The host sends a snapshot every 3 ticks (20 Hz); the guest sends input
## every 2 ticks (30 Hz).
const SNAPSHOT_EVERY := 3
const INPUT_EVERY := 2
## The guest draws the host's world this far in the past so it always has two
## snapshots to blend between.
const INTERP_DELAY := 0.1
const RECONNECT_WAIT := 30.0
const HUD_HEIGHT := 104.0
const PRESENTED_EVENTS := ["hit", "wall", "post", "score", "faceoff", "puck_drop", "sudden_death", "final"]

var mode: Mode = Mode.AI
var difficulty := "medium"
var rules: Dictionary = Match.RULES_TIMER
var local_team := 0

var match_: Match
var view: TableView
var touch: Array = [null, null]
var ai: AIController

var _paused := false
var _tick := 0
var _touch_team := {}
var _remote_input = null
var _host_events: Array = []
var _snapshots: Array = []
var _clock_offset := INF
var _predicted: TableSim
var _rtt_ms := -1
var _ping_timer := 0.0
var _rematch := [false, false]
var _waiting_for_peer := false
## The other player is gone for good (quit, or the host closed the room).
var _peer_gone := false
var _wait_left := 0.0
var _results_shown := false
var _results_pending := false
var _next_sim: TableSim

var _hud: Control
var _score_labels: Array[Label] = []
var _clock_label: Label
var _net_label: Label
var _pause_button: Button
var _banner: Label
var _overlay: Control
var _overlay_box: VBoxContainer
var _wait_label: Label


func setup(p_mode: Mode, options: Dictionary = {}) -> void:
	mode = p_mode
	difficulty = options.get("difficulty", Settings.difficulty)
	rules = options.get("rules", Settings.rules())
	local_team = 1 if mode == Mode.ONLINE_GUEST else 0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	match_ = Match.new(rules)

	view = TableView.new()
	view.sim = match_.sim
	view.flipped = mode == Mode.ONLINE_GUEST
	add_child(view)

	for team in 2:
		if _is_local(team):
			var t := TouchInput.new(team)
			t.slide_sensitivity = Settings.slide_sensitivity
			t.spin_sensitivity = Settings.spin_sensitivity
			touch[team] = t
	if mode == Mode.AI:
		var diffs := AIController.load_difficulties()
		ai = AIController.new(1, diffs.get(difficulty, diffs.medium), Time.get_ticks_usec())
	if mode == Mode.ONLINE_GUEST:
		_predicted = TableSim.new()

	_build_hud()
	_build_overlays()
	resized.connect(_layout)
	_layout()

	if _is_online():
		Net.message.connect(_on_net_message)
		Net.peer_left.connect(_on_peer_left)
		Net.peer_joined.connect(_on_peer_joined)
		Net.connection_lost.connect(_on_connection_lost)
		Net.joined.connect(_on_rejoined)
	if mode == Mode.ONLINE_HOST:
		Net.send({"k": "start", "rules": rules, "resume": false})
	Sfx.set_ambience(true)


func _exit_tree() -> void:
	Sfx.set_ambience(false)


func _is_local(team: int) -> bool:
	match mode:
		Mode.LOCAL:
			return true
		Mode.ONLINE_GUEST:
			return team == 1
		_:
			return team == 0


func _is_online() -> bool:
	return mode == Mode.ONLINE_HOST or mode == Mode.ONLINE_GUEST


func _runs_simulation() -> bool:
	return mode != Mode.ONLINE_GUEST


# --- Layout and HUD ---------------------------------------------------------

func _safe_insets() -> Vector2:
	# Top and bottom insets (notch, home bar) in viewport units.
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.y <= 0 or safe.size.y <= 0:
		return Vector2.ZERO
	var k := size.y / win.y
	var top := maxf(safe.position.y, 0) * k
	var bottom := maxf(win.y - safe.end.y, 0) * k
	return Vector2(minf(top, 120.0), minf(bottom, 80.0))


func _layout() -> void:
	var insets := _safe_insets()
	_hud.position = Vector2(0, insets.x)
	_hud.size = Vector2(size.x, HUD_HEIGHT)
	var top := insets.x + HUD_HEIGHT
	view.fit(Rect2(8, top, size.x - 16, size.y - top - insets.y - 8))


func _build_hud() -> void:
	_hud = Control.new()
	add_child(_hud)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -16
	row.add_theme_constant_override("separation", 12)
	_hud.add_child(row)

	var names := _team_names()
	var order := [local_team, 1 - local_team]
	_score_labels = [null, null]
	for slot in 2:
		var team: int = order[slot]
		var box := VBoxContainer.new()
		box.size_flags_horizontal = SIZE_EXPAND_FILL
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", -6)
		box.add_child(UIKit.label(names[team], 22, view.team_colors[team]))
		var score := UIKit.label("0", 52)
		box.add_child(score)
		_score_labels[team] = score
		row.add_child(box)
		if slot == 0:
			var mid := VBoxContainer.new()
			mid.size_flags_horizontal = SIZE_EXPAND_FILL
			mid.alignment = BoxContainer.ALIGNMENT_CENTER
			_clock_label = UIKit.label("3:00", 44, UIKit.ACCENT)
			mid.add_child(_clock_label)
			_net_label = UIKit.label("", 18, UIKit.MUTED)
			mid.add_child(_net_label)
			row.add_child(mid)

	_pause_button = Button.new()
	_pause_button.text = "II"
	_pause_button.custom_minimum_size = Vector2(80, 80)
	_pause_button.size_flags_vertical = SIZE_SHRINK_CENTER
	_pause_button.pressed.connect(_toggle_pause)
	_pause_button.visible = not _is_online()
	row.add_child(_pause_button)


func _team_names() -> Array:
	match mode:
		Mode.AI:
			return ["YOU", "CPU"]
		Mode.LOCAL:
			return ["RED", "BLUE"]
		_:
			return ["YOU", "FRIEND"] if local_team == 0 else ["FRIEND", "YOU"]


func _build_overlays() -> void:
	_banner = UIKit.label("", 84, UIKit.TEXT)
	_banner.set_anchors_and_offsets_preset(PRESET_CENTER)
	_banner.grow_horizontal = GROW_DIRECTION_BOTH
	_banner.grow_vertical = GROW_DIRECTION_BOTH
	_banner.custom_minimum_size = Vector2(700, 0)
	_banner.add_theme_constant_override("outline_size", 14)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_banner.mouse_filter = MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	add_child(_banner)

	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, 0.55)
	_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)
	_overlay_box = UIKit.centered_panel(_overlay, 580)


func _show_overlay(title: String, lines: Array, buttons: Array) -> void:
	UIKit.clear(_overlay_box)
	_overlay_box.add_child(UIKit.label(title, 52, UIKit.ACCENT))
	for line in lines:
		_overlay_box.add_child(UIKit.label(line, 30, UIKit.TEXT))
	for b in buttons:
		_overlay_box.add_child(UIKit.button(b[0], b[1]))
	_overlay.visible = true


func _hide_overlay() -> void:
	_overlay.visible = false


func _flash(text: String, color := UIKit.TEXT, hold := 0.6) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	var tw := create_tween()
	_banner.modulate.a = 1.0
	_banner.scale = Vector2(1.15, 1.15)
	_banner.pivot_offset = _banner.size * 0.5
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.15)
	tw.tween_interval(hold)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.3)


func _update_hud() -> void:
	for team in 2:
		_score_labels[team].text = str(match_.score[team])
	if match_.sudden_death:
		_clock_label.text = "SUDDEN DEATH"
		_clock_label.add_theme_font_size_override("font_size", 28)
		_clock_label.add_theme_color_override("font_color", UIKit.RED)
	elif rules.mode == "goals":
		_clock_label.text = "FIRST TO %d" % int(rules.goals)
		_clock_label.add_theme_font_size_override("font_size", 30)
	else:
		var t := int(ceilf(match_.time_left))
		_clock_label.text = "%d:%02d" % [t / 60, t % 60]
	if _is_online():
		_net_label.text = ("%d ms" % _rtt_ms) if _rtt_ms >= 0 else "connecting…"
		var bad := _rtt_ms > 150
		_net_label.add_theme_color_override("font_color", UIKit.RED if bad else UIKit.MUTED)


# --- Input ------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _overlay.visible or _paused:
		return
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			if pos.y < _hud.position.y + HUD_HEIGHT:
				return
			var team := _team_for_touch(pos)
			_touch_team[event.index] = team
			touch[team].press(event.index, view.screen_to_table(pos), _touch_sim(team))
		elif _touch_team.has(event.index):
			touch[_touch_team[event.index]].release(event.index)
			_touch_team.erase(event.index)
	elif event is InputEventScreenDrag:
		if _touch_team.has(event.index):
			var team: int = _touch_team[event.index]
			touch[team].drag(event.index, view.screen_to_table(event.position), _touch_sim(team))


func _team_for_touch(pos: Vector2) -> int:
	if mode == Mode.LOCAL:
		# The top half of the screen belongs to the player across the table.
		return 1 if pos.y < size.y * 0.5 else 0
	return local_team


## The guest's own rods are predicted locally, so its touches act on that copy.
func _touch_sim(team: int) -> TableSim:
	return _predicted if mode == Mode.ONLINE_GUEST else match_.sim


func _release_touches() -> void:
	for t in touch:
		if t:
			t.release_all()
	_touch_team.clear()


# --- Simulation -------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _paused:
		return
	if _waiting_for_peer:
		_wait_left -= DT
		_show_waiting()
		if _wait_left <= 0.0:
			_waiting_for_peer = false
			match_.end_by_forfeit(local_team)
			_present_events([{"type": "final", "winner": local_team}])
		return

	if _is_online():
		_ping_timer -= DT
		if _ping_timer <= 0.0:
			_ping_timer = 1.0
			Net.send({"k": "ping", "t": Time.get_ticks_msec()})

	if _runs_simulation():
		_step_match()
	else:
		_step_guest()
	_tick += 1


func _step_match() -> void:
	var inputs := [null, null]
	for team in 2:
		if touch[team]:
			inputs[team] = touch[team].inputs(match_.sim)
	if ai:
		inputs[1] = ai.compute(match_, DT)
	if mode == Mode.ONLINE_HOST:
		inputs[1] = _remote_input
	match_.tick(DT, inputs)
	_present_events(match_.events)

	if mode == Mode.ONLINE_HOST:
		for e in match_.events:
			if e.type in PRESENTED_EVENTS:
				_host_events.append(NetCodec.slim_event(e))
		if _tick % SNAPSHOT_EVERY == 0:
			Net.send({
				"k": "st",
				"n": _tick,
				"s": NetCodec.round_floats(match_.sim.to_state()),
				"m": NetCodec.round_floats(match_.to_state()),
				"e": _host_events,
			})
			_host_events = []


func _step_guest() -> void:
	var t: TouchInput = touch[local_team]
	var inputs: Array = t.inputs(_predicted)
	var all := [null, null]
	all[local_team] = inputs
	_predicted.apply_inputs(all)
	for rod in _predicted.team_rods(local_team):
		rod.step(DT, _predicted.cfg)
	if _tick % INPUT_EVERY == 0:
		Net.send({"k": "in", "r": NetCodec.round_floats(inputs)})


func _process(_delta: float) -> void:
	if mode == Mode.ONLINE_GUEST:
		_render_guest()
	var holding := []
	for team in 2:
		if touch[team]:
			for i in touch[team].active_rods():
				holding.append(team * match_.sim.rods_per_team + i)
	view.highlighted = holding
	if match_.phase == Match.Phase.COUNTDOWN:
		view.drop_progress = clampf(1.0 - match_.phase_time / Match.COUNTDOWN_TIME, 0.0, 1.0)
	else:
		view.drop_progress = 1.0
	_update_hud()


# --- Presentation -----------------------------------------------------------

func _present_events(events: Array) -> void:
	for e in events:
		var strength := float(e.get("strength", 0.0))
		match e.type:
			"hit":
				var s := strength / 1700.0
				Sfx.play("hit", 0.25 + s, randf_range(0.92, 1.08))
				if e.get("team", -1) == local_team and s > 0.5:
					Settings.haptic(12)
			"wall":
				Sfx.play("wall", 0.2 + strength / 2000.0)
			"post":
				Sfx.play("post", 0.4 + strength / 2000.0)
			"faceoff":
				Sfx.play("beep", 0.6)
			"puck_drop":
				Sfx.play("drop", 0.7)
			"score":
				Sfx.play("goal")
				Settings.haptic(80)
				var team := clampi(int(e.get("team", 0)), 0, 1)
				var text := "GOAL!"
				if mode == Mode.LOCAL or team != local_team:
					text = "%s SCORES!" % _team_names()[team]
				_flash(text, view.team_colors[team], 1.1)
			"sudden_death":
				Sfx.play("whistle")
				_flash("SUDDEN DEATH", UIKit.RED, 1.0)
			"final":
				if _results_pending:
					continue
				_results_pending = true
				Sfx.play("whistle")
				_flash("FINAL", UIKit.ACCENT, 0.8)
				get_tree().create_timer(1.4).timeout.connect(_show_results)


func _show_results() -> void:
	if _results_shown or not is_inside_tree():
		return
	_results_shown = true
	_release_touches()
	var s := match_.score
	var title: String
	var won := match_.winner == local_team
	if mode == Mode.LOCAL:
		title = "%s WINS" % _team_names()[match_.winner]
	else:
		title = "YOU WIN!" if won else "YOU LOSE"
	var lines := ["%s %d  –  %d %s" % [_team_names()[local_team], s[local_team], s[1 - local_team], _team_names()[1 - local_team]]]
	if match_.forfeit:
		lines.append("Opponent left, so the win is yours." if won else "You left the match.")
	if mode == Mode.AI:
		Settings.record_result("ai", s[0], s[1], won)
		lines.append("Difficulty: %s" % difficulty.capitalize())
	elif _is_online():
		Settings.record_result("online", s[local_team], s[1 - local_team], won)
	var buttons := [["Rematch", _on_rematch_pressed], ["Main Menu", _quit]]
	_show_overlay(title, lines, buttons)


func _on_rematch_pressed() -> void:
	if not _is_online():
		_restart()
		return
	if _peer_gone:
		_show_overlay("FRIEND LEFT", ["Your friend has left the game."], [["Main Menu", _quit]])
		return
	_rematch[local_team] = true
	Net.send({"k": "rematch"})
	_show_overlay("REMATCH?", ["Waiting for your friend…"], [["Main Menu", _quit]])
	_try_online_rematch()


func _try_online_rematch() -> void:
	if mode == Mode.ONLINE_HOST and _rematch[0] and _rematch[1]:
		Net.send({"k": "restart"})
		_restart()


func _restart() -> void:
	_rematch = [false, false]
	_results_shown = false
	_results_pending = false
	_release_touches()
	match_.start()
	if ai:
		ai.reset()
	_snapshots.clear()
	_hide_overlay()


func _toggle_pause() -> void:
	if _is_online() or match_.is_over():
		return
	_paused = not _paused
	_release_touches()
	if _paused:
		_show_overlay("PAUSED", [], [["Resume", _toggle_pause], ["Restart", func():
			_paused = false
			_restart()], ["Main Menu", _quit]])
	else:
		_hide_overlay()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if not _is_online() and not _paused and match_ and not match_.is_over():
			_toggle_pause()


func _quit() -> void:
	if _is_online():
		Net.send({"k": "bye"})
		Net.leave()
	exit_to_menu.emit()


# --- Online -----------------------------------------------------------------

func _on_net_message(d: Dictionary) -> void:
	match d.get("k", ""):
		"in":
			if mode == Mode.ONLINE_HOST:
				var parsed = NetCodec.parse_input(d.get("r"), match_.sim.rods_per_team)
				if parsed != null:
					_remote_input = parsed
		"st":
			if mode == Mode.ONLINE_GUEST:
				_receive_snapshot(d)
		"ping":
			Net.send({"k": "pong", "t": d.get("t", 0)})
		"pong":
			_rtt_ms = Time.get_ticks_msec() - int(d.get("t", 0))
		"rematch":
			_rematch[1 - local_team] = true
			_try_online_rematch()
		"restart":
			if mode == Mode.ONLINE_GUEST:
				_restart()
		"start":
			if mode == Mode.ONLINE_GUEST:
				_snapshots.clear()
				_clock_offset = INF
				_hide_overlay()
		"bye":
			# Leaving on purpose: no point waiting for a rejoin.
			if mode == Mode.ONLINE_HOST and not match_.is_over():
				match_.end_by_forfeit(local_team)
				_present_events([{"type": "final", "winner": local_team}])
			_on_peer_left()


func _receive_snapshot(d: Dictionary) -> void:
	if not NetCodec.valid_snapshot(d, match_.sim.rods.size()):
		return
	var n := int(d.get("n", 0))
	var now := Time.get_ticks_msec() / 1000.0
	# Smallest observed (arrival - send) offset approximates one-way latency
	# plus clock difference; snapshots are then placed on our own timeline.
	_clock_offset = minf(_clock_offset, now - n * DT)
	_snapshots.append({"time": n * DT + _clock_offset, "s": d.s, "m": d.m})
	while _snapshots.size() > 30:
		_snapshots.pop_front()
	match_.from_state(d.m)
	var events: Array = d.get("e", [])
	# The state says the match is over even if the "final" event was missed.
	if match_.is_over():
		events = events + [{"type": "final", "winner": match_.winner}]
	_present_events(events)


func _render_guest() -> void:
	if _snapshots.is_empty():
		return
	var render_time := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	var a: Dictionary = _snapshots[0]
	var b: Dictionary = _snapshots[_snapshots.size() - 1]
	for i in range(_snapshots.size() - 1):
		if _snapshots[i].time <= render_time and _snapshots[i + 1].time >= render_time:
			a = _snapshots[i]
			b = _snapshots[i + 1]
			break
	var sim := match_.sim
	sim.from_state(a.s)
	if b != a and b.time > a.time:
		var t := clampf((render_time - a.time) / (b.time - a.time), 0.0, 1.0)
		if _next_sim == null:
			_next_sim = TableSim.new(sim.cfg)
		var next := _next_sim
		next.from_state(b.s)
		# A goal or face-off teleports the puck; don't smear it across.
		if sim.puck_active == next.puck_active and sim.puck_pos.distance_to(next.puck_pos) < 200.0:
			sim.puck_pos = sim.puck_pos.lerp(next.puck_pos, t)
		else:
			sim.from_state(b.s)
		for i in sim.rods.size():
			sim.rods[i].x = lerpf(sim.rods[i].x, next.rods[i].x, t)
			sim.rods[i].angle = lerpf(sim.rods[i].angle, next.rods[i].angle, t)
	# Our own rods come from local prediction so they react instantly.
	var own := sim.team_rods(local_team)
	var mine := _predicted.team_rods(local_team)
	for i in own.size():
		own[i].x = mine[i].x
		own[i].angle = mine[i].angle


func _on_peer_left() -> void:
	if _peer_gone:
		return
	if match_.is_over():
		# Leave the results up; Rematch will explain the friend is gone.
		_peer_gone = true
		return
	if mode == Mode.ONLINE_HOST:
		_waiting_for_peer = true
		_wait_left = RECONNECT_WAIT
		_release_touches()
		_show_overlay("WAITING", ["Your friend lost connection.", ""], [["End Match", _quit]])
		_wait_label = _overlay_box.get_child(2)
		_show_waiting()
	else:
		_peer_gone = true
		_show_overlay("GAME OVER", ["The host left the game."], [["Main Menu", _quit]])


func _show_waiting() -> void:
	if is_instance_valid(_wait_label):
		_wait_label.text = "Giving them %d seconds to rejoin with code %s." % [int(ceilf(_wait_left)), Net.code]


func _on_peer_joined() -> void:
	if mode != Mode.ONLINE_HOST or _peer_gone:
		return
	if _waiting_for_peer:
		_waiting_for_peer = false
		_hide_overlay()
	Net.send({"k": "start", "rules": rules, "resume": true})


func _on_connection_lost() -> void:
	_release_touches()
	if mode == Mode.ONLINE_GUEST and not match_.is_over():
		_show_overlay("CONNECTION LOST", ["Check your connection and try again."], [
			["Reconnect", func():
				_show_overlay("RECONNECTING", ["Rejoining game %s…" % Net.code], [["Main Menu", _quit]])
				Net.rejoin()],
			["Main Menu", _quit],
		])
	else:
		_show_overlay("CONNECTION LOST", ["The online match has ended."], [["Main Menu", _quit]])


func _on_rejoined(_code: String) -> void:
	if mode == Mode.ONLINE_GUEST:
		_show_overlay("RECONNECTED", ["Waiting for the host…"], [["Main Menu", _quit]])
