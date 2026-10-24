extends TestCase

const KEYS := ["label", "reaction_delay", "slide_speed", "aim_error", "shot_chance", "aim_skill", "predict", "swing_speed"]


## Plays a full AI-vs-AI match and returns it.
func _play(bottom: String, top: String, seed: int, rules: Dictionary) -> Match:
	var diffs := AIController.load_difficulties()
	var m := Match.new(rules)
	var a := AIController.new(0, diffs[bottom], seed)
	var b := AIController.new(1, diffs[top], seed + 1000)
	for i in 60 * 60 * 8:
		m.tick(DT, [a.compute(m, DT), b.compute(m, DT)])
		if m.is_over():
			break
	return m


func test_difficulty_config_is_complete_and_in_range() -> void:
	var diffs := AIController.load_difficulties()
	for level in ["easy", "medium", "hard"]:
		check(diffs.has(level), "%s difficulty exists" % level)
		var p: Dictionary = diffs.get(level, {})
		for k in KEYS:
			check(p.has(k), "%s has %s" % [level, k])
		for k in ["slide_speed", "shot_chance", "aim_skill", "predict", "swing_speed"]:
			var v: float = p.get(k, -1.0)
			check(v >= 0.0 and v <= 1.0, "%s.%s within 0..1" % [level, k])
		check(float(p.get("reaction_delay", -1)) >= 0.0, "%s reaction delay is not negative" % level)


func test_harder_levels_are_strictly_tougher() -> void:
	var d := AIController.load_difficulties()
	check(d.easy.reaction_delay > d.medium.reaction_delay and d.medium.reaction_delay > d.hard.reaction_delay, "reaction gets faster")
	check(d.easy.slide_speed < d.medium.slide_speed and d.medium.slide_speed < d.hard.slide_speed, "sliding gets faster")
	check(d.easy.aim_error > d.medium.aim_error and d.medium.aim_error > d.hard.aim_error, "aim gets tighter")


func test_ai_respects_its_slide_speed() -> void:
	var d := AIController.load_difficulties()
	var m := Match.new()
	var ai := AIController.new(1, d.easy, 3)
	m.tick(DT, [null, null])
	var before: Array = ai.compute(m, DT)
	var after: Array = ai.compute(m, DT)
	var cap: float = m.sim.cfg.max_slide_speed * d.easy.slide_speed * DT + 0.001
	for i in before.size():
		check(absf(after[i][0] - before[i][0]) <= cap, "figure %d target moves at most the easy slide cap" % i)


func test_ai_vs_ai_produces_goals_and_finishes() -> void:
	var m := _play("medium", "medium", 11, {"mode": "goals", "goals": 3})
	check(m.score[0] + m.score[1] > 0, "AI matches produce goals (%d-%d)" % [m.score[0], m.score[1]])
	check(m.is_over(), "a first-to-3 AI match finishes within 8 minutes (%d-%d)" % [m.score[0], m.score[1]])


func test_hard_beats_easy_more_often() -> void:
	var hard_wins := 0
	var hard_goals := 0
	var easy_goals := 0
	for s in 4:
		# Alternate sides so table direction can't decide the result.
		var hard_bottom := s % 2 == 0
		var m := _play("hard" if hard_bottom else "easy", "easy" if hard_bottom else "hard", 100 + s, {"mode": "goals", "goals": 3})
		var hard_team := 0 if hard_bottom else 1
		hard_goals += m.score[hard_team]
		easy_goals += m.score[1 - hard_team]
		if m.winner == hard_team:
			hard_wins += 1
	check(hard_wins >= 3, "hard wins at least 3 of 4 against easy (won %d, goals %d-%d)" % [hard_wins, hard_goals, easy_goals])


func test_same_seed_same_match() -> void:
	var a := _play("medium", "hard", 5, {"mode": "timer", "seconds": 20.0})
	var b := _play("medium", "hard", 5, {"mode": "timer", "seconds": 20.0})
	check_eq(a.sim.to_state(), b.sim.to_state(), "identical seeds and inputs give an identical table")
	check_eq(a.to_state(), b.to_state(), "identical seeds and inputs give an identical match")
