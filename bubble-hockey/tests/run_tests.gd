extends SceneTree
## Headless test runner. Run from the project folder:
##   godot --headless --path . -s res://tests/run_tests.gd
## Exits with code 1 if any test fails.

const SUITES := [
	preload("res://tests/test_sim.gd"),
	preload("res://tests/test_match.gd"),
	preload("res://tests/test_ai.gd"),
	preload("res://tests/test_net.gd"),
]


func _initialize() -> void:
	var passed := 0
	var failed := 0
	var only := OS.get_environment("TEST_ONLY")
	for suite_script in SUITES:
		var suite = suite_script.new()
		for m in suite.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			if only != "" and not name.contains(only):
				continue
			suite.failures.clear()
			var started := Time.get_ticks_msec()
			suite.call(name)
			var ms := Time.get_ticks_msec() - started
			if suite.failures.is_empty():
				passed += 1
				print("  PASS  %s (%d ms)" % [name, ms])
			else:
				failed += 1
				print("  FAIL  %s" % name)
				for f in suite.failures:
					print("        - %s" % f)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
