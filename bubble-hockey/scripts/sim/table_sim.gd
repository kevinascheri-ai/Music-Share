class_name TableSim
extends RefCounted
## Pure, deterministic table physics: puck, rods, walls, posts, goals.
## No nodes, no rendering, no randomness, so it can run in tests, on the
## online host, and on the device all from the same code.
##
## Coordinates: origin at the rink's top-left, x to the right, y down.
## Team 0 defends the bottom goal (y = height) and attacks the top one.
## Team 1 defends the top goal (y = 0).

const TEAMS := 2

var cfg: Dictionary
var width: float
var height: float
var center_x: float
var end_zone: float

var puck_pos := Vector2.ZERO
var puck_vel := Vector2.ZERO
## False while the puck is "above the table": during a face-off countdown
## and after a goal. An inactive puck doesn't move or collide.
var puck_active := true
var stall_time := 0.0

## Team 0's rods first, then team 1's, each in config order.
var rods: Array[Rod] = []
var rods_per_team: int
## Events from the steps since the caller last cleared them. Each is a
## Dictionary with a "type": "hit", "wall", "post", "goal", or "stall".
var events: Array[Dictionary] = []


static func default_config() -> Dictionary:
	return load("res://config/table.json").data


func _init(p_cfg: Dictionary = {}) -> void:
	cfg = p_cfg if not p_cfg.is_empty() else default_config()
	width = cfg.width
	height = cfg.height
	center_x = width * 0.5
	rods_per_team = cfg.rods.size()
	var nearest := 1.0
	for r in cfg.rods:
		nearest = minf(nearest, r.dist_from_goal)
	end_zone = nearest * height
	for team in TEAMS:
		for r in cfg.rods:
			var n: int = r.figures
			var spacing := width / n
			var y: float = height * (1.0 - r.dist_from_goal) if team == 0 else height * r.dist_from_goal
			var x_range: float
			if r.has("slide_range"):
				x_range = r.slide_range
			else:
				x_range = center_x - cfg.figure_radius - 2.0 - (n - 1) * 0.5 * spacing
			rods.append(Rod.new(team, r.role, y, n, x_range, spacing))
	reset_puck()


func team_rods(team: int) -> Array[Rod]:
	return rods.slice(team * rods_per_team, (team + 1) * rods_per_team)


func reset_puck() -> void:
	puck_pos = Vector2(center_x, height * 0.5)
	puck_vel = Vector2.ZERO
	stall_time = 0.0


## inputs[team] is an Array with one [target_x, has_angle, target_angle]
## entry per rod, or null to leave that team's targets unchanged.
func apply_inputs(inputs: Array) -> void:
	for team in TEAMS:
		if team >= inputs.size() or inputs[team] == null:
			continue
		var team_input: Array = inputs[team]
		for i in mini(team_input.size(), rods_per_team):
			var e: Array = team_input[i]
			rods[team * rods_per_team + i].set_input(e[0], e[1], e[2])


func step(dt: float) -> void:
	var substeps: int = cfg.substeps
	var h := dt / substeps
	for s in substeps:
		for rod in rods:
			rod.step(h, cfg)
		if puck_active:
			_step_puck(h)
			if not puck_active:
				return


func _step_puck(h: float) -> void:
	_apply_slope(h)
	puck_vel *= exp(-float(cfg.puck_friction) * h)
	puck_vel = puck_vel.limit_length(cfg.puck_max_speed)
	puck_pos += puck_vel * h

	_collide_figures()
	_collide_walls()

	if puck_pos.y < -cfg.puck_radius * 0.5:
		_goal(0)
		return
	if puck_pos.y > height + cfg.puck_radius * 0.5:
		_goal(1)
		return

	if puck_vel.length() < cfg.stall_speed:
		stall_time += h
		if stall_time >= cfg.stall_seconds:
			stall_time = 0.0
			events.append({"type": "stall"})
	else:
		stall_time = 0.0


## The real table is molded so the puck rolls toward the figures and out of
## the corners. Only matters when the puck is slow, so it never bends a shot.
func _apply_slope(h: float) -> void:
	var speed := puck_vel.length()
	var weight := clampf(1.0 - speed / 250.0, 0.0, 1.0)
	if weight <= 0.0:
		return
	var nearest_dy := INF
	for rod in rods:
		var dy := rod.y - puck_pos.y
		if absf(dy) < absf(nearest_dy):
			nearest_dy = dy
	var accel := Vector2.ZERO
	var dead_band: float = cfg.figure_radius + cfg.puck_radius
	if absf(nearest_dy) > dead_band:
		accel.y = signf(nearest_dy) * cfg.slope_accel
	# Corners slope toward the goalie's lane, but stop short of the goal
	# mouth so the table never rolls the puck into a net on its own.
	if puck_pos.y < end_zone or puck_pos.y > height - end_zone:
		var dx := puck_pos.x - center_x
		if absf(dx) > cfg.goal_width * 0.5 + cfg.puck_radius:
			accel.x = -signf(dx) * cfg.corner_slope_accel
	puck_vel += accel * weight * h


func _collide_figures() -> void:
	var stick: float = cfg.stick_length
	var min_dist: float = cfg.figure_radius + cfg.puck_radius
	var restitution: float = cfg.figure_restitution
	# Contacts this substep, to spot a puck pinched between two figures.
	var normals: Array[Vector2] = []
	var contact_vels: Array[Vector2] = []
	for rod in rods:
		for i in rod.figure_offsets.size():
			var a := rod.figure_pos(i, center_x)
			var b := rod.stick_tip(i, center_x, stick)
			var ab := b - a
			var t := 0.0
			var len_sq := ab.length_squared()
			if len_sq > 0.0001:
				t = clampf((puck_pos - a).dot(ab) / len_sq, 0.0, 1.0)
			var q := a + ab * t
			var d := puck_pos - q
			var dist := d.length()
			if dist >= min_dist:
				continue
			var n := d / dist if dist > 0.0001 else Vector2(0, rod.forward_sign)
			puck_pos = q + n * min_dist
			var contact_vel := rod.point_velocity(t, stick)
			normals.append(n)
			contact_vels.append(contact_vel)
			var rel := puck_vel - contact_vel
			var vn := rel.dot(n)
			if vn < 0.0:
				rel -= (1.0 + restitution) * vn * n
				puck_vel = (rel + contact_vel).limit_length(cfg.puck_max_speed)
				if -vn > 60.0:
					events.append({"type": "hit", "strength": -vn, "team": rod.team})
	# A puck squeezed between two figures would otherwise ping-pong between
	# them at full speed. Let it ride along with the pair instead.
	for a in normals.size():
		for b in range(a + 1, normals.size()):
			if normals[a].dot(normals[b]) < -0.5:
				puck_vel = (contact_vels[a] + contact_vels[b]) * 0.5
				return


func _collide_walls() -> void:
	var r: float = cfg.puck_radius
	var e: float = cfg.wall_restitution
	var half_goal: float = cfg.goal_width * 0.5
	var in_mouth := absf(puck_pos.x - center_x) < half_goal

	if puck_pos.x - r < 0.0:
		puck_pos.x = r
		_bounce_x(e)
	elif puck_pos.x + r > width:
		puck_pos.x = width - r
		_bounce_x(e)

	if in_mouth:
		# Inside the goal pocket the puck is boxed in by the net's sides.
		if puck_pos.y < 0.0 or puck_pos.y > height:
			puck_pos.x = clampf(puck_pos.x, center_x - half_goal + r, center_x + half_goal - r)
	else:
		if puck_pos.y - r < 0.0:
			puck_pos.y = r
			_bounce_y(e)
		elif puck_pos.y + r > height:
			puck_pos.y = height - r
			_bounce_y(e)

	for post_y in [0.0, height]:
		for side in [-1.0, 1.0]:
			_collide_circle(Vector2(center_x + side * half_goal, post_y), cfg.post_radius, "post")

	var cr: float = cfg.corner_radius
	for c in [Vector2(cr, cr), Vector2(width - cr, cr), Vector2(cr, height - cr), Vector2(width - cr, height - cr)]:
		var beyond_x: bool = (puck_pos.x < c.x) if c.x < center_x else (puck_pos.x > c.x)
		var beyond_y: bool = (puck_pos.y < c.y) if c.y < height * 0.5 else (puck_pos.y > c.y)
		if not (beyond_x and beyond_y):
			continue
		var d: Vector2 = puck_pos - c
		var limit := cr - r
		if d.length() > limit:
			var n := d.normalized()
			puck_pos = c + n * limit
			var vn := puck_vel.dot(n)
			if vn > 0.0:
				puck_vel -= (1.0 + e) * vn * n
				_wall_event(vn)


func _collide_circle(c: Vector2, radius: float, kind: String) -> void:
	var d := puck_pos - c
	var min_dist: float = radius + cfg.puck_radius
	var dist := d.length()
	if dist >= min_dist or dist < 0.0001:
		return
	var n := d / dist
	puck_pos = c + n * min_dist
	var vn := puck_vel.dot(n)
	if vn < 0.0:
		puck_vel -= (1.0 + float(cfg.wall_restitution)) * vn * n
		if -vn > 60.0:
			events.append({"type": kind, "strength": -vn})


func _bounce_x(e: float) -> void:
	if (puck_vel.x < 0.0 and puck_pos.x < center_x) or (puck_vel.x > 0.0 and puck_pos.x > center_x):
		_wall_event(absf(puck_vel.x))
		puck_vel.x = -puck_vel.x * e


func _bounce_y(e: float) -> void:
	if (puck_vel.y < 0.0 and puck_pos.y < height * 0.5) or (puck_vel.y > 0.0 and puck_pos.y > height * 0.5):
		_wall_event(absf(puck_vel.y))
		puck_vel.y = -puck_vel.y * e


func _wall_event(strength: float) -> void:
	if strength > 60.0:
		events.append({"type": "wall", "strength": strength})


func _goal(scoring_team: int) -> void:
	puck_active = false
	puck_vel = Vector2.ZERO
	events.append({"type": "goal", "team": scoring_team})


## Compact state for network snapshots.
func to_state() -> Array:
	var r := []
	for rod in rods:
		r.append(rod.to_array())
	return [[puck_pos.x, puck_pos.y, puck_vel.x, puck_vel.y], puck_active, r]


func from_state(s: Array) -> void:
	var p: Array = s[0]
	puck_pos = Vector2(p[0], p[1])
	puck_vel = Vector2(p[2], p[3])
	puck_active = s[1]
	var r: Array = s[2]
	for i in mini(r.size(), rods.size()):
		rods[i].from_array(r[i])
