class_name TableView3D
extends Node3D
## The table in 3D: cabinet, ice, boards, nets, the glass dome with its
## jumbotron, the figures and their rods, the puck, lighting and effects.
## It only draws a TableSim; it never changes it.
##
## One world unit is 100 table pixels. Table (x, y) maps to world (X, Z) with
## the rink centered on the origin and the ice at Y = 0.

const UNIT := 100.0
const BOARD_HEIGHT := 0.27
const BOARD_THICKNESS := 0.14
const DOME_SIZE := Vector3(4.45, 2.6, 7.45)
const DECK_SIZE := Vector3(9.4, 0.14, 15.4)
## Above the dome's crown in the menu; above the far end during a match.
const SCOREBOARD_Y := 3.4
const SCOREBOARD_END_Y := 1.25
const SCOREBOARD_END_SCALE := 0.85
## The figures are drawn larger than their collision bodies, like the real
## table's chunky toys; the stick still reaches exactly as far as physics says.
const FIGURE_SCALE := 1.5

const LOGO_ASSET := "res://assets/center_logo.png"
const PUCK_ASSET := "res://assets/puck.glb"
const CABINET_ASSET := "res://assets/cabinet.glb"
const SCOREBOARD_ASSET := "res://assets/scoreboard.glb"

var sim: TableSim
## Viewed from the top team's end (online guest).
var flipped := false
## Straight down from above (pass and play).
var overhead := false
## Slow orbit for the menu background.
var attract := false
var team_colors := [Color("e0312b"), Color("2563eb")]
## Indexes into sim.figures currently held by a finger.
var highlighted: Array = []
## 0..1 while the puck pops up at a face-off.
var drop_progress := 1.0

var camera: Camera3D
var _frame_rect := Rect2()
var _cam_target := Vector3.ZERO
var _cam_dist := 16.0
var _cam_pitch := -0.95
var _cam_yaw := 0.0
var _shake := 0.0
var _time := 0.0

var _ice_mat: ShaderMaterial
var _figure_nodes: Array[Node3D] = []
var _rings: Array[MeshInstance3D] = []
var _rods: Array[Node3D] = []
var _puck: Node3D
var _trail: Array[MeshInstance3D] = []
var _trail_points: Array[Vector3] = []
var _sparks: CPUParticles3D
var _confetti: CPUParticles3D
var _lamps: Array[MeshInstance3D] = []
var _lamp_mat: StandardMaterial3D
var _lamp_light: OmniLight3D
var _lamp_time := 0.0
var _score_labels: Array = []
var _scoreboard: Node3D
var _scoreboard_post: MeshInstance3D


# --- Coordinates ------------------------------------------------------------

func to_world(p: Vector2, y := 0.0) -> Vector3:
	return Vector3((p.x - sim.width * 0.5) / UNIT, y, (p.y - sim.height * 0.5) / UNIT)


func to_table(w: Vector3) -> Vector2:
	return Vector2(w.x * UNIT + sim.width * 0.5, w.z * UNIT + sim.height * 0.5)


## Where a screen point lands on the ice, in table pixels.
func screen_to_table(p: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(p)
	var dir := camera.project_ray_normal(p)
	if absf(dir.y) < 0.0001:
		return to_table(origin)
	var t := -origin.y / dir.y
	return to_table(origin + dir * t)


# --- Build ------------------------------------------------------------------

func _ready() -> void:
	_build_environment()
	_build_cabinet()
	_build_rink()
	_build_dome()
	_build_scoreboard()
	_build_figures()
	_build_puck()
	_build_effects()
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.1
	camera.far = 200.0
	add_child(camera)
	camera.make_current()
	if _frame_rect.size == Vector2.ZERO:
		fit(get_viewport().get_visible_rect())


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.015, 0.02, 0.06)
	sky_mat.sky_horizon_color = Color(0.13, 0.07, 0.26)
	sky_mat.ground_horizon_color = Color(0.1, 0.06, 0.2)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.02)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.62)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.88
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-62), deg_to_rad(28), 0)
	key.light_color = Color(1.0, 0.97, 0.92)
	key.light_energy = 1.15
	key.shadow_enabled = true
	key.shadow_blur = 1.5
	key.directional_shadow_max_distance = 40.0
	add_child(key)

	# Arena colour from the sides, plus the dome's overhead light.
	for spec in [[Vector3(-7, 4.5, -5), Color(0.85, 0.25, 1.0)], [Vector3(7, 4.5, 6), Color(0.15, 0.75, 1.0)]]:
		var o := OmniLight3D.new()
		o.position = spec[0]
		o.light_color = spec[1]
		o.light_energy = 2.2
		o.omni_range = 16.0
		add_child(o)
	var top := OmniLight3D.new()
	top.position = Vector3(0, 2.3, 0)
	top.light_energy = 0.7
	top.omni_range = 9.0
	add_child(top)


func _build_cabinet() -> void:
	var floor_mat := FigureModel.paint(Color(0.03, 0.03, 0.05), 0.35, 0.2)
	FigureModel._part(self, _plane(Vector2(120, 120)), floor_mat, Vector3(0, -4.4, 0))
	if ResourceLoader.exists(CABINET_ASSET):
		var cab := (load(CABINET_ASSET) as PackedScene).instantiate() as Node3D
		add_child(cab)
	else:
		var deck := FigureModel.paint(Color(0.05, 0.07, 0.14), 0.18, 0.4)
		var body := FigureModel.paint(Color(0.02, 0.02, 0.03), 0.22, 0.5)
		FigureModel._part(self, FigureModel._box(DECK_SIZE), deck, Vector3(0, -DECK_SIZE.y * 0.5, 0))
		FigureModel._part(self, FigureModel._box(Vector3(DECK_SIZE.x - 0.5, 1.3, DECK_SIZE.z - 0.5)), body, Vector3(0, -0.8, 0))
		var legs := FigureModel.paint(Color(0.6, 0.62, 0.66), 0.2, 0.9)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				FigureModel._part(self, FigureModel._box(Vector3(0.45, 3.2, 0.45)), legs, Vector3(sx * 3.9, -3.0, sz * 6.9))
	# LED strip around the deck.
	var led := StandardMaterial3D.new()
	led.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	led.albedo_color = Color(0.3, 1.6, 2.4)
	var hx := DECK_SIZE.x * 0.5
	var hz := DECK_SIZE.z * 0.5
	FigureModel._part(self, FigureModel._box(Vector3(DECK_SIZE.x + 0.04, 0.035, 0.04)), led, Vector3(0, -0.03, hz + 0.01))
	FigureModel._part(self, FigureModel._box(Vector3(DECK_SIZE.x + 0.04, 0.035, 0.04)), led, Vector3(0, -0.03, -hz - 0.01))
	FigureModel._part(self, FigureModel._box(Vector3(0.04, 0.035, DECK_SIZE.z + 0.04)), led, Vector3(hx + 0.01, -0.03, 0))
	FigureModel._part(self, FigureModel._box(Vector3(0.04, 0.035, DECK_SIZE.z + 0.04)), led, Vector3(-hx - 0.01, -0.03, 0))


func _plane(size: Vector2) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = size
	return p


func _build_rink() -> void:
	_ice_mat = ShaderMaterial.new()
	_ice_mat.shader = load("res://shaders/ice.gdshader")
	_ice_mat.set_shader_parameter("rink", Vector2(sim.width, sim.height))
	_ice_mat.set_shader_parameter("corner_radius", float(sim.cfg.corner_radius))
	_ice_mat.set_shader_parameter("goal_width", float(sim.cfg.goal_width))
	var slots: Array[Vector4] = []
	for f in sim.figures:
		slots.append(Vector4(f.slot_a.x, f.slot_a.y, f.slot_b.x, f.slot_b.y))
	_ice_mat.set_shader_parameter("slots", slots)
	_ice_mat.set_shader_parameter("slot_count", slots.size())
	if ResourceLoader.exists(LOGO_ASSET):
		_ice_mat.set_shader_parameter("logo", load(LOGO_ASSET))
		_ice_mat.set_shader_parameter("has_logo", true)
	var ice := FigureModel._part(self, _plane(Vector2(sim.width, sim.height) / UNIT), _ice_mat, Vector3(0, 0.001, 0))
	ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var kick := FigureModel.paint(Color(0.98, 0.78, 0.1), 0.3)
	var boards := FigureModel.paint(Color(0.97, 0.98, 1.0), 0.18)
	var rail := FigureModel.paint(Color(0.82, 0.85, 0.9), 0.1, 0.9)
	add_child(_walls(0.0, 0.07, kick, false))
	add_child(_walls(0.07, BOARD_HEIGHT, boards, false))
	add_child(_walls(BOARD_HEIGHT, BOARD_HEIGHT + 0.025, rail, true))

	# Nets with red posts and crossbar.
	var net_mat := ShaderMaterial.new()
	net_mat.shader = load("res://shaders/net.gdshader")
	var post := FigureModel.paint(Color(0.88, 0.1, 0.12), 0.2, 0.3)
	var gw: float = float(sim.cfg.goal_width) / UNIT
	for end in [-1.0, 1.0]:
		var line_z: float = end * sim.height * 0.5 / UNIT
		var depth := 0.34
		var net := FigureModel._part(self, FigureModel._box(Vector3(gw, BOARD_HEIGHT, depth)), net_mat, Vector3(0, BOARD_HEIGHT * 0.5, line_z + end * depth * 0.5))
		net.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for side in [-1.0, 1.0]:
			FigureModel._part(self, FigureModel._cyl(0.035, BOARD_HEIGHT), post, Vector3(side * gw * 0.5, BOARD_HEIGHT * 0.5, line_z))
		FigureModel._part(self, FigureModel._cyl(0.03, gw), post, Vector3(0, BOARD_HEIGHT, line_z), Vector3(0, 0, PI * 0.5))


## One band of the boards, following the rink's rounded outline with gaps at
## the goal mouths.
func _walls(y0: float, y1: float, mat: Material, cap: bool) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := _rink_outline()
	var t := BOARD_THICKNESS
	var cx := sim.width * 0.5
	var half_goal: float = float(sim.cfg.goal_width) * 0.5
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		if a.distance_to(b) < 0.01:
			continue
		var mid := (a + b) * 0.5
		var on_end := absf(mid.y) < 1.0 or absf(mid.y - sim.height) < 1.0
		if on_end and absf(mid.x - cx) < half_goal:
			continue
		var d := (b - a).normalized()
		var n := Vector2(d.y, -d.x)
		var a_out := a + n * t * UNIT
		var b_out := b + n * t * UNIT
		var n3 := Vector3(n.x, 0, n.y)
		if not cap:
			_quad(st, to_world(a, y0), to_world(b, y0), to_world(b, y1), to_world(a, y1), -n3)
			_quad(st, to_world(b_out, y0), to_world(a_out, y0), to_world(a_out, y1), to_world(b_out, y1), n3)
		_quad(st, to_world(a, y1), to_world(b, y1), to_world(b_out, y1), to_world(a_out, y1), Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	# Wind each triangle so its face points along n.
	var flip := (b - a).cross(c - a).dot(n) > 0.0
	for v in ([a, c, b, a, d, c] if flip else [a, b, c, a, c, d]):
		st.set_normal(n)
		st.add_vertex(v)


## The rink edge, clockwise, with points at the goal mouth edges.
func _rink_outline() -> Array:
	var w := sim.width
	var h := sim.height
	var cr: float = sim.cfg.corner_radius
	var cx := w * 0.5
	var hg: float = float(sim.cfg.goal_width) * 0.5
	var pts := []
	pts.append_array([Vector2(cr, 0), Vector2(cx - hg, 0), Vector2(cx + hg, 0), Vector2(w - cr, 0)])
	pts.append_array(_arc(Vector2(w - cr, cr), cr, -PI * 0.5, 0.0))
	pts.append(Vector2(w, h - cr))
	pts.append_array(_arc(Vector2(w - cr, h - cr), cr, 0.0, PI * 0.5))
	pts.append_array([Vector2(cx + hg, h), Vector2(cx - hg, h), Vector2(cr, h)])
	pts.append_array(_arc(Vector2(cr, h - cr), cr, PI * 0.5, PI))
	pts.append(Vector2(0, cr))
	pts.append_array(_arc(Vector2(cr, cr), cr, PI, PI * 1.5))
	return pts


func _arc(c: Vector2, r: float, a0: float, a1: float) -> Array:
	var out := []
	for i in range(1, 13):
		var a := lerpf(a0, a1, i / 12.0)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


func _build_dome() -> void:
	var glass := ShaderMaterial.new()
	glass.shader = load("res://shaders/glass.gdshader")
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.0
	sphere.is_hemisphere = true
	sphere.radial_segments = 64
	sphere.rings = 24
	var dome := FigureModel._part(self, sphere, glass, Vector3.ZERO)
	dome.scale = DOME_SIZE
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Chrome rim where the dome meets the deck.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.985
	ring.outer_radius = 1.015
	ring.rings = 96
	var rim := FigureModel._part(self, ring, FigureModel.paint(Color(0.86, 0.88, 0.92), 0.08, 1.0), Vector3(0, 0.01, 0))
	rim.scale = Vector3(DOME_SIZE.x, 1.6, DOME_SIZE.z)


func _build_scoreboard() -> void:
	var root := Node3D.new()
	root.position = Vector3(0, SCOREBOARD_Y, 0)
	add_child(root)
	_scoreboard = root
	# A mast down to the deck, shown when the board stands at the far end.
	_scoreboard_post = FigureModel._part(root, FigureModel._cyl(0.07, 1.0), FigureModel.paint(Color(0.2, 0.2, 0.24), 0.2, 0.9), Vector3.ZERO)
	_scoreboard_post.visible = false
	if ResourceLoader.exists(SCOREBOARD_ASSET):
		root.add_child((load(SCOREBOARD_ASSET) as PackedScene).instantiate())
	else:
		FigureModel._part(root, FigureModel._box(Vector3(1.9, 1.0, 1.9)), FigureModel.paint(Color(0.12, 0.13, 0.16), 0.18, 0.7), Vector3.ZERO)
		var trim := FigureModel.paint(Color(0.85, 0.87, 0.92), 0.08, 1.0)
		for y in [-0.52, 0.52]:
			FigureModel._part(root, FigureModel._box(Vector3(1.96, 0.05, 1.96)), trim, Vector3(0, y, 0))
	var screen := StandardMaterial3D.new()
	screen.albedo_color = Color(0.02, 0.03, 0.08)
	screen.emission_enabled = true
	screen.emission = Color(0.05, 0.1, 0.25)
	screen.roughness = 0.1
	for face in 4:
		var pivot := Node3D.new()
		pivot.rotation.y = face * PI * 0.5
		root.add_child(pivot)
		FigureModel._part(pivot, FigureModel._box(Vector3(1.72, 0.84, 0.01)), screen, Vector3(0, 0, 0.955))
		# Each end reads its own team on the left.
		var left_team := 1 if face == 2 else 0
		var labels := {}
		labels.clock = _led_label(pivot, "3:00", Vector3(0, 0.17, 0.965), Color(2.2, 1.7, 0.3), 120)
		labels.left = _led_label(pivot, "0", Vector3(-0.55, -0.16, 0.965), _hdr(team_colors[left_team]), 150)
		labels.right = _led_label(pivot, "0", Vector3(0.55, -0.16, 0.965), _hdr(team_colors[1 - left_team]), 150)
		labels.mid = _led_label(pivot, "BUBBLE HOCKEY", Vector3(0, -0.3, 0.965), Color(0.9, 0.95, 1.4), 40)
		labels.left_team = left_team
		_score_labels.append(labels)
	# Goal lamps on top.
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.5, 0.05, 0.05)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1, 0.1, 0.08)
	_lamp_mat.emission_energy_multiplier = 0.2
	for side in [-1.0, 1.0]:
		var lamp := FigureModel._part(root, FigureModel._sphere(0.12), _lamp_mat, Vector3(side * 0.6, 0.62, 0))
		_lamps.append(lamp)
	_lamp_light = OmniLight3D.new()
	_lamp_light.position = Vector3(0, 0.9, 0)
	_lamp_light.light_color = Color(1, 0.15, 0.1)
	_lamp_light.light_energy = 0.0
	_lamp_light.omni_range = 12.0
	root.add_child(_lamp_light)


func _hdr(c: Color) -> Color:
	return Color(c.r * 2.0 + 0.2, c.g * 2.0 + 0.2, c.b * 2.0 + 0.2)


func _led_label(parent: Node3D, text: String, pos: Vector3, color: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.pixel_size = 0.0035
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	parent.add_child(l)
	return l


func _build_figures() -> void:
	var reach: float = float(sim.cfg.stick_length) / UNIT
	var chrome := FigureModel.paint(Color(0.86, 0.88, 0.92), 0.1, 1.0)
	var grip := FigureModel.paint(Color(0.05, 0.05, 0.06), 0.6)
	for f in sim.figures:
		var node := FigureModel.build(team_colors[f.team], f.is_goalie, reach / FIGURE_SCALE)
		node.scale = Vector3.ONE * FIGURE_SCALE
		add_child(node)
		_figure_nodes.append(node)

		var ring := TorusMesh.new()
		ring.inner_radius = 0.27
		ring.outer_radius = 0.33
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = _hdr(team_colors[f.team])
		var r := FigureModel._part(self, ring, glow, Vector3.ZERO)
		r.scale = Vector3(1, 0.1, 1)
		r.visible = false
		_rings.append(r)

		# The control rod sticking out of the team's end of the cabinet.
		var rod := Node3D.new()
		add_child(rod)
		FigureModel._part(rod, FigureModel._cyl(0.028, 1.0), chrome, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
		var handle := Node3D.new()
		rod.add_child(handle)
		if f.is_goalie:
			FigureModel._part(handle, FigureModel._sphere(0.09), grip, Vector3.ZERO)
		else:
			FigureModel._part(handle, FigureModel._cyl(0.055, 0.26), grip, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
			FigureModel._part(handle, FigureModel._box(Vector3(0.02, 0.115, 0.24)), FigureModel.paint(team_colors[f.team], 0.3), Vector3.ZERO)
		_rods.append(rod)


func _build_puck() -> void:
	if ResourceLoader.exists(PUCK_ASSET):
		_puck = (load(PUCK_ASSET) as PackedScene).instantiate() as Node3D
		add_child(_puck)
	else:
		_puck = Node3D.new()
		add_child(_puck)
		var r: float = float(sim.cfg.puck_radius) / UNIT
		FigureModel._part(_puck, FigureModel._cyl(r, 0.07), FigureModel.paint(Color(0.04, 0.04, 0.045), 0.35), Vector3(0, 0.035, 0))
		FigureModel._part(_puck, FigureModel._cyl(r * 0.7, 0.072), FigureModel.paint(Color(0.12, 0.12, 0.13), 0.25), Vector3(0, 0.035, 0))
	var trail_mat := StandardMaterial3D.new()
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	trail_mat.albedo_color = Color(0.5, 0.8, 1.6, 0.35)
	var r2: float = float(sim.cfg.puck_radius) / UNIT
	for i in 8:
		var ghost := FigureModel._part(self, FigureModel._cyl(r2 * (0.45 + 0.07 * i), 0.01), trail_mat, Vector3.ZERO)
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.visible = false
		_trail.append(ghost)


func _build_effects() -> void:
	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.amount = 22
	_sparks.lifetime = 0.35
	_sparks.explosiveness = 1.0
	_sparks.direction = Vector3.UP
	_sparks.spread = 75.0
	_sparks.initial_velocity_min = 1.2
	_sparks.initial_velocity_max = 2.8
	_sparks.gravity = Vector3(0, -8, 0)
	_sparks.scale_amount_min = 0.6
	_sparks.scale_amount_max = 1.2
	var spark_mesh := FigureModel._box(Vector3(0.02, 0.02, 0.02))
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(2.4, 2.0, 1.2)
	spark_mesh.material = spark_mat
	_sparks.mesh = spark_mesh
	add_child(_sparks)

	_confetti = CPUParticles3D.new()
	_confetti.emitting = false
	_confetti.one_shot = true
	_confetti.amount = 160
	_confetti.lifetime = 2.4
	_confetti.explosiveness = 0.9
	_confetti.direction = Vector3.UP
	_confetti.spread = 50.0
	_confetti.initial_velocity_min = 3.0
	_confetti.initial_velocity_max = 5.5
	_confetti.gravity = Vector3(0, -4.5, 0)
	_confetti.damping_min = 1.0
	_confetti.damping_max = 2.0
	_confetti.angular_velocity_min = -360.0
	_confetti.angular_velocity_max = 360.0
	var conf_mesh := QuadMesh.new()
	conf_mesh.size = Vector2(0.06, 0.035)
	var conf_mat := StandardMaterial3D.new()
	conf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	conf_mat.vertex_color_use_as_albedo = true
	conf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	conf_mesh.material = conf_mat
	_confetti.mesh = conf_mesh
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(2, 0.3, 0.3), Color(2, 1.7, 0.3), Color(0.3, 0.8, 2.2), Color(1.8, 1.8, 1.8), Color(0.5, 2, 0.8)])
	_confetti.color_initial_ramp = ramp
	add_child(_confetti)


# --- Camera -----------------------------------------------------------------

## Frames the rink inside `rect` (screen pixels), leaving room for the HUD.
func fit(rect: Rect2) -> void:
	_frame_rect = rect
	if camera == null or sim == null:
		return
	if attract:
		_cam_pitch = deg_to_rad(-38.0)
		_cam_dist = 21.0
		_cam_target = Vector3(0, 0.2, 0)
		_place_scoreboard()
		_place_camera(0.0, Vector3.ZERO)
		return
	_cam_pitch = deg_to_rad(-86.0 if overhead else -49.0)
	_cam_yaw = PI if flipped else 0.0
	_cam_target = Vector3(0, 0, 0)
	_place_scoreboard()
	var hx := sim.width * 0.5 / UNIT + BOARD_THICKNESS
	var hz := sim.height * 0.5 / UNIT + BOARD_THICKNESS
	var points: Array[Vector3] = [
		Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz),
		Vector3(-hx, BOARD_HEIGHT, hz), Vector3(hx, BOARD_HEIGHT, hz),
	]
	if _scoreboard.visible:
		points.append(_scoreboard.position + Vector3(0, 0.5 * SCOREBOARD_END_SCALE, 0))
	# Search the distance that just fits, then re-center, twice.
	for pass_i in 2:
		var lo := 3.0
		var hi := 80.0
		for i in 24:
			_cam_dist = (lo + hi) * 0.5
			_place_camera(0.0, Vector3.ZERO)
			if _fits(points, rect.grow(-6.0)):
				hi = _cam_dist
			else:
				lo = _cam_dist
		_cam_dist = hi
		_place_camera(0.0, Vector3.ZERO)
		# Slide the target so the rink's picture lands centered in rect.
		var bounds := _projected_bounds(points)
		var off := rect.get_center() - bounds.get_center()
		var view_h := get_viewport().get_visible_rect().size.y
		var px_per_unit := view_h / (2.0 * _cam_dist * tan(deg_to_rad(camera.fov) * 0.5))
		var basis := camera.global_transform.basis
		_cam_target -= (basis.x * off.x - basis.y * off.y) / px_per_unit


## The menu floats the jumbotron over the dome like the real table. In a
## match it would block the ice, so it stands behind the far goal instead.
func _place_scoreboard() -> void:
	_scoreboard.visible = not overhead
	if attract:
		_scoreboard.position = Vector3(0, SCOREBOARD_Y, 0)
		_scoreboard.scale = Vector3.ONE
		_scoreboard.rotation.y = 0.0
		_scoreboard_post.visible = false
		return
	var far := -1.0 if not flipped else 1.0
	_scoreboard.position = Vector3(0, SCOREBOARD_END_Y, far * (DECK_SIZE.z * 0.5 + 0.2))
	_scoreboard.scale = Vector3.ONE * SCOREBOARD_END_SCALE
	_scoreboard_post.visible = true
	var mast := SCOREBOARD_END_Y / SCOREBOARD_END_SCALE
	_scoreboard_post.scale = Vector3(1, mast, 1)
	_scoreboard_post.position = Vector3(0, -mast * 0.5, 0)


func _place_camera(yaw_extra: float, offset: Vector3) -> void:
	var b := Basis.from_euler(Vector3(_cam_pitch, _cam_yaw + yaw_extra, 0))
	camera.global_transform = Transform3D(b, _cam_target + offset + b * Vector3(0, 0, _cam_dist))


func _fits(points: Array[Vector3], rect: Rect2) -> bool:
	for p in points:
		if camera.is_position_behind(p) or not rect.has_point(camera.unproject_position(p)):
			return false
	return true


func _projected_bounds(points: Array[Vector3]) -> Rect2:
	var r := Rect2(camera.unproject_position(points[0]), Vector2.ZERO)
	for p in points:
		r = r.expand(camera.unproject_position(p))
	return r


# --- Per frame --------------------------------------------------------------

func _process(delta: float) -> void:
	if sim == null or camera == null:
		return
	_time += delta
	_update_figures()
	_update_puck(delta)
	_update_lamps(delta)
	_update_camera(delta)


func _update_figures() -> void:
	var hz := DECK_SIZE.z * 0.5
	for i in sim.figures.size():
		var f := sim.figures[i]
		var node := _figure_nodes[i]
		node.position = to_world(f.pos())
		if f.is_goalie:
			node.rotation.y = 0.0 if f.team == 0 else PI
		else:
			node.rotation.y = -f.angle
		_rings[i].visible = i in highlighted
		_rings[i].position = to_world(f.pos(), 0.012)
		# Rods come out of the team's own end. Pulled back means more rod out.
		var end_sign := 1.0 if f.team == 0 else -1.0
		var x := f.pos().x if not f.is_goalie else sim.width * 0.5
		var out := 0.35 if f.is_goalie else 0.45 + (1.0 - f.s / f.slot_len) * 1.1
		var rod := _rods[i]
		var rod_y := -0.32 if f.is_goalie else -0.2 - 0.03 * (i % sim.figures_per_team)
		rod.position = Vector3((x - sim.width * 0.5) / UNIT, rod_y, end_sign * (hz + out * 0.5))
		var shaft := rod.get_child(0) as MeshInstance3D
		shaft.scale = Vector3(1, out, 1)
		var handle := rod.get_child(1) as Node3D
		handle.position = Vector3(0, 0, end_sign * out * 0.5)
		handle.rotation.z = f.angle


func _update_puck(delta: float) -> void:
	var p := to_world(sim.puck_pos)
	var y := 0.0
	var glow := 0.0
	if not sim.puck_active and sim.puck_pos.distance_to(Vector2(sim.width, sim.height) * 0.5) < 1.0:
		# Popping up out of the center hole.
		var t := clampf(drop_progress, 0.0, 1.0)
		y = lerpf(-0.12, 0.0, ease(t, 0.4)) + sin(t * PI) * 0.18
		glow = 1.0 - t
	_ice_mat.set_shader_parameter("pop_glow", glow)
	_puck.position = Vector3(p.x, y, p.z)
	_puck.rotation.y += sim.puck_vel.length() * 0.0004
	var speed := sim.puck_vel.length()
	if sim.puck_active and speed > 650.0:
		_trail_points.push_front(_puck.position + Vector3(0, 0.02, 0))
	elif not _trail_points.is_empty():
		_trail_points.pop_back()
	while _trail_points.size() > _trail.size():
		_trail_points.pop_back()
	for i in _trail.size():
		var ghost := _trail[i]
		ghost.visible = i < _trail_points.size() and i > 0
		if ghost.visible:
			ghost.position = _trail_points[i]
			ghost.scale = Vector3.ONE * (1.0 - i * 0.09)


func _update_lamps(delta: float) -> void:
	_lamp_time = maxf(_lamp_time - delta, 0.0)
	var on := _lamp_time > 0.0 and fmod(_lamp_time, 0.3) > 0.12
	_lamp_mat.emission_energy_multiplier = 6.0 if on else 0.2
	_lamp_light.light_energy = 3.5 if on else 0.0


func _update_camera(delta: float) -> void:
	if attract:
		_place_camera(_time * 0.12, Vector3.ZERO)
		return
	_shake = maxf(_shake - delta * 1.6, 0.0)
	# A little life: lean toward the puck and shake on goals.
	var lean := Vector3((sim.puck_pos.x - sim.width * 0.5) / UNIT * 0.05, 0, 0)
	if flipped:
		lean = -lean
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.12
	_place_camera(0.0, lean + jitter)


# --- Scoreboard and effects ----------------------------------------------------

func set_scoreboard(score: Array, clock: String, caption := "") -> void:
	for l in _score_labels:
		l.clock.text = clock
		l.left.text = str(score[l.left_team])
		l.right.text = str(score[1 - l.left_team])
		l.mid.text = caption


func effect(e: Dictionary) -> void:
	match e.get("type", ""):
		"hit":
			if float(e.get("strength", 0.0)) > 900.0:
				_sparks.position = to_world(sim.puck_pos, 0.08)
				_sparks.restart()
		"post":
			_sparks.position = to_world(sim.puck_pos, 0.15)
			_sparks.restart()
		"score":
			var team := int(e.get("team", 0))
			# The scorer attacks the far goal: team 0 scores at y = 0.
			var goal_y := 0.0 if team == 0 else sim.height
			_confetti.position = to_world(Vector2(sim.width * 0.5, goal_y), 0.3)
			_confetti.restart()
			_lamp_time = 2.4
			_shake = 1.0
