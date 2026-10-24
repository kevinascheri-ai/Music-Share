extends TestCase


func _step(sim: TableSim, ticks: int) -> void:
	for i in ticks:
		sim.apply_inputs(idle_inputs(sim))
		sim.step(DT)


func _fig(sim: TableSim, team: int, role: String) -> Figure:
	for f in sim.team_figures(team):
		if f.role == role:
			return f
	return null


## Moves a figure to a slot position and keeps it there.
func _park(f: Figure, s: float) -> void:
	f.s = s
	f.target_s = s


func test_layout_has_five_skaters_and_a_goalie_per_side() -> void:
	var sim := TableSim.new()
	check_eq(sim.figures.size(), 12, "twelve figures in the default layout")
	for team in 2:
		var goalies := 0
		for f in sim.team_figures(team):
			goalies += 1 if f.is_goalie else 0
		check_eq(goalies, 1, "team %d has exactly one goalie" % team)


func test_top_team_mirrors_bottom_team() -> void:
	var sim := TableSim.new()
	var corner := Vector2(sim.width, sim.height)
	for i in sim.figures_per_team:
		var a := sim.figures[i]
		var b := sim.figures[i + sim.figures_per_team]
		check(a.slot_a.is_equal_approx(corner - b.slot_a), "%s slot is rotated 180 degrees" % a.role)
		check(a.forward_sign == -b.forward_sign, "%s faces the other way" % a.role)


func test_skater_slots_run_the_length_of_the_ice() -> void:
	var sim := TableSim.new()
	for f in sim.figures:
		if f.is_goalie:
			check(absf(f.slot_dir.y) < 0.01, "goalie slides side to side")
		else:
			check(absf(f.slot_dir.x) < 0.01, "%s slot runs lengthwise" % f.role)


func test_figures_on_different_slots_never_overlap() -> void:
	var sim := TableSim.new()
	var min_gap: float = 2.0 * sim.cfg.figure_radius
	for i in sim.figures.size():
		for j in range(i + 1, sim.figures.size()):
			var a := sim.figures[i]
			var b := sim.figures[j]
			var gap := _segment_distance(a.slot_a, a.slot_b, b.slot_a, b.slot_b)
			check(gap >= min_gap, "%d:%s and %d:%s slots are %.0f apart" % [a.team, a.role, b.team, b.role, gap])


func _segment_distance(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	var best := INF
	for p in [a, b]:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, c, d)))
	for p in [c, d]:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


func test_slots_stay_inside_the_boards() -> void:
	var sim := TableSim.new()
	var r: float = sim.cfg.figure_radius
	for f in sim.figures:
		for p in [f.slot_a, f.slot_b]:
			check(p.x >= r and p.x <= sim.width - r and p.y >= r and p.y <= sim.height - r, "%s slot end %s inside the rink" % [f.role, p])


func test_slide_is_speed_limited_and_clamped() -> void:
	var sim := TableSim.new()
	var f := _fig(sim, 0, "center")
	var start := f.s
	f.set_input(100000.0, false, 0.0)
	check_eq(f.target_s, f.slot_len, "target clamps to the end of the slot")
	f.step(DT, sim.cfg)
	check(absf(f.s - start - float(sim.cfg.max_slide_speed) * DT) < 0.01, "slide limited to max speed in one tick")


func test_skaters_spin_a_full_turn_and_keep_spinning() -> void:
	var sim := TableSim.new()
	var f := _fig(sim, 0, "left_wing")
	var start := f.angle
	for i in 30:
		f.set_input(f.s, true, start + TAU * 1.5)
		f.step(DT, sim.cfg)
	check(f.angle - start > TAU, "a skater can spin more than 360 degrees")
	f.set_input(f.s, true, f.angle + 10.0)
	f.step(DT, sim.cfg)
	f.set_input(f.s, false, 0.0)
	var spinning := f.ang_vel
	f.step(DT, sim.cfg)
	check(f.ang_vel > 0.0 and f.ang_vel < spinning, "a released skater keeps spinning and slows down")


func test_goalie_does_not_spin() -> void:
	var sim := TableSim.new()
	var g := _fig(sim, 0, "goalie")
	var start := g.angle
	for i in 20:
		g.set_input(g.s, true, start + 5.0)
		g.step(DT, sim.cfg)
	check_eq(g.angle, start, "goalie only slides")


func test_side_wall_bounce() -> void:
	var sim := TableSim.new()
	sim.puck_pos = Vector2(40, 380)
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
	_park(_fig(sim, 1, "goalie"), 0.0)
	sim.puck_pos = Vector2(sim.center_x, 35)
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
	check(not sim.puck_active, "puck is taken off the ice after a goal")


func test_shot_wide_of_goal_bounces() -> void:
	var sim := TableSim.new()
	sim.puck_pos = Vector2(sim.center_x + 140, 30)
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
	var g := _fig(sim, 1, "goalie")
	sim.puck_pos = Vector2(sim.center_x, 130)
	sim.puck_vel = Vector2(0, -1000)
	var goal := false
	for i in 40:
		sim.apply_inputs(idle_inputs(sim))
		sim.step(DT)
		for e in sim.events:
			goal = goal or e.type == "goal"
	check(not goal, "centered goalie stops a straight shot")
	check(sim.puck_pos.y > g.pos().y, "puck ends up in front of the goalie")


func test_spinning_stick_fires_the_puck() -> void:
	var sim := TableSim.new()
	var c := _fig(sim, 0, "center")
	_park(_fig(sim, 1, "center"), 0.0)
	c.angle = 0.0
	# Puck just past the stick, in the direction a backward (negative) spin sweeps.
	var r := Vector2(cos(-0.6), sin(-0.6)) * 40.0
	sim.puck_pos = c.pos() + r
	sim.puck_vel = Vector2.ZERO
	var fastest := 0.0
	for i in 10:
		c.set_input(c.s, true, c.angle - 3.0)
		sim.step(DT)
		fastest = maxf(fastest, sim.puck_vel.length())
		check(sim.puck_vel.length() <= sim.cfg.puck_max_speed + 0.01, "shot speed is capped")
	check(fastest > 500.0, "a spinning stick fires the puck (%.0f)" % fastest)
	check(sim.puck_vel.y < 0.0, "the sweep sends it up the ice")


func test_body_slide_pushes_puck() -> void:
	var sim := TableSim.new()
	var w := _fig(sim, 0, "left_wing")
	w.angle = 0.0
	sim.puck_pos = w.pos() + Vector2(0, -32)
	sim.puck_vel = Vector2.ZERO
	for i in 6:
		w.set_input(w.slot_len, true, 0.0)
		sim.step(DT)
	check(sim.puck_vel.y < -300.0, "a skater pushed up its slot drives the puck ahead (vy=%.0f)" % sim.puck_vel.y)


func test_pinched_puck_does_not_explode() -> void:
	var sim := TableSim.new()
	var a := _fig(sim, 0, "center")
	var b := _fig(sim, 1, "center")
	# Bring both centers level, with the puck squeezed between their bodies.
	_park(a, a.slot_len * 0.65)
	b.s = (b.slot_a - Vector2(0, a.pos().y)).y * -b.slot_dir.y
	b.target_s = b.s
	sim.puck_pos = (a.pos() + b.pos()) * 0.5
	sim.puck_vel = Vector2.ZERO
	a.angle = PI
	b.angle = 0.0
	for i in 30:
		a.set_input(a.slot_len, true, PI)
		b.set_input(b.slot_len, true, 0.0)
		sim.step(DT)
	check(sim.puck_vel.length() < 1200.0, "a pinched puck stays sane (speed %.0f)" % sim.puck_vel.length())


func test_slow_puck_drifts_toward_a_slot() -> void:
	var sim := TableSim.new()
	sim.puck_pos = Vector2(170, 300)
	sim.puck_vel = Vector2.ZERO
	var start := _gap_to_nearest_slot(sim)
	_step(sim, 60)
	check(_gap_to_nearest_slot(sim) < start, "table slope pulls a resting puck toward the slots")


func _gap_to_nearest_slot(sim: TableSim) -> float:
	var best := INF
	for f in sim.figures:
		best = minf(best, sim.puck_pos.distance_to(Geometry2D.get_closest_point_to_segment(sim.puck_pos, f.slot_a, f.slot_b)))
	return best


func test_still_puck_reports_stall() -> void:
	var sim := TableSim.new()
	# On a wing's slot line, far from every figure.
	sim.puck_pos = Vector2(85, 300)
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
			for f in sim.team_figures(team):
				t.append([rng.randf_range(0, f.slot_len), rng.randf() < 0.5, f.angle + rng.randf_range(-3.0, 3.0)])
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
	a.figures[3].s = 12.5
	a.figures[3].angle = 4.4
	var b := TableSim.new()
	b.from_state(a.to_state())
	check_eq(b.puck_pos, a.puck_pos, "puck position survives a round trip")
	check_eq(b.figures[3].s, 12.5, "slot position survives a round trip")
	check_eq(b.figures[3].angle, 4.4, "stick angle survives a round trip")
