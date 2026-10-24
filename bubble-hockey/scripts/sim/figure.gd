class_name Figure
extends RefCounted
## One player figure. Like the real table, a skater rides a straight slot (the
## rod pushes and pulls it along) and spins a full 360 degrees (the rod
## twists), sweeping its stick around it in the plane of the ice. The goalie
## only slides side to side and doesn't spin.

var team: int
var role: String
var is_goalie: bool
## Slot endpoints. Position s runs from 0 at `slot_a` to `slot_len` at `slot_b`.
var slot_a: Vector2
var slot_b: Vector2
var slot_dir: Vector2
var slot_len: float
## +1 when "forward" (toward the opponent's goal) is +y, -1 when it is -y.
var forward_sign: float

var s := 0.0
var vs := 0.0
## Stick direction in radians (0 = +x, increasing toward +y). Unbounded, so
## a figure can keep spinning.
var angle := 0.0
var ang_vel := 0.0

## Input targets, set every tick by whoever controls this figure.
var target_s := 0.0
var target_angle := 0.0
var has_angle_target := false


func _init(p_team: int, p_role: String, a: Vector2, b: Vector2, home: float, goalie: bool) -> void:
	team = p_team
	role = p_role
	is_goalie = goalie
	slot_a = a
	slot_b = b
	slot_len = a.distance_to(b)
	slot_dir = (b - a) / slot_len
	forward_sign = -1.0 if team == 0 else 1.0
	s = home * slot_len
	target_s = s
	angle = forward_angle()
	target_angle = angle


## Stick pointing straight at the opponent's goal.
func forward_angle() -> float:
	return PI * 0.5 * forward_sign


func pos() -> Vector2:
	return slot_a + slot_dir * s


func velocity() -> Vector2:
	return slot_dir * vs


func set_input(p_target_s: float, p_has_angle: bool, p_target_angle: float) -> void:
	target_s = clampf(p_target_s, 0.0, slot_len)
	has_angle_target = p_has_angle and not is_goalie
	target_angle = p_target_angle


func step(dt: float, cfg: Dictionary) -> void:
	var old_s := s
	s = clampf(move_toward(s, target_s, float(cfg.max_slide_speed) * dt), 0.0, slot_len)
	vs = (s - old_s) / dt
	if is_goalie:
		return
	var max_spin: float = cfg.max_spin_speed
	if has_angle_target:
		ang_vel = clampf((target_angle - angle) / dt, -max_spin, max_spin)
	else:
		# A released rod keeps spinning and slowly winds down.
		ang_vel *= exp(-float(cfg.spin_damping) * dt)
		if absf(ang_vel) < 0.05:
			ang_vel = 0.0
	angle += ang_vel * dt
	# Keep the number small without changing the direction it points.
	if absf(angle) > TAU * 64.0:
		var wrap := TAU * floorf(angle / TAU)
		angle -= wrap
		target_angle -= wrap


func stick_tip(stick_length: float) -> Vector2:
	return pos() + Vector2(cos(angle), sin(angle)) * stick_length


## Velocity of a point on the figure (the stick sweeps around the body).
func point_velocity(p: Vector2) -> Vector2:
	var r := p - pos()
	return velocity() + Vector2(-r.y, r.x) * ang_vel


func to_array() -> Array:
	return [s, angle, vs, ang_vel]


func from_array(a: Array) -> void:
	s = a[0]
	angle = a[1]
	vs = a[2]
	ang_vel = a[3]
