class_name TouchInput
extends RefCounted
## Turns touches into figure targets for one team, the way the real table's
## rods work: push/pull and twist.
##
## A touch grabs the team's figure nearest to where it lands, however far
## away, so a slightly-off thumb never does nothing. Moving the
## finger along that figure's slot slides it (relative to where the drag
## started, so nothing jumps). Moving the finger across the slot twists it:
## the figure spins, and a quick flick sends it spinning on its own for a
## slapshot. Each finger drives its own figure, so two thumbs can work two
## figures at once.
##
## All positions are table coordinates, so a camera from either end needs
## no special handling.

## Radians of spin per table pixel of sideways drag, before sensitivity.
const SPIN_PER_PIXEL := 0.045

var team: int
var slide_sensitivity := 1.0
var spin_sensitivity := 1.0

## touch index -> {fig, start, s, angle}
var _touches := {}
## Per figure: [target_s, has_angle, target_angle]
var _targets: Array = []


func _init(p_team: int) -> void:
	team = p_team


func reset() -> void:
	_touches.clear()
	_targets.clear()


func press(index: int, table_pos: Vector2, sim: TableSim) -> void:
	_ensure_targets(sim)
	var figs := sim.team_figures(team)
	var best := 0
	var best_d := INF
	for i in figs.size():
		var d := figs[i].pos().distance_to(table_pos)
		if d < best_d:
			best_d = d
			best = i
	# One finger per figure: a new touch on a held figure takes it over.
	for k in _touches.keys():
		if _touches[k].fig == best:
			_touches.erase(k)
	var f := figs[best]
	_touches[index] = {"fig": best, "start": table_pos, "s": f.target_s, "angle": f.angle}
	_targets[best] = [f.target_s, not f.is_goalie, f.angle]


func drag(index: int, table_pos: Vector2, sim: TableSim) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	var f: Figure = sim.team_figures(team)[t.fig]
	var delta: Vector2 = table_pos - t.start
	var along := delta.dot(f.slot_dir)
	var across := delta.dot(Vector2(-f.slot_dir.y, f.slot_dir.x))
	var s: float = clampf(t.s + along * slide_sensitivity, 0.0, f.slot_len)
	if s <= 0.0 or s >= f.slot_len:
		# Re-anchor at the end of the slot so pulling back responds at once.
		t.s = s
		t.start = table_pos - Vector2(-f.slot_dir.y, f.slot_dir.x) * across
	var angle: float = t.angle + across * SPIN_PER_PIXEL * spin_sensitivity
	_targets[t.fig] = [s, not f.is_goalie, angle]


func release(index: int) -> void:
	if not _touches.has(index):
		return
	var i: int = _touches[index].fig
	_touches.erase(index)
	if i < _targets.size():
		# Let go of the twist so the figure spins on under its own momentum.
		_targets[i] = [_targets[i][0], false, 0.0]


func release_all() -> void:
	for k in _touches.keys():
		release(k)


func active_figures() -> Array:
	var out := []
	for k in _touches:
		out.append(_touches[k].fig)
	return out


func inputs(sim: TableSim) -> Array:
	_ensure_targets(sim)
	return _targets.duplicate(true)


func _ensure_targets(sim: TableSim) -> void:
	if _targets.is_empty():
		for f in sim.team_figures(team):
			_targets.append([f.target_s, false, 0.0])
