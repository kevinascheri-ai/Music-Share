class_name AIController
extends RefCounted
## Rule-based computer opponent. Each figure works from the puck as the AI
## saw it `reaction_delay` seconds ago, slides along its slot at a capped
## speed to line up a shot, and spins when the puck is in reach. The spin
## direction is always the one that sweeps the stick toward the opponent's
## goal. Difficulty is only the numbers in config/difficulty.json.

enum Shot { IDLE, STRIKE, RECOVER }

const STRIKE_TIME := 0.32
const RECOVER_TIME := 0.2
const OPPORTUNITY_COOLDOWN := 0.3
## How long the AI looks ahead when it reads the play.
const LOOKAHEAD := 0.18

var team: int
var params: Dictionary
var rng := RandomNumberGenerator.new()
var _time := 0.0
## Ring of [time, pos, vel, active] samples of the puck, oldest first.
var _history: Array = []
var _state: Array = []
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
	_state.clear()
	_targets.clear()


func compute(m: Match, dt: float) -> Array:
	var sim := m.sim
	var figs := sim.team_figures(team)
	if _state.is_empty():
		for f in figs:
			_state.append({"shot": Shot.IDLE, "t": 0.0, "cooldown": 0.0, "aim": 0.0, "dir": 1.0, "goal": 0.0})
			_targets.append(f.s)
	_time += dt
	_history.append([_time, sim.puck_pos, sim.puck_vel, sim.puck_active])
	var delay: float = params.reaction_delay
	while _history.size() > 2 and _history[1][0] <= _time - delay:
		_history.pop_front()
	var seen: Array = _history[0]
	var p: Vector2 = seen[1]
	var v: Vector2 = seen[2]
	var active: bool = seen[3]
	var ahead := p + v * LOOKAHEAD * float(params.predict)

	var cfg := sim.cfg
	var reach: float = float(cfg.stick_length) + float(cfg.puck_radius) + 2.0
	var max_step: float = float(cfg.max_slide_speed) * float(params.slide_speed) * dt
	var goal := Vector2(sim.center_x, 0.0 if team == 0 else sim.height)
	var out := []

	for i in figs.size():
		var f: Figure = figs[i]
		var st: Dictionary = _state[i]
		st.cooldown = maxf(st.cooldown - dt, 0.0)
		st.t += dt

		var want_s := f.s
		if not active:
			want_s = _closest_s(f, Vector2(sim.center_x, sim.height * 0.5))
		elif f.is_goalie:
			want_s = _closest_s(f, Vector2(_goalie_x(p, v, f, sim), f.pos().y))
		else:
			# Line up level with the puck, nudged so the stick's sweep at the
			# contact point heads for the goal. aim_skill blends this in.
			var to_goal := (goal - ahead).normalized()
			var body := Vector2(f.pos().x, ahead.y)
			if absf(to_goal.y) > 0.2:
				body.y = ahead.y + (ahead.x - f.pos().x) * to_goal.x / to_goal.y * float(params.aim_skill)
			want_s = _closest_s(f, body + Vector2(0, st.aim))
		_targets[i] = move_toward(_targets[i], want_s, max_step)

		var has_angle := false
		var angle := f.angle
		var r := p - f.pos()
		var in_reach := active and not f.is_goalie and r.length() < reach
		match st.shot:
			Shot.IDLE:
				if in_reach and st.cooldown <= 0.0:
					st.cooldown = OPPORTUNITY_COOLDOWN
					var tangent := Vector2(-r.y, r.x)
					var dir := signf(tangent.dot(goal - p))
					if dir != 0.0 and rng.randf() < float(params.shot_chance):
						st.shot = Shot.STRIKE
						st.t = 0.0
						st.dir = dir
						st.goal = f.angle + dir * TAU
			Shot.STRIKE:
				has_angle = true
				var swing: float = float(cfg.max_spin_speed) * float(params.swing_speed) * dt
				angle = move_toward(f.angle, st.goal, swing)
				if st.t >= STRIKE_TIME or is_equal_approx(angle, st.goal):
					st.shot = Shot.RECOVER
					st.t = 0.0
			Shot.RECOVER:
				if st.t >= RECOVER_TIME:
					st.shot = Shot.IDLE
					st.t = 0.0
					st.aim = rng.randf_range(-1.0, 1.0) * float(params.aim_error)

		out.append([_targets[i], has_angle, angle])
	return out


## Slot position closest to a point.
func _closest_s(f: Figure, target: Vector2) -> float:
	return clampf((target - f.slot_a).dot(f.slot_dir), 0.0, f.slot_len)


## Where the goalie should stand: where the puck will cross the goalie's
## line, blended with where it is now by `predict`. Side-wall bounces are
## folded in.
func _goalie_x(p: Vector2, v: Vector2, f: Figure, sim: TableSim) -> float:
	var predict: float = params.predict
	var line_y := f.pos().y
	if predict <= 0.0 or absf(v.y) < 1.0:
		return p.x
	var t := (line_y - p.y) / v.y
	if t <= 0.0 or t > 1.0:
		return p.x
	var r: float = sim.cfg.puck_radius
	var span := sim.width - 2.0 * r
	var x := fposmod(p.x + v.x * t - r, 2.0 * span)
	if x > span:
		x = 2.0 * span - x
	return lerpf(p.x, x + r, predict)
