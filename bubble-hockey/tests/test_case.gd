class_name TestCase
extends RefCounted
## Minimal assertion helpers shared by the test suites.

const DT := 1.0 / 60.0

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func check_eq(actual, expected, msg: String) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [msg, str(expected), str(actual)])


## Inputs that hold every rod still at its current position.
func idle_inputs(sim: TableSim) -> Array:
	var out := []
	for team in TableSim.TEAMS:
		var team_in := []
		for rod in sim.team_rods(team):
			team_in.append([rod.x, false, 0.0])
		out.append(team_in)
	return out


func run_until(m: Match, max_ticks: int, inputs_fn: Callable, stop: Callable) -> int:
	for i in max_ticks:
		m.tick(DT, inputs_fn.call())
		if stop.call():
			return i
	return -1
