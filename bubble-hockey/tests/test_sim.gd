extends TestCase


func _step(sim: TableSim, ticks: int) -> void:
	for i in ticks:
		sim.apply_inputs(idle_inputs(sim))
		sim.step(DT)


func _goalie(sim: TableSim, team: int) -> Rod:
	return sim.team_rods(team)[0]


func test_layout_mirrors_between_teams() -> void:
	var sim := TableSim.new()
	check_eq(sim.rods.size(), 6, "six rods in the default layout")
	for i in sim.rods_per_team:
		var a := sim.rods[i]
		var b := sim.rods[i + sim.rods_per_team]
		check(is_equal_approx(a.y, sim.height - b.y), "rod %d mirrors across the center line" % i)
		check_eq(a.figure_offsets.size(), b.figure_offsets.size(), "same figure count on rod %d" % i)


func test_rods_stay_inside_the_boards() -> void:
	var sim := TableSim.new()
	var margin: float = sim.cfg.figure_radius
	for rod in sim.rods:
		for x in [-rod.x_range, rod.x_range]:
			rod.x = x
			for i in rod.figure_offsets.size():
				var fx := rod.figure_pos(i, sim.center_x).x
				check(fx >= margin and fx <= sim.width - margin, "%s figure %d inside at x=%.0f" % [rod.role, i, fx])


func test_rod_slide_is_speed_limited_and_clamped() -> void:
	var sim := TableSim.new()
	var rod := sim.rods[2]
	rod.set_input(10000.0, false, 0.0)
	check_eq(rod.target_x, rod.x_range, "target clamps to slide range")
	rod.step(DT, sim.cfg)
	check(absf(rod.x - sim.cfg.rod_max_slide_speed * DT) < 0.01, "slide limited to max speed in one tick")


func test_rod_spin_springs_back_to_rest() -> void:
	var sim := TableSim.new()
	var rod := sim.rods[0]
	rod.angle = 1.0
	for i in 120:
		rod.step(DT, sim.cfg)
	check(absf(rod.angle) < 0.05, "rod returns near rest without input (angle %.3f)" % rod.angle)


func test_side_wall_bounce() -> void:
	var sim := TableSim.new()
	sim.puck_pos = Vector2(40, 400)
	sim.puck_vel = Vector2(-800, 0)
	_step(sim, 10)
	check(sim.puck_vel.x > 0.0, "puck bounces off the left wall")
	check(sim.puck_pos.x >= sim.cfg.puck_radius, "puck stays inside the left wall")


func test_corner_keeps_puck_inside() -> void:
	var sim := TableSim.new()
	sim.puck_pos = Vector2(60, 60)
	sim.puck_vel = Vector2(-900, -900)
	_step(sim, 20)
	var c := Vector2(sim.cfg.corner_radius, sim.cfg.corner_radius)
	var limit: float = sim.cfg.corner_radius - sim.cfg.puck_radius + 0.5
	if sim.puck_pos.x < c.x and sim.puck_pos.y < c.y:
		check(sim.puck_pos.distance_to(c) <= limit, "puck stays inside the rounded corner")
	check(sim.puck_pos.x > 0.0 and sim.puck_pos.y > 0.0, "puck never leaves through the corner")


func test_shot_into_open_goal_scores() -> void:
	var sim := TableSim.new()
	var g := _goalie(sim, 1)
	g.x = g.x_range
	g.target_x = g.x_range
	sim.puck_pos = Vector2(sim.center_x, 45)
	sim.puck_vel = Vector2(0, -900)
	var scored := -1
	for i in 30:
		sim.step(DT)
		for e in sim.events:
			if e.type == "goal":
				scored = e.team
		if scored != -1:
			break
	check_eq(scored, 0, "bottom team scores in the top goal")
	check(not sim.puck_active, "puck is taken off the table after a goal")


func test_shot_wide_of_goal_bounces() -> void:
	var sim := TableSim.new()
	sim.puck_pos = Vector2(sim.center_x + 160, 45)
	sim.puck_vel = Vector2(0, -900)
	var goal := false
	for i in 20:
		sim.step(DT)
		for e in sim.events:
			goal = goal or e.type == "goal"
	check(not goal, "no goal when the puck hits the boards beside the net")
	check(sim.puck_vel.y > 0.0, "puck bounces back off the end boards")


func test_goalie_blocks_straight_shot() -> void:
	var sim := TableSim.new()
	var g := _goalie(sim, 1)
	sim.puck_pos = Vector2(sim.center_x, 200)
	sim.puck_vel = Vector2(0, -1000)
	var goal := false
	for i in 40:
		sim.apply_inputs(idle_inputs(sim))
		sim.step(DT)
		for e in sim.events:
			goal = goal or e.type == "goal"
	check(not goal, "centered goalie stops a straight shot")
	check(sim.puck_pos.y > g.y, "puck ends up in front of the goalie")


func test_forward_swing_shoots_puck_up_table() -> void:
	var sim := TableSim.new()
	var fwd := sim.team_rods(0)[2]
	var fig := fwd.figure_pos(1, sim.center_x)
	sim.puck_pos = fig + Vector2(0, -(sim.cfg.figure_radius + sim.cfg.puck_radius + 20))
	sim.puck_vel = Vector2.ZERO
	# Move the opposing forwards so the shooting lane is open.
	var other := sim.team_rods(1)[2]
	other.x = other.x_range
	other.target_x = other.x_range
	fwd.angle = -0.6
	var fastest := 0.0
	for i in 8:
		fwd.set_input(fwd.x, true, 1.35)
		sim.step(DT)
		fastest = minf(fastest, sim.puck_vel.y)
		check(sim.puck_vel.length() <= sim.cfg.puck_max_speed + 0.01, "shot speed is capped")
	check(fastest < -500.0, "a forward swing fires the puck toward the opponent (vy=%.0f)" % fastest)


func test_pinched_puck_does_not_explode() -> void:
	var sim := TableSim.new()
	var fwd := sim.team_rods(0)[2]
	var other := sim.team_rods(1)[2]
	var touch: float = sim.cfg.figure_radius + sim.cfg.puck_radius
	sim.puck_pos = Vector2(sim.center_x, other.y + touch + 1.0)
	sim.puck_vel = Vector2.ZERO
	fwd.angle = 1.35
	other.angle = -1.35
	for i in 30:
		fwd.set_input(fwd.x, true, 1.35)
		other.set_input(other.x, true, -1.35)
		sim.step(DT)
	check(sim.puck_vel.length() < 400.0, "a pinched puck stays calm (speed %.0f)" % sim.puck_vel.length())


func test_slow_puck_rolls_toward_a_rod() -> void:
	var sim := TableSim.new()
	var defense := sim.team_rods(0)[1]
	sim.puck_pos = Vector2(sim.center_x, defense.y - 60)
	sim.puck_vel = Vector2.ZERO
	var start_gap := _gap_to_nearest_rod(sim)
	_step(sim, 90)
	check(_gap_to_nearest_rod(sim) < start_gap, "table slope pulls a resting puck toward the figures")


func _gap_to_nearest_rod(sim: TableSim) -> float:
	var best := INF
	for rod in sim.rods:
		best = minf(best, absf(rod.y - sim.puck_pos.y))
	return best


func test_still_puck_reports_stall() -> void:
	var sim := TableSim.new()
	var defense := sim.team_rods(0)[1]
	sim.puck_pos = Vector2(sim.center_x, defense.y)
	sim.puck_vel = Vector2.ZERO
	var stalled := false
	for i in int(sim.cfg.stall_seconds * 60) + 10:
		sim.events.clear()
		sim.apply_inputs(idle_inputs(sim))
		sim.step(DT)
		for e in sim.events:
			stalled = stalled or e.type == "stall"
	check(stalled, "a puck sitting still out of reach triggers a stall")


func test_random_play_keeps_puck_in_bounds() -> void:
	var sim := TableSim.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var r: float = sim.cfg.puck_radius
	var goals := 0
	var bad := 0
	for i in 20000:
		if not sim.puck_active:
			sim.reset_puck()
			sim.puck_active = true
			sim.puck_vel = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 1200.0
		var inputs := []
		for team in 2:
			var t := []
			for rod in sim.team_rods(team):
				t.append([rng.randf_range(-rod.x_range, rod.x_range), rng.randf() < 0.5, rng.randf_range(-1.4, 1.4)])
			inputs.append(t)
		sim.events.clear()
		sim.apply_inputs(inputs)
		sim.step(DT)
		for e in sim.events:
			if e.type == "goal":
				goals += 1
		var p := sim.puck_pos
		var in_x := p.x >= r - 0.5 and p.x <= sim.width - r + 0.5
		var in_y := p.y >= -r and p.y <= sim.height + r
		if not (in_x and in_y) or sim.puck_vel.length() > sim.cfg.puck_max_speed + 0.5:
			bad += 1
	check_eq(bad, 0, "puck never escapes the rink or exceeds max speed")
	check(goals > 0, "random play still produces goals (%d)" % goals)


func test_state_round_trip() -> void:
	var a := TableSim.new()
	a.puck_pos = Vector2(123, 456)
	a.puck_vel = Vector2(7, -8)
	a.rods[3].x = 12.5
	a.rods[3].angle = 0.4
	var b := TableSim.new()
	b.from_state(a.to_state())
	check_eq(b.puck_pos, a.puck_pos, "puck position survives a round trip")
	check_eq(b.rods[3].x, 12.5, "rod position survives a round trip")
	check_eq(b.rods[3].angle, 0.4, "rod angle survives a round trip")
