extends Control
## App shell: menus, the online lobby, and switching into a match. A
## computer-vs-computer game plays behind the menus as an attract screen.

var _menu: Control
var _attract: TableView
var _scrim: ColorRect
var _attract_match: Match
var _attract_ai: Array[AIController] = []
var _game: GameScreen
var _status: Label
var _code_edit: LineEdit


func _ready() -> void:
	theme = UIKit.make_theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	var diffs := AIController.load_difficulties()
	_attract_match = Match.new(Match.RULES_GOALS)
	_attract_ai = [AIController.new(0, diffs.medium, 1), AIController.new(1, diffs.medium, 2)]
	_attract = TableView.new()
	_attract.sim = _attract_match.sim
	add_child(_attract)
	_scrim = ColorRect.new()
	_scrim.color = Color(UIKit.BG, 0.72)
	_scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_scrim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_scrim)

	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_menu)

	resized.connect(_layout)
	_layout()

	Net.room_created.connect(_on_room_created)
	Net.joined.connect(_on_joined)
	Net.peer_joined.connect(_on_peer_joined)
	Net.message.connect(_on_lobby_message)
	Net.failed.connect(_on_net_failed)
	Net.connection_lost.connect(_on_lobby_connection_lost)

	show_main()


func _layout() -> void:
	_attract.fit(Rect2(Vector2.ZERO, size))


func _physics_process(_delta: float) -> void:
	if _game != null:
		return
	var dt := 1.0 / 60.0
	_attract_match.tick(dt, [_attract_ai[0].compute(_attract_match, dt), _attract_ai[1].compute(_attract_match, dt)])
	if _attract_match.is_over():
		_attract_match.start()


# --- Screens ----------------------------------------------------------------

func _screen(title: String, subtitle := "") -> VBoxContainer:
	UIKit.clear(_menu)
	var box := UIKit.centered_panel(_menu, 600)
	box.add_child(UIKit.label(title, 60, UIKit.ACCENT))
	if subtitle != "":
		box.add_child(UIKit.label(subtitle, 26, UIKit.MUTED))
	return box


func show_main() -> void:
	var box := _screen("BUBBLE HOCKEY", "Classic table hockey, back under the dome.")
	box.add_child(UIKit.button("Play vs Computer", show_difficulty))
	box.add_child(UIKit.button("Play a Friend Online", func(): _with_tutorial(show_online)))
	box.add_child(UIKit.button("Pass & Play", show_pass_and_play))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for b in [["How to Play", func(): show_how_to_play(show_main)], ["Settings", show_settings], ["Stats", show_stats]]:
		var btn := UIKit.button(b[0], b[1], 24)
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(btn)
	box.add_child(row)
	box.add_child(UIKit.label("v%s" % ProjectSettings.get_setting("application/config/version"), 20, UIKit.MUTED))


func show_difficulty() -> void:
	var box := _screen("VS COMPUTER", "Pick your opponent.")
	box.add_child(_match_type_row())
	var diffs := AIController.load_difficulties()
	for level in ["easy", "medium", "hard"]:
		box.add_child(UIKit.button(diffs[level].label, func():
			Settings.difficulty = level
			Settings.save()
			_with_tutorial(func(): _start_game(GameScreen.Mode.AI, {"difficulty": level}))))
	box.add_child(UIKit.button("Back", show_main))


func show_pass_and_play() -> void:
	var box := _screen("PASS & PLAY", "Lay the phone flat between you. Red plays from the bottom, Blue from the top.")
	box.add_child(_match_type_row())
	box.add_child(UIKit.button("Start", func(): _with_tutorial(func(): _start_game(GameScreen.Mode.LOCAL, {}))))
	box.add_child(UIKit.button("Back", show_main))


func _match_type_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var group := ButtonGroup.new()
	for opt in [["timer", "3 Minutes"], ["goals", "First to 5"]]:
		var b := Button.new()
		b.text = opt[1]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = Settings.match_mode == opt[0]
		b.custom_minimum_size = Vector2(0, 72)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 26)
		b.toggled.connect(func(on: bool):
			if on:
				Settings.match_mode = opt[0]
				Settings.save())
		row.add_child(b)
	return row


func show_online() -> void:
	var box := _screen("PLAY A FRIEND", "Create a game and send your friend the code, or enter theirs.")
	box.add_child(_match_type_row())
	box.add_child(UIKit.button("Create Game", func():
		_set_status("Connecting…")
		Net.host_room()))
	box.add_child(UIKit.label("Have a code?", 26, UIKit.MUTED))
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "ABCDE"
	_code_edit.max_length = 5
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.custom_minimum_size = Vector2(0, 88)
	_code_edit.add_theme_font_size_override("font_size", 44)
	_code_edit.text_changed.connect(func(t: String):
		var up := t.to_upper()
		if up != t:
			var caret := _code_edit.caret_column
			_code_edit.text = up
			_code_edit.caret_column = caret)
	_code_edit.text_submitted.connect(func(_t): _join())
	box.add_child(_code_edit)
	box.add_child(UIKit.button("Join Game", _join))
	_status = UIKit.label("", 26, UIKit.MUTED)
	box.add_child(_status)
	box.add_child(UIKit.button("Back", func():
		Net.leave()
		show_main()))


func _join() -> void:
	var code := _code_edit.text.strip_edges().to_upper()
	if code.length() != 5:
		_set_status("Codes are 5 letters and numbers.")
		return
	_set_status("Joining…")
	Net.join_room(code)


func _set_status(text: String) -> void:
	if is_instance_valid(_status):
		_status.text = text


func _show_hosting(code: String) -> void:
	var box := _screen("YOUR GAME", "Send this code to your friend.")
	var code_label := UIKit.label(code, 96, UIKit.TEXT)
	box.add_child(code_label)
	box.add_child(UIKit.button("Copy Code", func():
		DisplayServer.clipboard_set(code)
		_set_status("Copied! Paste it in a message to your friend.")))
	_status = UIKit.label("Waiting for your friend to join…", 26, UIKit.MUTED)
	box.add_child(_status)
	box.add_child(UIKit.button("Cancel", func():
		Net.leave()
		show_online()))


func show_settings() -> void:
	var box := _screen("SETTINGS")
	box.add_child(_slider("Slide sensitivity", Settings.slide_sensitivity, func(v): Settings.slide_sensitivity = v))
	box.add_child(_slider("Swing sensitivity", Settings.spin_sensitivity, func(v): Settings.spin_sensitivity = v))
	box.add_child(_toggle("Sound effects", Settings.sound, func(on): Settings.sound = on))
	box.add_child(_toggle("Crowd noise", Settings.ambience, func(on): Settings.ambience = on))
	box.add_child(_toggle("Vibration", Settings.haptics, func(on): Settings.haptics = on))
	box.add_child(UIKit.label("Online server", 24, UIKit.MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	var server := LineEdit.new()
	server.text = Settings.server_url
	server.custom_minimum_size = Vector2(0, 72)
	server.add_theme_font_size_override("font_size", 24)
	server.text_changed.connect(func(t: String): Settings.server_url = t.strip_edges())
	box.add_child(server)
	box.add_child(UIKit.button("Done", func():
		if Settings.server_url == "":
			Settings.server_url = Settings.DEFAULT_SERVER
		Settings.save()
		show_main()))


func _slider(text: String, value: float, on_change: Callable) -> Control:
	var v := UIKit.column(4)
	var title := UIKit.label("%s: %.1fx" % [text, value], 26, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	v.add_child(title)
	var s := HSlider.new()
	s.min_value = 0.5
	s.max_value = 2.0
	s.step = 0.1
	s.value = value
	s.custom_minimum_size = Vector2(0, 48)
	s.value_changed.connect(func(x: float):
		title.text = "%s: %.1fx" % [text, x]
		on_change.call(x))
	v.add_child(s)
	return v


func _toggle(text: String, on: bool, on_change: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.custom_minimum_size = Vector2(0, 64)
	c.add_theme_font_size_override("font_size", 26)
	c.toggled.connect(func(x: bool):
		on_change.call(x)
		Sfx.play("click"))
	return c


func show_stats() -> void:
	var s := Settings.stats
	var box := _screen("STATS", "Saved on this device.")
	var played: int = s.wins + s.losses
	var lines := [
		"Games: %d   Wins: %d   Losses: %d" % [played, s.wins, s.losses],
		"Goals for: %d   Against: %d" % [s.goals_for, s.goals_against],
		"Vs computer: %d–%d" % [s.ai_wins, s.ai_losses],
		"Online: %d–%d" % [s.online_wins, s.online_losses],
	]
	for l in lines:
		box.add_child(UIKit.label(l, 28))
	box.add_child(UIKit.button("Back", show_main))


func show_how_to_play(done: Callable) -> void:
	var box := _screen("HOW TO PLAY")
	var tips := [
		"Your three rods are the rows nearest you: goalie, defense, and forwards.",
		"Touch a row and drag left or right to slide it.",
		"Drag toward the other goal to swing your sticks. Pull back first, then flick forward for a hard shot.",
		"Use two thumbs to work two rods at once. Held rods glow.",
		"Most goals after 3 minutes wins. A tie goes to sudden death.",
	]
	for t in tips:
		box.add_child(UIKit.label("•  " + t, 26, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	box.add_child(UIKit.button("Got It", func():
		Settings.tutorial_seen = true
		Settings.save()
		done.call()))


## Shows the controls once, the first time a player starts any match.
func _with_tutorial(next: Callable) -> void:
	if Settings.tutorial_seen:
		next.call()
	else:
		show_how_to_play(next)


# --- Matches ----------------------------------------------------------------

func _start_game(mode: GameScreen.Mode, options: Dictionary) -> void:
	_menu.visible = false
	_attract.visible = false
	_scrim.visible = false
	_game = GameScreen.new()
	_game.setup(mode, options)
	_game.exit_to_menu.connect(_end_game)
	add_child(_game)


func _end_game() -> void:
	if _game:
		_game.queue_free()
		_game = null
	_menu.visible = true
	_attract.visible = true
	_scrim.visible = true
	show_main()


func _on_room_created(code: String) -> void:
	if _game == null:
		_show_hosting(code)


func _on_peer_joined() -> void:
	if _game == null and Net.role == Net.Role.HOST:
		_start_game(GameScreen.Mode.ONLINE_HOST, {})


func _on_joined(_code: String) -> void:
	if _game == null:
		_set_status("Joined! Waiting for the host…")


func _on_lobby_message(d: Dictionary) -> void:
	if _game == null and Net.role == Net.Role.GUEST and d.get("k") == "start":
		_start_game(GameScreen.Mode.ONLINE_GUEST, {"rules": NetCodec.parse_rules(d.get("rules"))})


func _on_net_failed(reason: String) -> void:
	if _game == null:
		_set_status(reason)


func _on_lobby_connection_lost() -> void:
	if _game == null:
		show_online()
		_set_status("Lost connection to the game server.")
