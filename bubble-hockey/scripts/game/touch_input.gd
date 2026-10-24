class_name TouchInput
extends RefCounted
## Turns touches into rod targets for one team.
##
## A touch grabs the team's rod nearest to where it lands. Dragging sideways
## slides that rod (relative to where the drag started, so nothing jumps).
## Dragging toward the opponent swings the sticks forward, dragging back
## winds them up, and a quick flick carries through as a shot. Each finger
## drives its own rod, so two thumbs can work two rods at once.
##
## All positions are table coordinates, so a flipped view needs no special
## handling: "toward the opponent" is the rod's forward direction.

## Radians of stick swing per table pixel of drag, before sensitivity.
const SPIN_PER_PIXEL := 0.02

var team: int
var slide_sensitivity := 1.0
var spin_sensitivity := 1.0

## touch index -> {rod, start, rod_x, angle}
var _touches := {}
## Per rod: [target_x, has_angle, target_angle]
var _targets: Array = []


func _init(p_team: int) -> void:
	team = p_team


func reset() -> void:
	_touches.clear()
	_targets.clear()


func press(index: int, table_pos: Vector2, sim: TableSim) -> void:
	_ensure_targets(sim)
	var rods := sim.team_rods(team)
	var best := 0
	for i in rods.size():
		if absf(rods[i].y - table_pos.y) < absf(rods[best].y - table_pos.y):
			best = i
	# One finger per rod: a new touch on a held rod takes it over.
	for k in _touches.keys():
		if _touches[k].rod == best:
			_touches.erase(k)
	_touches[index] = {
		"rod": best,
		"start": table_pos,
		"rod_x": rods[best].target_x,
		"angle": rods[best].angle,
	}
	_targets[best] = [rods[best].target_x, true, rods[best].angle]


func drag(index: int, table_pos: Vector2, sim: TableSim) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	var rod: Rod = sim.team_rods(team)[t.rod]
	var delta: Vector2 = table_pos - t.start
	var x: float = clampf(t.rod_x + delta.x * slide_sensitivity, -rod.x_range, rod.x_range)
	var angle: float = t.angle + delta.y * rod.forward_sign * SPIN_PER_PIXEL * spin_sensitivity
	var limit: float = sim.cfg.rod_angle_limit
	if absf(angle) > limit:
		# Re-anchor so swinging back starts working immediately instead of
		# having to undo the overshoot first.
		angle = signf(angle) * limit
		t.angle = angle
		t.start = Vector2(t.start.x, table_pos.y)
	_targets[t.rod] = [x, true, angle]


func release(index: int) -> void:
	if not _touches.has(index):
		return
	var rod_i: int = _touches[index].rod
	_touches.erase(index)
	if rod_i < _targets.size():
		# Let go of the spin so momentum and the return spring take over.
		_targets[rod_i] = [_targets[rod_i][0], false, 0.0]


func release_all() -> void:
	for k in _touches.keys():
		release(k)


func active_rods() -> Array:
	var out := []
	for k in _touches:
		out.append(_touches[k].rod)
	return out


func inputs(sim: TableSim) -> Array:
	_ensure_targets(sim)
	return _targets.duplicate(true)


func _ensure_targets(sim: TableSim) -> void:
	if _targets.is_empty():
		for rod in sim.team_rods(team):
			_targets.append([rod.target_x, false, 0.0])
