extends TestCase


func _idle(m: Match) -> Callable:
	return func(): return idle_inputs(m.sim)


## Puts the puck just in front of `team`'s target goal, heading in, with the
## defending goalie moved aside.
func _force_goal(m: Match, team: int) -> void:
	var defender := 1 - team
	var g: Figure = m.sim.team_figures(defender)[0]
	g.s = 0.0
	g.target_s = 0.0
	m.sim.puck_active = true
	if team == 0:
		m.sim.puck_pos = Vector2(m.sim.center_x, 30)
		m.sim.puck_vel = Vector2(0, -900)
	else:
		m.sim.puck_pos = Vector2(m.sim.center_x, m.sim.height - 30)
		m.sim.puck_vel = Vector2(0, 900)


func test_starts_with_faceoff_countdown() -> void:
	var m := Match.new()
	check_eq(m.phase, Match.Phase.COUNTDOWN, "match opens on a face-off")
	check(not m.sim.puck_active, "puck is held during the countdown")
	run_until(m, 200, _idle(m), func(): return m.phase == Match.Phase.PLAYING)
	check_eq(m.phase, Match.Phase.PLAYING, "countdown ends in play")
	check(m.sim.puck_active, "puck drops when play starts")


func test_goal_scores_then_faceoff() -> void:
	var m := Match.new()
	run_until(m, 200, _idle(m), func(): return m.phase == Match.Phase.PLAYING)
	_force_goal(m, 0)
	run_until(m, 60, _idle(m), func(): return m.phase != Match.Phase.PLAYING)
	check_eq(m.score, [1, 0], "goal counts for the bottom team")
	check_eq(m.phase, Match.Phase.GOAL, "goal celebration phase")
	run_until(m, 300, _idle(m), func(): return m.phase == Match.Phase.COUNTDOWN)
	check_eq(m.phase, Match.Phase.COUNTDOWN, "play resumes with a face-off")
	check_eq(m.sim.puck_pos, Vector2(m.sim.center_x, m.sim.height * 0.5), "puck back at center ice")


func test_timer_win() -> void:
	var m := Match.new({"mode": "timer", "seconds": 3.0})
	run_until(m, 200, _idle(m), func(): return m.phase == Match.Phase.PLAYING)
	_force_goal(m, 1)
	run_until(m, 2000, _idle(m), func(): return m.is_over())
	check(m.is_over(), "match ends when the clock runs out")
	check_eq(m.winner, 1, "team with more goals wins")
	check_eq(m.time_left, 0.0, "clock shows zero at the end")


func test_tie_goes_to_sudden_death() -> void:
	var m := Match.new({"mode": "timer", "seconds": 1.0})
	run_until(m, 400, _idle(m), func(): return m.sudden_death)
	check(m.sudden_death, "a tie at full time goes to sudden death")
	check(not m.is_over(), "sudden death keeps the match going")
	check_eq(m.phase, Match.Phase.COUNTDOWN, "sudden death opens with a face-off")
	run_until(m, 200, _idle(m), func(): return m.phase == Match.Phase.PLAYING)
	_force_goal(m, 0)
	run_until(m, 60, _idle(m), func(): return m.is_over())
	check(m.is_over(), "next goal ends sudden death")
	check_eq(m.winner, 0, "sudden death scorer wins")


func test_first_to_goals_mode() -> void:
	var m := Match.new({"mode": "goals", "goals": 2})
	for n in 2:
		run_until(m, 400, _idle(m), func(): return m.phase == Match.Phase.PLAYING)
		_force_goal(m, 1)
		run_until(m, 60, _idle(m), func(): return m.phase != Match.Phase.PLAYING)
	check(m.is_over(), "match ends at the goal target")
	check_eq(m.winner, 1, "first to the target wins")
	check_eq(m.score, [0, 2], "final score")


func test_goals_mode_has_no_clock() -> void:
	var m := Match.new({"mode": "goals", "goals": 3})
	run_until(m, 60 * 20, _idle(m), func(): return m.is_over())
	check(not m.is_over(), "goals mode doesn't end on time")


func test_stall_restarts_with_faceoff() -> void:
	var m := Match.new()
	run_until(m, 200, _idle(m), func(): return m.phase == Match.Phase.PLAYING)
	# On a wing's slot line, far from every figure: nothing can reach it.
	m.sim.puck_pos = Vector2(85, 300)
	m.sim.puck_vel = Vector2.ZERO
	var saw_faceoff := [false]
	run_until(m, 400, _idle(m), func():
		for e in m.events:
			if e.type == "faceoff":
				saw_faceoff[0] = true
		return saw_faceoff[0])
	check(saw_faceoff[0], "a dead puck is dropped again at center")


func test_forfeit() -> void:
	var m := Match.new()
	m.end_by_forfeit(1)
	check(m.is_over(), "forfeit ends the match")
	check(m.forfeit, "forfeit flag is set")
	check_eq(m.winner, 1, "forfeit winner")


func test_state_round_trip() -> void:
	var a := Match.new()
	a.score = [2, 3]
	a.time_left = 42.5
	a.sudden_death = true
	var b := Match.new()
	b.from_state(a.to_state())
	check_eq(b.score, [2, 3], "score survives a round trip")
	check_eq(b.time_left, 42.5, "clock survives a round trip")
	check(b.sudden_death, "sudden death survives a round trip")
