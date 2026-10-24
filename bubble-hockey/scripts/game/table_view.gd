class_name TableView
extends Node2D
## Draws a TableSim with plain shapes (placeholder art, per the MVP plan).
## Set `flipped` to show the table from the top team's side.

const BOARD_MARGIN := 24.0
const NET_DEPTH := 30.0

const ICE := Color("eef6fc")
const ICE_EDGE := Color("d7e7f3")
const BOARDS := Color("fafafa")
const KICKPLATE := Color("f0c419")
const RED_LINE := Color("d23b33")
const BLUE_LINE := Color("2f6fd6")
const STICK := Color("3b2a1e")
const PUCK := Color("141414")

var sim: TableSim
var flipped := false
var team_colors := [Color("d93a32"), Color("2f6fd6")]
## Rod indexes (into sim.rods) currently held by a finger.
var highlighted: Array = []
## 0..1 while the puck is dropping in at a face-off.
var drop_progress := 1.0

var _trail: Array[Vector2] = []


func fit(rect: Rect2) -> void:
	var w := sim.width + BOARD_MARGIN * 2.0
	var h := sim.height + (BOARD_MARGIN + NET_DEPTH) * 2.0
	var s := minf(rect.size.x / w, rect.size.y / h)
	scale = Vector2(s, s)
	rotation = PI if flipped else 0.0
	var half := Vector2(sim.width, sim.height) * 0.5
	position = rect.get_center() - half.rotated(rotation) * s


func screen_to_table(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func _process(_delta: float) -> void:
	if sim == null:
		return
	if sim.puck_active and sim.puck_vel.length() > 500.0:
		_trail.append(sim.puck_pos)
		if _trail.size() > 7:
			_trail.pop_front()
	elif not _trail.is_empty():
		_trail.pop_front()
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var w := sim.width
	var h := sim.height
	var cx := sim.center_x
	var cr: float = sim.cfg.corner_radius
	var gw: float = sim.cfg.goal_width

	# Boards, kickplate, ice.
	_rounded_rect(Rect2(-BOARD_MARGIN, -BOARD_MARGIN, w + BOARD_MARGIN * 2, h + BOARD_MARGIN * 2), cr + BOARD_MARGIN, BOARDS)
	_rounded_rect(Rect2(-8, -8, w + 16, h + 16), cr + 8, KICKPLATE)
	_rounded_rect(Rect2(0, 0, w, h), cr, ICE)

	# Nets behind each goal line.
	for end in [0, 1]:
		var y0 := -NET_DEPTH if end == 0 else h
		var net := Rect2(cx - gw * 0.5, y0, gw, NET_DEPTH)
		draw_rect(net, Color(1, 1, 1, 0.9))
		for i in 7:
			var x := net.position.x + net.size.x * i / 6.0
			draw_line(Vector2(x, net.position.y), Vector2(x, net.end.y), Color(0.6, 0.6, 0.6), 1.5)
		for i in 4:
			var y := net.position.y + net.size.y * i / 3.0
			draw_line(Vector2(net.position.x, y), Vector2(net.end.x, y), Color(0.6, 0.6, 0.6), 1.5)
		draw_rect(net, RED_LINE, false, 4.0)
		var line_y := 0.0 if end == 0 else h
		# Crease.
		var crease_dir := 1.0 if end == 0 else -1.0
		var pts := PackedVector2Array()
		for i in 17:
			var a := PI * i / 16.0
			pts.append(Vector2(cx + cos(a) * 70.0, line_y + crease_dir * sin(a) * 70.0))
		draw_colored_polygon(pts, Color(0.55, 0.75, 0.95, 0.35))
		draw_polyline(pts, RED_LINE, 2.5)
		for side in [-1.0, 1.0]:
			draw_circle(Vector2(cx + side * gw * 0.5, line_y), sim.cfg.post_radius, RED_LINE)

	# Lines and circles.
	draw_line(Vector2(0, h * 0.5), Vector2(w, h * 0.5), RED_LINE, 6.0)
	for f in [0.33, 0.67]:
		draw_line(Vector2(0, h * f), Vector2(w, h * f), Color(BLUE_LINE, 0.75), 7.0)
	draw_arc(Vector2(cx, h * 0.5), 64.0, 0, TAU, 48, BLUE_LINE, 3.0)
	draw_circle(Vector2(cx, h * 0.5), 7.0, BLUE_LINE)

	# Rod slots, with a glow on the rods a finger is holding.
	for i in sim.rods.size():
		var rod := sim.rods[i]
		if i in highlighted:
			draw_rect(Rect2(0, rod.y - 26, w, 52), Color(team_colors[rod.team], 0.16))
		draw_line(Vector2(8, rod.y), Vector2(w - 8, rod.y), Color(0, 0, 0, 0.12), 3.0)

	_draw_puck()

	# Figures: stick first so the body sits on top of it.
	var stick: float = sim.cfg.stick_length
	var fr: float = sim.cfg.figure_radius
	for rod in sim.rods:
		var color: Color = team_colors[rod.team]
		for i in rod.figure_offsets.size():
			var body := rod.figure_pos(i, cx)
			var tip := rod.stick_tip(i, cx, stick)
			if body.distance_to(tip) > 2.0:
				draw_line(body, tip, STICK, 7.0)
				draw_circle(tip, 7.0, STICK)
			draw_circle(body + _screen_offset(Vector2(2, 3)), fr, Color(0, 0, 0, 0.18))
			draw_circle(body, fr, color.darkened(0.35))
			draw_circle(body, fr - 3.0, color)
			# Helmet faces the way the figure shoots.
			draw_circle(body + Vector2(0, rod.forward_sign * 5.0), 7.5, color.lightened(0.35))

	# The bubble: a faint glass highlight, always at the screen's top left.
	var glare := PackedVector2Array()
	var turn := PI if flipped else 0.0
	for i in 25:
		var a := lerpf(PI * 1.08, PI * 1.42, i / 24.0) + turn
		glare.append(Vector2(cx + cos(a) * w * 0.4, h * 0.5 + sin(a) * h * 0.42))
	draw_polyline(glare, Color(1, 1, 1, 0.5), 12.0)


func _draw_puck() -> void:
	var r: float = sim.cfg.puck_radius
	for i in _trail.size():
		var a := float(i + 1) / (_trail.size() + 1)
		draw_circle(_trail[i], r * (0.5 + 0.4 * a), Color(PUCK, 0.12 * a))
	var p := sim.puck_pos
	var scale_f := 1.0
	if not sim.puck_active:
		scale_f = lerpf(1.8, 1.0, drop_progress)
	draw_circle(p + _screen_offset(Vector2(3, 4)) * scale_f, r * scale_f, Color(0, 0, 0, 0.22))
	draw_circle(p, r * scale_f, PUCK)
	draw_arc(p, r * scale_f - 3.0, 0, TAU, 24, Color(0.35, 0.35, 0.35), 2.0)


## Shadows fall the same way on screen whichever end the player sits at.
func _screen_offset(v: Vector2) -> Vector2:
	return -v if flipped else v


func _rounded_rect(rect: Rect2, radius: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(rect.end.x - radius, rect.position.y + radius), -PI * 0.5],
		[Vector2(rect.end.x - radius, rect.end.y - radius), 0.0],
		[Vector2(rect.position.x + radius, rect.end.y - radius), PI * 0.5],
		[Vector2(rect.position.x + radius, rect.position.y + radius), PI],
	]
	for c in corners:
		for i in 9:
			var a: float = c[1] + PI * 0.5 * i / 8.0
			pts.append(c[0] + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(pts, color)
