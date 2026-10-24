extends TestCase


func test_parse_input_accepts_well_formed_input() -> void:
	var r = NetCodec.parse_input([[10, true, 0.5], [-3.5, false, 0], [0.0, 1, -1.2]], 3)
	check_eq(r, [[10.0, true, 0.5], [-3.5, false, 0.0], [0.0, true, -1.2]], "numbers and flags are normalized")


func test_parse_input_rejects_malformed_input() -> void:
	check_eq(NetCodec.parse_input("nope", 3), null, "not an array")
	check_eq(NetCodec.parse_input([[0, false, 0]], 3), null, "wrong figure count")
	check_eq(NetCodec.parse_input([[0, false], [0, false, 0], [0, false, 0]], 3), null, "short figure entry")
	check_eq(NetCodec.parse_input([["x", false, 0], [0, false, 0], [0, false, 0]], 3), null, "string where a number belongs")
	check_eq(NetCodec.parse_input([[NAN, false, 0], [0, false, 0], [0, false, 0]], 3), null, "NaN is rejected")


func test_parse_rules_clamps_and_defaults() -> void:
	check_eq(NetCodec.parse_rules(null), Match.RULES_TIMER, "missing rules fall back to the timer")
	check_eq(NetCodec.parse_rules({"mode": "goals", "goals": 999}), {"mode": "goals", "goals": NetCodec.MAX_GOALS}, "goal target is capped")
	check_eq(NetCodec.parse_rules({"mode": "goals", "goals": "five"}), {"mode": "goals", "goals": 5}, "bad goal target defaults to 5")
	check_eq(NetCodec.parse_rules({"mode": "timer", "seconds": 1}), {"mode": "timer", "seconds": NetCodec.MIN_SECONDS}, "clock has a minimum")
	check_eq(NetCodec.parse_rules({"mode": "weird"}), {"mode": "timer", "seconds": 180.0}, "unknown mode becomes the 3-minute timer")


func _snapshot(m: Match) -> Dictionary:
	# Through JSON, exactly as the guest receives it.
	var d := {"k": "st", "n": 3, "s": NetCodec.round_floats(m.sim.to_state()), "m": NetCodec.round_floats(m.to_state()), "e": [{"type": "hit", "strength": 900.0, "team": 0}]}
	return JSON.parse_string(JSON.stringify(d))


func test_real_snapshot_is_valid_and_round_trips() -> void:
	var m := Match.new()
	m.sim.puck_pos = Vector2(120.123, 456.789)
	m.score = [2, 1]
	var d := _snapshot(m)
	check(NetCodec.valid_snapshot(d, m.sim.figures.size()), "a real snapshot passes validation")
	var guest := Match.new()
	guest.sim.from_state(d.s)
	guest.from_state(d.m)
	check(guest.sim.puck_pos.distance_to(m.sim.puck_pos) < 0.01, "puck position survives JSON and rounding")
	check_eq(guest.score, [2, 1], "score survives JSON")


func test_malformed_snapshots_are_rejected() -> void:
	var m := Match.new()
	var count := m.sim.figures.size()
	var good := _snapshot(m)
	var cases := {
		"missing state": func(d): d.erase("s"),
		"short puck": func(d): d.s[0] = [1, 2],
		"wrong figure count": func(d): d.s[2].pop_back(),
		"string in figure": func(d): d.s[2][0][1] = "x",
		"phase out of range": func(d): d.m[3] = 99,
		"event without type": func(d): d.e = [{"team": 1}],
		"non-bool flag": func(d): d.m[5] = 1,
	}
	for name in cases:
		var d: Dictionary = good.duplicate(true)
		cases[name].call(d)
		check(not NetCodec.valid_snapshot(d, count), "rejects snapshot with %s" % name)


func test_slim_event_keeps_only_presentation_fields() -> void:
	var e := NetCodec.slim_event({"type": "hit", "strength": 812.678, "team": 1, "secret": 5})
	check_eq(e, {"type": "hit", "strength": 813.0, "team": 1}, "slimmed hit event")
