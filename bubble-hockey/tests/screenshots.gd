extends Node
## Renders screenshots of the main screens for visual review. It runs as a
## scene (not with -s) so the autoloads exist. Needs a display; on a headless
## machine use xvfb-run:
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/screenshots.tscn -- <out_dir>

var _out := "user://screenshots"
var _main: Control


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await _frames(2)
	var img := get_tree().root.get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
	print("saved ", name)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	Input.parse_input_event(e)


func _run() -> void:
	var settings := Settings
	settings.tutorial_seen = false
	settings.sound = false
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(90)
	await _shot("01_menu")
	_main.show_difficulty()
	await _shot("02_difficulty")
	_main.show_how_to_play(func(): pass)
	await _shot("03_how_to_play")
	_main.show_online()
	await _shot("04_online")
	_main.show_settings()
	await _shot("05_settings")

	settings.tutorial_seen = true
	_main._start_game(GameScreen.Mode.AI, {"difficulty": "medium"})
	await _frames(150)
	await _shot("06_game_ai")

	# Grab our forward rod and wind up, then flick forward.
	var game: GameScreen = _main._game
	var fwd: Rod = game.match_.sim.team_rods(0)[2]
	var grab: Vector2 = game.view.get_global_transform_with_canvas() * Vector2(game.match_.sim.center_x, fwd.y)
	_touch(0, grab, true)
	await _frames(2)
	for i in 6:
		_drag(0, grab + Vector2(-8 * i, 9 * i))
		await _frames(1)
	await _shot("07_windup_held")
	for i in 4:
		_drag(0, grab + Vector2(-48, 54 - 40 * i))
		await _frames(1)
	await _shot("08_swing")
	_touch(0, grab, false)
	print("rod after drag: x=%.1f angle=%.2f" % [fwd.x, fwd.angle])

	game._toggle_pause()
	await _shot("09_pause")
	game._toggle_pause()
	game.match_.score = [3, 2]
	game.match_.end_by_forfeit(0)
	game._show_results()
	await _shot("10_results")
	game._quit()
	await _frames(5)

	_main._start_game(GameScreen.Mode.LOCAL, {})
	await _frames(200)
	await _shot("11_pass_and_play")
	get_tree().quit()
