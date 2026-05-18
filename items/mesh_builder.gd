class_name MeshBuilder

## Procedural low-poly mesh factory.
##
## All meshes use flat shading: every triangle gets a face-normal so the
## faceted faces catch light individually — that is the "low-poly" look.
##
## Coordinate convention for tools:
##   +Z = tip / blade end (held pointing forward-down in player hand)
##   +Y = up in the tool's local space
##   handle runs along Z, head/blade at the +Z end

# ── Public API ────────────────────────────────────────────────────────────────

## Returns a two-surface ArrayMesh for the given tool:
##   surface 0 = handle (wood brown)
##   surface 1 = head / blade (tier colour from tool_data.color)
static func tool(tool_data: ToolItemData) -> ArrayMesh:
	match tool_data.tool_type:
		"axe":     return _axe(tool_data.color)
		"pickaxe": return _pickaxe(tool_data.color)
		"sword":   return _sword(tool_data.color)
	return null

## Low-poly boulder scaled to `size`.  One surface, single colour from caller.
static func boulder(size: Vector3) -> ArrayMesh:
	return _build_boulder(size)

# ── Material helper ───────────────────────────────────────────────────────────

static func mat(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var m          := StandardMaterial3D.new()
	m.albedo_color  = color
	m.roughness     = roughness
	m.metallic      = 0.0
	return m

# ── Low-level triangle helpers ────────────────────────────────────────────────

## Adds one flat-shaded triangle (face normal auto-computed from winding).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(n); st.add_vertex(a)
	st.set_normal(n); st.add_vertex(b)
	st.set_normal(n); st.add_vertex(c)

## Adds a flat-shaded axis-aligned box (6 faces, 12 triangles).
## cx/cy/cz = centre, sx/sy/sz = full extents.
static func _box(st: SurfaceTool,
		cx: float, cy: float, cz: float,
		sx: float, sy: float, sz: float) -> void:
	var hx := sx * 0.5; var hy := sy * 0.5; var hz := sz * 0.5
	var v := [
		Vector3(cx-hx, cy-hy, cz-hz),  # 0 bottom-left-front
		Vector3(cx+hx, cy-hy, cz-hz),  # 1 bottom-right-front
		Vector3(cx+hx, cy+hy, cz-hz),  # 2 top-right-front
		Vector3(cx-hx, cy+hy, cz-hz),  # 3 top-left-front
		Vector3(cx-hx, cy-hy, cz+hz),  # 4 bottom-left-back
		Vector3(cx+hx, cy-hy, cz+hz),  # 5 bottom-right-back
		Vector3(cx+hx, cy+hy, cz+hz),  # 6 top-right-back
		Vector3(cx-hx, cy+hy, cz+hz),  # 7 top-left-back
	]
	_tri(st, v[0], v[2], v[1]); _tri(st, v[0], v[3], v[2])  # front  (-Z)
	_tri(st, v[5], v[7], v[4]); _tri(st, v[5], v[6], v[7])  # back   (+Z)
	_tri(st, v[4], v[3], v[0]); _tri(st, v[4], v[7], v[3])  # left   (-X)
	_tri(st, v[1], v[2], v[5]); _tri(st, v[5], v[2], v[6])  # right  (+X)
	_tri(st, v[4], v[0], v[1]); _tri(st, v[4], v[1], v[5])  # bottom (-Y)
	_tri(st, v[3], v[7], v[6]); _tri(st, v[3], v[6], v[2])  # top    (+Y)

## Adds a wedge (triangular prism) tapering from full-width at z0 to a thin
## edge at z1.  Used for blade tips / axe bevel.
## Profile in YZ plane; extruded ±hx in X.
static func _wedge_xz(st: SurfaceTool,
		y_bot: float, y_top: float,
		z0: float, z1: float,
		hx_wide: float, hx_thin: float) -> void:
	# Face at z0 (wide)
	var bot0l := Vector3(-hx_wide, y_bot, z0)
	var bot0r := Vector3( hx_wide, y_bot, z0)
	var top0l := Vector3(-hx_wide, y_top, z0)
	var top0r := Vector3( hx_wide, y_top, z0)
	# Face at z1 (thin / sharp)
	var bot1l := Vector3(-hx_thin, y_bot, z1)
	var bot1r := Vector3( hx_thin, y_bot, z1)
	var top1l := Vector3(-hx_thin, y_top, z1)
	var top1r := Vector3( hx_thin, y_top, z1)
	# Back face (z0)
	_tri(st, bot0l, top0l, top0r); _tri(st, bot0l, top0r, bot0r)
	# Front face (z1)
	_tri(st, bot1r, top1r, top1l); _tri(st, bot1r, top1l, bot1l)
	# Left side
	_tri(st, bot0l, bot1l, top1l); _tri(st, bot0l, top1l, top0l)
	# Right side
	_tri(st, bot0r, top0r, top1r); _tri(st, bot0r, top1r, bot1r)
	# Top
	_tri(st, top0l, top1l, top1r); _tri(st, top0l, top1r, top0r)
	# Bottom
	_tri(st, bot0r, bot1r, bot1l); _tri(st, bot0r, bot1l, bot0l)

# ── Tool builders ─────────────────────────────────────────────────────────────

const _WOOD := Color(0.50, 0.31, 0.13)

static func _axe(head_col: Color) -> ArrayMesh:
	var mesh := ArrayMesh.new()

	# ── Surface 0: handle ────────────────────────────────────────────────────
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat(_WOOD))
	# Main handle shaft — runs from z=-0.24 (butt) to z=+0.14 (neck)
	_box(st, 0, 0, -0.05, 0.040, 0.040, 0.38)
	# Knuckle guard / wrap at grip centre
	_box(st, 0, 0, -0.05, 0.055, 0.055, 0.06)
	st.commit(mesh)

	# ── Surface 1: axe head ──────────────────────────────────────────────────
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat(head_col, 0.75))
	# Eye / socket — the part that grips the handle at z=+0.14
	_box(st, 0, 0, 0.17, 0.055, 0.055, 0.06)
	# Blade body — tall flat slab above handle axis
	_box(st, 0, 0.09, 0.22, 0.040, 0.28, 0.14)
	# Bevel: tapers from full thickness at z=+0.29 to a thin edge at z=+0.35
	_wedge_xz(st, -0.06, 0.24, 0.29, 0.35, 0.020, 0.004)
	# Beard (the hook below the handle line) — small downward extension
	_box(st, 0, -0.10, 0.24, 0.040, 0.08, 0.10)
	st.commit(mesh)

	return mesh


static func _pickaxe(head_col: Color) -> ArrayMesh:
	var mesh := ArrayMesh.new()

	# ── Surface 0: handle ────────────────────────────────────────────────────
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat(_WOOD))
	_box(st, 0, 0, -0.05, 0.040, 0.040, 0.38)
	_box(st, 0, 0, -0.05, 0.055, 0.055, 0.06)  # grip knuckle
	st.commit(mesh)

	# ── Surface 1: pick head ─────────────────────────────────────────────────
	# The head is a horizontal bar perpendicular to the handle (along X),
	# with both ends bent forward toward +Z.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat(head_col, 0.72))
	# Centre block that clamps to the handle
	_box(st, 0, 0, 0.17, 0.060, 0.060, 0.06)
	# Horizontal bar — the poll + pick bar running left-right
	_box(st, 0, 0, 0.17, 0.32, 0.048, 0.048)
	# Right-side pick point — juts forward (+Z)
	_box(st, 0.10, 0, 0.23, 0.048, 0.042, 0.10)
	# Right-side pick tip (tapers to point)
	_wedge_xz(st, -0.021, 0.021, 0.28, 0.35, 0.048, 0.004)
	# Left-side poll (blunt hammer face)
	_box(st, -0.12, 0, 0.20, 0.060, 0.050, 0.06)
	st.commit(mesh)

	return mesh


static func _sword(blade_col: Color) -> ArrayMesh:
	var mesh := ArrayMesh.new()

	# ── Surface 0: hilt (handle + pommel) ───────────────────────────────────
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat(_WOOD))
	# Grip
	_box(st, 0, 0, -0.08, 0.048, 0.048, 0.16)
	# Pommel — slightly wider nub at the butt end
	_box(st, 0, 0, -0.19, 0.068, 0.068, 0.06)
	st.commit(mesh)

	# ── Surface 1: blade + crossguard ───────────────────────────────────────
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat(blade_col, 0.55))
	# Crossguard — wide thin bar at z=0
	_box(st, 0, 0, 0.01, 0.22, 0.038, 0.038)
	# Ricasso (thick section just above guard)
	_box(st, 0, 0, 0.10, 0.032, 0.020, 0.16)
	# Main blade — flat and thin, tapers toward tip
	_wedge_xz(st, -0.012, 0.012, 0.18, 0.52, 0.016, 0.003)
	st.commit(mesh)

	return mesh

# ── Boulder ───────────────────────────────────────────────────────────────────

## Irregular low-poly boulder using two rings of offset vertices around apex
## and base.  Scaled to `size` (x=width, y=height, z=depth).
static func _build_boulder(size: Vector3) -> ArrayMesh:
	# Unit-space vertices — the boulder sits with its base near y=0.
	# The irregularity comes from mixing the upper and lower ring phases.
	var u := [  # upper ring, y≈0.55, 5 vertices
		Vector3( 0.68, 0.55,  0.18),
		Vector3( 0.10, 0.60,  0.75),
		Vector3(-0.70, 0.55,  0.08),
		Vector3(-0.20, 0.52, -0.72),
		Vector3( 0.62, 0.58, -0.52),
	]
	var l := [  # lower ring, y≈0.08, 5 vertices (rotated ~36° vs upper)
		Vector3( 0.90, 0.08,  0.42),
		Vector3(-0.22, 0.10,  0.90),
		Vector3(-0.88, 0.06,  0.12),
		Vector3(-0.48, 0.09, -0.82),
		Vector3( 0.72, 0.10, -0.68),
	]
	var apex := Vector3(0,  1.0, 0)
	var base := Vector3(0, -0.18, 0)

	# Scale all vertices
	for i in u.size():
		u[i] = Vector3(u[i].x * size.x, u[i].y * size.y, u[i].z * size.z)
		l[i] = Vector3(l[i].x * size.x, l[i].y * size.y, l[i].z * size.z)
	apex = Vector3(0, size.y, 0)
	base = Vector3(0, size.y * -0.18, 0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var n := u.size()  # = 5

	# Top fan: apex → upper ring
	for i in n:
		_tri(st, apex, u[i], u[(i + 1) % n])

	# Middle band: upper ring → lower ring (two tris per step)
	for i in n:
		var ni := (i + 1) % n
		_tri(st, u[i],  l[i],  u[ni])
		_tri(st, u[ni], l[i],  l[ni])

	# Bottom fan: lower ring → base
	for i in n:
		_tri(st, base, l[(i + 1) % n], l[i])

	return st.commit()
