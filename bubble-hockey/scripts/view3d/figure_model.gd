class_name FigureModel
extends RefCounted
## Builds the 3D figures: glossy painted toy players like the ones on a real
## table. If assets/skater.glb or assets/goalie.glb exist, those are used
## instead (see docs/ASSETS.md), tinted with the team color.
##
## Every model faces -Z with its stick reaching out along +X, so turning the
## node by -angle about Y points the stick where the simulation says.

const SKATER_ASSET := "res://assets/skater.glb"
const GOALIE_ASSET := "res://assets/goalie.glb"


static func build(team_color: Color, goalie: bool, stick_reach: float) -> Node3D:
	var path := GOALIE_ASSET if goalie else SKATER_ASSET
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		var node := scene.instantiate() as Node3D
		_tint(node, team_color)
		return node
	return _goalie(team_color) if goalie else _skater(team_color, stick_reach)


static func paint(color: Color, rough := 0.22, metal := 0.15) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.7
	return m


static func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 6
	return c


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 20
	s.rings = 10
	return s


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 20
	return c


static func _skater(color: Color, reach: float) -> Node3D:
	var root := Node3D.new()
	var jersey := paint(color)
	var dark := paint(color.darkened(0.45), 0.3)
	var white := paint(Color(0.96, 0.96, 0.98), 0.25)
	var chrome := paint(Color(0.85, 0.87, 0.9), 0.12, 0.95)
	var black := paint(Color(0.06, 0.06, 0.07), 0.35)
	var visor := paint(Color(0.1, 0.14, 0.2), 0.05, 0.6)

	# The rider that sits in the slot.
	_part(root, _cyl(0.15, 0.03), chrome, Vector3(0, 0.015, 0))
	# Skates and legs.
	for side in [-1.0, 1.0]:
		_part(root, _box(Vector3(0.05, 0.03, 0.13)), black, Vector3(side * 0.05, 0.05, -0.01))
		_part(root, _capsule(0.045, 0.2), dark, Vector3(side * 0.05, 0.15, 0))
	# Pants, jersey with a white stripe, shoulders.
	_part(root, _capsule(0.085, 0.16), dark, Vector3(0, 0.26, 0))
	_part(root, _capsule(0.095, 0.22), jersey, Vector3(0, 0.36, 0))
	_part(root, _cyl(0.097, 0.03), white, Vector3(0, 0.33, 0))
	_part(root, _capsule(0.06, 0.26), jersey, Vector3(0, 0.43, 0), Vector3(0, 0, PI * 0.5))
	# Arms reaching down to the stick on the right.
	_part(root, _capsule(0.035, 0.2), jersey, Vector3(0.12, 0.33, -0.03), Vector3(0.3, 0, 0.7))
	_part(root, _capsule(0.035, 0.18), jersey, Vector3(0.07, 0.33, 0.05), Vector3(-0.3, 0, 1.0))
	_part(root, _sphere(0.04), black, Vector3(0.18, 0.25, 0.0))
	# Helmet and visor.
	_part(root, _sphere(0.075), jersey, Vector3(0, 0.56, 0))
	_part(root, _box(Vector3(0.1, 0.035, 0.03)), visor, Vector3(0, 0.55, -0.065))
	# Stick: shaft from the gloves down to the ice, blade along the ice.
	var hand := Vector3(0.18, 0.25, 0.0)
	var blade := Vector3(reach - 0.07, 0.025, 0.0)
	var shaft_len := hand.distance_to(blade)
	var stick := paint(Color(0.92, 0.72, 0.4), 0.35)
	var shaft := _part(root, _box(Vector3(0.03, shaft_len, 0.03)), stick, (hand + blade) * 0.5)
	shaft.rotation = Vector3(0, 0, atan2(blade.x - hand.x, hand.y - blade.y))
	_part(root, _box(Vector3(0.16, 0.045, 0.025)), stick, Vector3(reach - 0.03, 0.022, -0.01))
	_part(root, _box(Vector3(0.08, 0.048, 0.028)), white, Vector3(reach - 0.04, 0.022, -0.01))
	return root


static func _goalie(color: Color) -> Node3D:
	var root := Node3D.new()
	var jersey := paint(color)
	var pads := paint(Color(0.97, 0.97, 0.99), 0.3)
	var trim := paint(color.darkened(0.3), 0.3)
	var chrome := paint(Color(0.85, 0.87, 0.9), 0.12, 0.95)
	var black := paint(Color(0.06, 0.06, 0.07), 0.35)
	var cage := paint(Color(0.75, 0.75, 0.78), 0.2, 0.9)

	_part(root, _box(Vector3(0.44, 0.03, 0.14)), chrome, Vector3(0, 0.015, 0))
	# Wide leg pads in a crouch.
	for side in [-1.0, 1.0]:
		_part(root, _box(Vector3(0.13, 0.26, 0.09)), pads, Vector3(side * 0.12, 0.15, -0.02), Vector3(0, 0, side * 0.12))
		_part(root, _box(Vector3(0.13, 0.03, 0.095)), trim, Vector3(side * 0.12, 0.2, -0.02), Vector3(0, 0, side * 0.12))
	_part(root, _capsule(0.12, 0.26), jersey, Vector3(0, 0.38, 0.02))
	_part(root, _capsule(0.07, 0.36), jersey, Vector3(0, 0.45, 0.02), Vector3(0, 0, PI * 0.5))
	# Blocker and catching glove.
	_part(root, _box(Vector3(0.05, 0.13, 0.09)), pads, Vector3(-0.22, 0.32, -0.05))
	_part(root, _sphere(0.07), trim, Vector3(0.22, 0.34, -0.05))
	# Mask with cage.
	_part(root, _sphere(0.08), pads, Vector3(0, 0.58, 0.01))
	_part(root, _box(Vector3(0.1, 0.07, 0.02)), cage, Vector3(0, 0.56, -0.07))
	# Stick flat on the ice in front.
	_part(root, _box(Vector3(0.3, 0.03, 0.05)), black, Vector3(-0.02, 0.02, -0.12))
	return root


## Recolors light materials on an imported model to the team color.
static func _tint(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				if m.albedo_color.get_luminance() > 0.7 and m.albedo_texture == null:
					m.albedo_color = color
				elif m.albedo_texture != null:
					m.albedo_color = color.lerp(Color.WHITE, 0.45)
				mi.set_surface_override_material(i, m)
	for c in node.get_children():
		_tint(c, color)
