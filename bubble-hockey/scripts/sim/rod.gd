class_name Rod
extends RefCounted
## One rod: a row of figures that slide together along x and spin together
## around the rod's axis. Spinning swings each figure's stick forward or back
## along y, which is how the puck gets shot.

var team: int
var role: String
var y: float
## Offset of the rod from the table's center line, in table pixels.
var x := 0.0
var x_range: float
var figure_offsets: Array[float] = []
## +1 when "forward" (toward the opponent's goal) is +y, -1 when it is -y.
var forward_sign: float

var angle := 0.0
var ang_vel := 0.0
var vx := 0.0

## Input targets, set every tick by whoever controls this rod.
var target_x := 0.0
var target_angle := 0.0
var has_angle_target := false


func _init(p_team: int, p_role: String, p_y: float, p_figures: int, p_x_range: float, spacing: float) -> void:
	team = p_team
	role = p_role
	y = p_y
	x_range = p_x_range
	forward_sign = -1.0 if team == 0 else 1.0
	for i in p_figures:
		figure_offsets.append((i - (p_figures - 1) * 0.5) * spacing)


func set_input(p_target_x: float, p_has_angle: bool, p_target_angle: float) -> void:
	target_x = clampf(p_target_x, -x_range, x_range)
	has_angle_target = p_has_angle
	target_angle = p_target_angle


func step(dt: float, cfg: Dictionary) -> void:
	var max_slide: float = cfg.rod_max_slide_speed
	var max_spin: float = cfg.rod_max_spin_speed
	var limit: float = cfg.rod_angle_limit

	var old_x := x
	x = move_toward(x, target_x, max_slide * dt)
	x = clampf(x, -x_range, x_range)
	vx = (x - old_x) / dt

	if has_angle_target:
		var want := clampf(target_angle, -limit, limit)
		ang_vel = clampf((want - angle) / dt, -max_spin, max_spin)
	else:
		# Spring back to rest so figures don't stay wound up after a shot.
		ang_vel += (-cfg.rod_spring * angle - cfg.rod_damping * ang_vel) * dt
		ang_vel = clampf(ang_vel, -max_spin, max_spin)
	angle += ang_vel * dt
	if absf(angle) > limit:
		angle = signf(angle) * limit
		ang_vel = 0.0


## Center of figure i's body, in table coordinates.
func figure_pos(i: int, center_x: float) -> Vector2:
	return Vector2(center_x + x + figure_offsets[i], y)


## How far forward the stick tip reaches right now (negative = behind).
func reach(stick_length: float) -> float:
	return stick_length * sin(angle)


func stick_tip(i: int, center_x: float, stick_length: float) -> Vector2:
	return figure_pos(i, center_x) + Vector2(0, forward_sign * reach(stick_length))


## Velocity of a point on figure i's stick, t in [0, 1] from body to tip.
func point_velocity(t: float, stick_length: float) -> Vector2:
	return Vector2(vx, forward_sign * t * stick_length * cos(angle) * ang_vel)


func to_array() -> Array:
	return [x, angle, vx, ang_vel]


func from_array(a: Array) -> void:
	x = a[0]
	angle = a[1]
	vx = a[2]
	ang_vel = a[3]
