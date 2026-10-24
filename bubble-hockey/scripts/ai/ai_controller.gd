class_name AIController
extends RefCounted
## Rule-based computer opponent. Each rod tracks the puck as the AI saw it
## `reaction_delay` seconds ago, slides at a capped speed, aims with some
## error, and swings when the puck sits in front of a figure. Difficulty is
## only the numbers in config/difficulty.json; there is no cheating.

enum Shot { IDLE, WINDUP, STRIKE, RECOVER }

const WINDUP_ANGLE := -0.8
const WINDUP_TIME := 0.09
const STRIKE_TIME := 0.22
const RECOVER_TIME := 0.25
const OPPORTUNITY_COOLDOWN := 0.35

var team: int
var params: Dictionary
var rng := RandomNumberGenerator.new()
var _time := 0.0
## Ring of [time, pos, vel] samples of the puck, oldest first.
var _history: Array = []
var _rod_state: Array = []
var _targets: Array = []


static func load_difficulties() -> Dictionary:
	var d: Dictionary = load("res://config/difficulty.json").data.duplicate()
	d.erase("_comment")
	return d


func _init(p_team: int, p_params: Dictionary, p_seed: int = 1) -> void:
	team = p_team
	params = p_params
	rng.seed = p_seed


func reset() -> void:
	_history.clear()
	_rod_state.clear()
	_targets.clear()


func compute(m: Match, dt: float) -> Array:
	var sim := m.sim
	var rods := sim.team_rods(team)
	if _rod_state.is_empty():
		for rod in rods:
			_rod_state.append({"shot": Shot.IDLE, "t": 0.0, "cooldown": 0.0, "aim": 0.0})
			_targets.append(rod.x)
	_time += dt
	_history.append([_time, sim.puck_pos, sim.puck_vel, sim.puck_active])
	var delay: float = params.reaction_delay
	while _history.size() > 2 and _history[1][0] <= _time - delay:
		_history.pop_front()
	var seen: Array = _history[0]
	var p: Vector2 = seen[1]
	var v: Vector2 = seen[2]
	var active: bool = seen[3]

	var cfg := sim.cfg
	var stick: float = cfg.stick_length
	var touch: float = cfg.figure_radius + cfg.puck_radius
	var max_step: float = cfg.rod_max_slide_speed * float(params.slide_speed) * dt
	var goal_y := 0.0 if team == 0 else sim.height
	var out := []

	for i in rods.size():
		var rod: Rod = rods[i]
		var st: Dictionary = _rod_state[i]
		st.cooldown = maxf(st.cooldown - dt, 0.0)
		st.t += dt

		var px := _predict_x(p, v, rod.y, sim) if active else sim.center_x
		var in_front := (p.y - rod.y) * rod.forward_sign
		var shooting_zone := active and in_front > 0.0 and in_front < stick + touch - 4.0

		# Aim: hit the puck slightly off-center so it heads for the goal.
		var aim_x := px
		if shooting_zone:
			var to_goal := (Vector2(sim.center_x, goal_y) - p).normalized()
			aim_x = p.x - to_goal.x * touch * float(params.aim_skill)
		elif active and in_front < 0.0:
			# The puck is behind this rod. Touching it now mostly makes own
			# goals, so park a figure on the goal-mouth side of it: any
			# accidental contact then pushes it toward the boards instead.
			var side := signf(p.x - sim.center_x)
			if side == 0.0:
				side = 1.0
			aim_x = p.x - side * (touch + 14.0)
		aim_x += st.aim

		var best_x := rod.x
		var best_err := INF
		var best_fig := 0
		for f in rod.figure_offsets.size():
			var want := clampf(aim_x - sim.center_x - rod.figure_offsets[f], -rod.x_range, rod.x_range)
			var err := absf(aim_x - (sim.center_x + want + rod.figure_offsets[f]))
			# Prefer figures that don't need a long slide to get there.
			err += absf(want - rod.x) * 0.15
			if err < best_err:
				best_err = err
				best_x = want
				best_fig = f
		_targets[i] = move_toward(_targets[i], best_x, max_step)

		var fig_x := sim.center_x + rod.x + rod.figure_offsets[best_fig]
		var lined_up := absf(p.x - fig_x) < touch + 2.0
		var has_angle := false
		var angle := 0.0

		match st.shot:
			Shot.IDLE:
				if shooting_zone and lined_up and st.cooldown <= 0.0:
					st.cooldown = OPPORTUNITY_COOLDOWN
					if rng.randf() < float(params.shot_chance):
						st.shot = Shot.WINDUP
						st.t = 0.0
						st.aim = rng.randf_range(-1.0, 1.0) * float(params.aim_error)
			Shot.WINDUP:
				has_angle = true
				angle = WINDUP_ANGLE
				if st.t >= WINDUP_TIME:
					st.shot = Shot.STRIKE
					st.t = 0.0
			Shot.STRIKE:
				has_angle = true
				var swing: float = cfg.rod_max_spin_speed * float(params.swing_speed) * dt
				angle = rod.angle + swing
				if rod.angle >= float(cfg.rod_angle_limit) - 0.05 or st.t >= STRIKE_TIME:
					st.shot = Shot.RECOVER
					st.t = 0.0
			Shot.RECOVER:
				if st.t >= RECOVER_TIME:
					st.shot = Shot.IDLE
					st.t = 0.0
					st.aim = rng.randf_range(-1.0, 1.0) * float(params.aim_error) * 0.5

		out.append([_targets[i], has_angle, angle])
	return out


## Where the puck will cross the rod's line, blended with where it is now by
## the difficulty's `predict` value. Bounces off the side walls are folded in.
func _predict_x(p: Vector2, v: Vector2, rod_y: float, sim: TableSim) -> float:
	var predict: float = params.predict
	if predict <= 0.0 or absf(v.y) < 1.0:
		return p.x
	var t := (rod_y - p.y) / v.y
	if t <= 0.0 or t > 1.0:
		return p.x
	var r: float = sim.cfg.puck_radius
	var lo := r
	var span := sim.width - 2.0 * r
	var x := fposmod(p.x + v.x * t - lo, 2.0 * span)
	if x > span:
		x = 2.0 * span - x
	return lerpf(p.x, x + lo, predict)
