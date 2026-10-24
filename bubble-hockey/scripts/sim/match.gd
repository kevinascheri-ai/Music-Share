class_name Match
extends RefCounted
## Match rules on top of the table: face-offs, scoring, the clock, sudden
## death, and the end of the game. Pure and deterministic like TableSim.

enum Phase { COUNTDOWN, PLAYING, GOAL, ENDED }

const COUNTDOWN_TIME := 1.6
const GOAL_PAUSE := 2.2

const RULES_TIMER := {"mode": "timer", "seconds": 180.0}
const RULES_GOALS := {"mode": "goals", "goals": 5}

var sim: TableSim
var rules: Dictionary
var score := [0, 0]
var time_left := 0.0
var phase: Phase = Phase.COUNTDOWN
## Seconds left in the current COUNTDOWN or GOAL phase.
var phase_time := 0.0
var sudden_death := false
var winner := -1
var forfeit := false
var last_scorer := -1
## Events produced by the last tick: the table's events plus "faceoff",
## "puck_drop", "score", "sudden_death", and "final".
var events: Array[Dictionary] = []


func _init(p_rules: Dictionary = RULES_TIMER, p_cfg: Dictionary = {}) -> void:
	rules = p_rules
	sim = TableSim.new(p_cfg)
	start()


func start() -> void:
	score = [0, 0]
	time_left = rules.get("seconds", 0.0)
	sudden_death = false
	winner = -1
	forfeit = false
	last_scorer = -1
	events.clear()
	_begin_faceoff()


func is_over() -> bool:
	return phase == Phase.ENDED


func tick(dt: float, inputs: Array) -> void:
	events.clear()
	sim.events.clear()
	sim.apply_inputs(inputs)

	match phase:
		Phase.COUNTDOWN:
			sim.step(dt)
			phase_time -= dt
			if phase_time <= 0.0:
				phase = Phase.PLAYING
				sim.puck_active = true
				events.append({"type": "puck_drop"})
		Phase.PLAYING:
			sim.step(dt)
			if rules.mode == "timer" and not sudden_death:
				time_left = maxf(time_left - dt, 0.0)
			for e in sim.events:
				if e.type == "goal":
					_on_goal(e.team)
				elif e.type == "stall":
					_begin_faceoff()
			if phase == Phase.PLAYING and rules.mode == "timer" and not sudden_death and time_left <= 0.0:
				_on_time_up()
		Phase.GOAL:
			sim.step(dt)
			phase_time -= dt
			if phase_time <= 0.0:
				_begin_faceoff()
		Phase.ENDED:
			sim.step(dt)

	var merged: Array[Dictionary] = sim.events.duplicate()
	merged.append_array(events)
	events = merged


func end_by_forfeit(winning_team: int) -> void:
	forfeit = true
	_end(winning_team)


func _on_goal(team: int) -> void:
	score[team] += 1
	last_scorer = team
	events.append({"type": "score", "team": team})
	if sudden_death:
		_end(team)
	elif rules.mode == "goals" and score[team] >= int(rules.goals):
		_end(team)
	else:
		phase = Phase.GOAL
		phase_time = GOAL_PAUSE


func _on_time_up() -> void:
	if score[0] == score[1]:
		sudden_death = true
		events.append({"type": "sudden_death"})
		_begin_faceoff()
	else:
		_end(0 if score[0] > score[1] else 1)


func _begin_faceoff() -> void:
	sim.reset_puck()
	sim.puck_active = false
	phase = Phase.COUNTDOWN
	phase_time = COUNTDOWN_TIME
	events.append({"type": "faceoff"})


func _end(winning_team: int) -> void:
	winner = winning_team
	phase = Phase.ENDED
	sim.puck_active = false
	events.append({"type": "final", "winner": winning_team})


func to_state() -> Array:
	return [score[0], score[1], time_left, phase, phase_time, sudden_death, winner, forfeit]


func from_state(s: Array) -> void:
	score = [int(s[0]), int(s[1])]
	time_left = s[2]
	phase = int(s[3]) as Phase
	phase_time = s[4]
	sudden_death = s[5]
	winner = int(s[6])
	forfeit = s[7]
