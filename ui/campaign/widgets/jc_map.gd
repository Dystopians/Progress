## 舆图（docs/57 §13）：着色地形底图 + 矢量的地区边界、图层着色、城池港口关隘、地名与数字、贸易航线。
## 底图与几何由 tools/render_map.gd 生成（assets/map/jc_base.png、jc_geo.json）。
## 图层：terrain（只看地形）/ living / unrest / unemp / logistics / literacy / industry / pop。
class_name JcMap
extends Control

signal region_selected(rid: String)
signal region_hovered(rid: String, at: Vector2)

const GEO_PATH: String = "res://assets/map/jc_geo.json"
const BASE_PATH: String = "res://assets/map/jc_base.png"
## 值越大越好的图层（颜色从橙红到青绿）；其余反过来
const GOOD_HIGH: PackedStringArray = ["living", "literacy", "industry", "pop"]

var geo: Dictionary = {}
var base_tex: Texture2D = null
var map_size: Vector2 = Vector2(1600, 1000)
var polys: Dictionary = {}          # rid → PackedVector2Array
var layer: String = "terrain"
var layer_vals: Dictionary = {}     # rid → {v, raw}
var labels_sub: Dictionary = {}     # rid → 地名下的一行字
var names: Dictionary = {}          # rid → 地名
var routes: Array = []              # [{partner, name, route, exports, imports}]
var partner_names: Dictionary = {}
var markers: Dictionary = {}        # rid → {icons: [贴图路径], alert: 警示键}
var _tex_cache: Dictionary = {}
var selected: String = ""
var hovered: String = ""
var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_load()
	set_process(true)


func _load() -> void:
	if not geo.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GEO_PATH))
	if parsed is Dictionary:
		geo = parsed
		var sz: Array = geo.get("size", [1600, 1000])
		map_size = Vector2(float(sz[0]), float(sz[1]))
		var regs: Dictionary = geo.get("regions", {})
		for rid: Variant in regs.keys():
			var pv: PackedVector2Array = PackedVector2Array()
			for p: Variant in regs[rid]:
				pv.append(Vector2(float(p[0]), float(p[1])))
			polys[String(rid)] = pv
	if ResourceLoader.exists(BASE_PATH):
		base_tex = load(BASE_PATH) as Texture2D


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	if not routes.is_empty():
		queue_redraw()


# ── 坐标 ────────────────────────────────────────────────────────────────
func _scale() -> float:
	return minf(size.x / map_size.x, size.y / map_size.y)


## 横向居中、贴顶：多出来的高度留在下面，给地区一览用。
func _offset() -> Vector2:
	return Vector2((size.x - map_size.x * _scale()) * 0.5, 0.0)


func to_local_pt(p: Vector2) -> Vector2:
	return _offset() + p * _scale()


func to_map_pt(p: Vector2) -> Vector2:
	return (p - _offset()) / maxf(_scale(), 0.0001)


func region_at(local_pos: Vector2) -> String:
	var mp: Vector2 = to_map_pt(local_pos)
	for rid: String in polys.keys():
		if Geometry2D.is_point_in_polygon(mp, polys[rid]):
			return rid
	return ""


func label_pos(rid: String) -> Vector2:
	var lp: Array = geo.get("labels", {}).get(rid, [0, 0])
	return to_local_pt(Vector2(float(lp[0]), float(lp[1])))


# ── 输入 ────────────────────────────────────────────────────────────────
func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var rid: String = region_at((ev as InputEventMouseMotion).position)
		if rid != hovered:
			hovered = rid
			queue_redraw()
		region_hovered.emit(rid, (ev as InputEventMouseMotion).position)
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
			and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var rid2: String = region_at((ev as InputEventMouseButton).position)
		if rid2 != "":
			selected = rid2
			queue_redraw()
			region_selected.emit(rid2)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hovered != "":
		hovered = ""
		queue_redraw()
		region_hovered.emit("", Vector2.ZERO)
	elif what == NOTIFICATION_RESIZED:
		queue_redraw()


# ── 绘制 ────────────────────────────────────────────────────────────────
func _layer_color(v: int) -> Color:
	var good: bool = GOOD_HIGH.has(layer)
	var t: float = clampf(float(v) / 1_000_000.0, 0.0, 1.0)
	if not good:
		t = 1.0 - t
	var bad_c: Color = JwTheme.c("ochre.hot")
	var mid_c: Color = JwTheme.c("ochre.core")
	var good_c: Color = JwTheme.c("teal.core")
	var c: Color = bad_c.lerp(mid_c, t * 2.0) if t < 0.5 else mid_c.lerp(good_c, (t - 0.5) * 2.0)
	c.a = 0.42
	return c


func _local_poly(rid: String) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in polys[rid]:
		out.append(to_local_pt(p))
	return out


func _draw() -> void:
	if base_tex != null:
		draw_texture_rect(base_tex, Rect2(_offset(), map_size * _scale()), false)
	var sc: float = _scale()
	# 图层着色
	if layer != "terrain":
		for rid: String in polys.keys():
			var lv: Dictionary = layer_vals.get(rid, {})
			if lv.is_empty():
				continue
			var lp: PackedVector2Array = _local_poly(rid)
			if Geometry2D.triangulate_polygon(lp).size() >= 3:
				draw_colored_polygon(lp, _layer_color(int(lv.get("v", 0))))
	# 悬停：提亮
	if hovered != "" and polys.has(hovered):
		var hp: PackedVector2Array = _local_poly(hovered)
		if Geometry2D.triangulate_polygon(hp).size() >= 3:
			var hc: Color = JwTheme.c("text.primary")
			hc.a = 0.10
			draw_colored_polygon(hp, hc)
	# 贸易航线
	_draw_routes(sc)
	# 边界：暗底细线 + 浅色虚线；选中的地区描粗
	for rid2: String in polys.keys():
		var ring: PackedVector2Array = _local_poly(rid2)
		ring.append(ring[0])
		draw_polyline(ring, Color(0, 0, 0, 0.55), 4.5, true)
		var bc: Color = JwTheme.c("warm.text")
		bc.a = 0.95
		draw_polyline(ring, bc, 1.8, true)
	if selected != "" and polys.has(selected):
		var sring: PackedVector2Array = _local_poly(selected)
		sring.append(sring[0])
		var gl: Color = JwTheme.c("focus.ring")
		gl.a = 0.35
		draw_polyline(sring, gl, 7.0, true)
		draw_polyline(sring, JwTheme.c("focus.ring"), 2.5, true)
	# 城池、港口、关隘
	for cty: Dictionary in geo.get("cities", []):
		var p: Vector2 = to_local_pt(Vector2(float(cty["pos"][0]), float(cty["pos"][1])))
		if bool(cty.get("capital", false)):
			_draw_capital(p, 9.0)
		else:
			draw_circle(p, 6.0, Color(0, 0, 0, 0.55))
			draw_circle(p, 4.5, JwTheme.c("warm.text"))
			draw_circle(p, 2.0, JwTheme.c("bg.abyss"))
	for pt: Dictionary in geo.get("ports", []):
		_draw_anchor(to_local_pt(Vector2(float(pt["pos"][0]), float(pt["pos"][1]))), 8.0)
	for ps: Dictionary in geo.get("passes", []):
		_draw_pass(to_local_pt(Vector2(float(ps["pos"][0]), float(ps["pos"][1]))), 7.0)
	# 地名与图层数字
	var font: Font = JwTheme.font("title_page")
	var fs: int = int(clampf(26.0 * sc * 1.6, 16.0, 30.0))
	var font2: Font = JwTheme.font("body_bold")
	var fs2: int = int(clampf(15.0 * sc * 1.6, 12.0, 17.0))
	for rid3: String in polys.keys():
		var name_s: String = String(names.get(rid3, rid3))
		var pos: Vector2 = label_pos(rid3)
		var tw: float = font.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at: Vector2 = pos - Vector2(tw * 0.5, 0)
		draw_string_outline(font, at, name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.03, 0.07, 0.10, 0.9))
		draw_string(font, at, name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, JwTheme.c("text.primary"))
		var sub: String = String(labels_sub.get(rid3, ""))
		if sub != "":
			var tw2: float = font2.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
			var at2: Vector2 = pos + Vector2(-tw2 * 0.5, fs2 + 6)
			draw_string_outline(font2, at2, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 5, Color(0.03, 0.07, 0.10, 0.9))
			draw_string(font2, at2, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, JwTheme.c("focus.ring"))
		_draw_markers(rid3, pos + Vector2(0, fs2 + 16), sc)


## 地区名下：主要产业的小图（圆形底）；有事时在地名左上角画警示记号。
func _draw_markers(rid: String, at: Vector2, sc: float) -> void:
	var mk: Dictionary = markers.get(rid, {})
	if mk.is_empty():
		return
	var icons: Array = mk.get("icons", [])
	var d: float = clampf(34.0 * sc * 1.6, 22.0, 40.0)
	var gap: float = 6.0
	var total: float = icons.size() * d + maxi(0, icons.size() - 1) * gap
	var x: float = at.x - total * 0.5
	for path: Variant in icons:
		var tex: Texture2D = _tex(String(path))
		var c: Vector2 = Vector2(x + d * 0.5, at.y + d * 0.5)
		draw_circle(c, d * 0.5 + 2.0, Color(0.03, 0.07, 0.10, 0.85))
		if tex != null:
			draw_texture_rect(tex, Rect2(Vector2(x, at.y), Vector2(d, d)), false)
		draw_arc(c, d * 0.5 + 1.0, 0.0, TAU, 24, JwTheme.c("warm.text"), 1.2, true)
		x += d + gap
	var alert: String = String(mk.get("alert", ""))
	if alert != "":
		var p: Vector2 = label_pos(rid) + Vector2(-40.0 * clampf(sc * 1.6, 0.6, 1.2), -34.0)
		var col: Color = JwTheme.c("ochre.hot") if alert == "hunger" or alert == "unrest" else JwTheme.c("ochre.core")
		var tri: PackedVector2Array = PackedVector2Array([p + Vector2(0, -12), p + Vector2(11, 8), p + Vector2(-11, 8)])
		draw_colored_polygon(tri, Color(0, 0, 0, 0.6))
		var tri2: PackedVector2Array = PackedVector2Array([p + Vector2(0, -10), p + Vector2(9, 6.5), p + Vector2(-9, 6.5)])
		draw_colored_polygon(tri2, col)
		draw_line(p + Vector2(0, -5), p + Vector2(0, 1.5), JwTheme.c("bg.abyss"), 2.0, true)
		draw_circle(p + Vector2(0, 4), 1.2, JwTheme.c("bg.abyss"))


func _tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_tex_cache[path] = t
	return t


func _draw_capital(p: Vector2, r: float) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 10:
		var a: float = -PI / 2 + TAU * float(i) / 10.0
		var rr: float = r if i % 2 == 0 else r * 0.45
		pts.append(p + Vector2(cos(a), sin(a)) * rr)
	var shadow: PackedVector2Array = PackedVector2Array()
	for q: Vector2 in pts:
		shadow.append(q + Vector2(1.5, 1.5))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.55))
	draw_colored_polygon(pts, JwTheme.c("ochre.core"))
	var ring: PackedVector2Array = pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, JwTheme.c("bg.abyss"), 1.2, true)


func _draw_anchor(p: Vector2, r: float) -> void:
	var c: Color = JwTheme.c("text.primary")
	var sh: Color = Color(0, 0, 0, 0.6)
	for pass_i: int in 2:
		var col: Color = sh if pass_i == 0 else c
		var o: Vector2 = Vector2(1.2, 1.2) if pass_i == 0 else Vector2.ZERO
		draw_arc(p + o + Vector2(0, -r * 0.75), r * 0.25, 0.0, TAU, 12, col, 1.6, true)
		draw_line(p + o + Vector2(0, -r * 0.5), p + o + Vector2(0, r * 0.8), col, 1.8, true)
		draw_line(p + o + Vector2(-r * 0.45, -r * 0.2), p + o + Vector2(r * 0.45, -r * 0.2), col, 1.6, true)
		draw_arc(p + o + Vector2(0, r * 0.15), r * 0.65, 0.35, PI - 0.35, 12, col, 1.8, true)


func _draw_pass(p: Vector2, r: float) -> void:
	var tri: PackedVector2Array = PackedVector2Array([p + Vector2(-r, r * 0.7), p + Vector2(0, -r * 0.8), p + Vector2(r, r * 0.7)])
	draw_colored_polygon(tri, Color(0, 0, 0, 0.5))
	var ring: PackedVector2Array = tri.duplicate()
	ring.append(tri[0])
	draw_polyline(ring, JwTheme.c("warm.text"), 1.6, true)


func _draw_routes(sc: float) -> void:
	var starts: Dictionary = geo.get("route_start", {})
	var anchors: Dictionary = geo.get("partners", {})
	var font: Font = JwTheme.font("caption")
	var fs: int = 13
	for rt: Dictionary in routes:
		var pid: String = String(rt["partner"])
		if not anchors.has(pid):
			continue
		var sea: bool = String(rt.get("route", "sea")) == "sea"
		var s0: Array = starts.get("sea" if sea else "land", [0, 0])
		var a: Vector2 = to_local_pt(Vector2(float(s0[0]), float(s0[1])))
		var ap: Array = anchors[pid]
		var b: Vector2 = to_local_pt(Vector2(float(ap[0]), float(ap[1])))
		var vol: int = int(rt.get("exports", 0)) + int(rt.get("imports", 0))
		var w: float = clampf(1.0 + log(1.0 + float(vol) / 1e8) * 0.9, 1.0, 5.0)
		var mid: Vector2 = (a + b) * 0.5 + Vector2(60.0 * sc * 1.6 if sea else 0.0, 0)
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in 25:
			var t2: float = float(i) / 24.0
			pts.append(a.lerp(mid, t2).lerp(mid.lerp(b, t2), t2))
		var col: Color = JwTheme.c("focus.ring") if sea else JwTheme.c("ochre.core")
		col.a = 0.85
		# 流动的虚线
		var dash: float = 10.0
		var phase: float = fmod(_t * 18.0, dash * 2.0)
		var acc: float = -phase
		for i2: int in pts.size() - 1:
			var p0: Vector2 = pts[i2]
			var p1: Vector2 = pts[i2 + 1]
			var seg: float = p0.distance_to(p1)
			var d0: float = 0.0
			while d0 < seg:
				var on: bool = int(floor((acc + d0) / dash)) % 2 == 0
				var d1: float = minf(seg, d0 + dash - fposmod(acc + d0, dash))
				if on:
					draw_line(p0.lerp(p1, d0 / seg), p0.lerp(p1, d1 / seg), col, w, true)
				d0 = d1 + 0.001
			acc += seg
		# 伙伴名
		var nm: String = String(rt.get("name", pid))
		var tw: float = font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at: Vector2 = b + Vector2(-tw * 0.5, -10)
		at.x = clampf(at.x, 4.0, size.x - tw - 4.0)
		draw_string_outline(font, at, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.03, 0.07, 0.10, 0.9))
		draw_string(font, at, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, JwTheme.c("text.primary"))
		draw_circle(b, 4.0, col)
