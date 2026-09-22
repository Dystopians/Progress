## 地区图（docs/20 §7.2.5、D-13、IM-9；T1）：抽象多边形 + 剧本邻接边（带物流成本系数）+ 图层填色
## + 右侧固定标签栏与 1 lu 引出线。标签不画在多边形里（小区放不下，D-13）；选中态用描边，不用颜色（颜色留给图层）。
## 拓扑（哪几区相邻、成本多少）只从剧本 regions.json 读；轮廓是界面登记的抽象几何，不对应真实地理（B-15）。
## 命中测试自己做：Geometry2D.is_point_in_polygon；填充前先 Geometry2D.triangulate_polygon（凹多边形，IM-9）。
class_name JwRegionMap
extends Control

signal region_selected(r: int)
signal region_opened(r: int)

const BAR_W: float = 250.0

## 每区：{"poly": PackedVector2Array（坐标空间）, "token": 图层色, "label": 标签文字}。
var regions: Array[Dictionary] = []
## [[a, b, 物流成本 ppm], …]
var edges: Array = []
var coord: Vector2 = Vector2(1000, 700)
var selected: int = -1
var label_bar: VBoxContainer = null
var label_nodes: Array[Control] = []


static func make(p_regions: Array[Dictionary], p_edges: Array, p_coord: Vector2, p_selected: int = -1) -> JwRegionMap:
	var m: JwRegionMap = JwRegionMap.new()
	m.regions = p_regions
	m.edges = p_edges
	m.coord = p_coord
	m.selected = p_selected
	m.custom_minimum_size = Vector2(464, 314)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	JwUi.tag(m, "RegionMap")
	m.label_bar = JwUi.vbox(10)
	m.label_bar.name = "MapLabelBar"
	JwUi.tag(m.label_bar, "MapLabelBar")
	m.add_child(m.label_bar)
	# 标签按锚点的纵坐标排序，减少引出线交叉。
	var order: Array[int] = []
	for r: int in p_regions.size():
		order.append(r)
	order.sort_custom(func(a: int, b: int) -> bool: return m.anchor_of(a).y < m.anchor_of(b).y)
	m.label_nodes.resize(p_regions.size())
	for r2: int in order:
		var pnl: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.raised", String(p_regions[r2]["token"]), 4, 8))
		var l: Label = JwUi.label(String(p_regions[r2]["label"]), "body_bold" if r2 == p_selected else "body", "text.primary")
		pnl.add_child(l)
		JwUi.tag(pnl, "MapLabel%d" % r2)
		m.label_bar.add_child(pnl)
		m.label_nodes[r2] = pnl
	return m


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and label_bar != null:
		label_bar.position = Vector2(size.x - BAR_W, 12)
		label_bar.size = Vector2(BAR_W - 10, maxf(size.y - 24, 0))
		queue_redraw()


func _map_rect() -> Rect2:
	return Rect2(Vector2(8, 8), Vector2(maxf(size.x - BAR_W - 24, 10), maxf(size.y - 16, 10)))


## 坐标空间 → 控件本地坐标（等比缩放、居中）。
func to_local_pt(p: Vector2) -> Vector2:
	var mr: Rect2 = _map_rect()
	var k: float = minf(mr.size.x / coord.x, mr.size.y / coord.y)
	var off: Vector2 = mr.position + (mr.size - coord * k) * 0.5
	return off + p * k


func to_coord_pt(p: Vector2) -> Vector2:
	var mr: Rect2 = _map_rect()
	var k: float = minf(mr.size.x / coord.x, mr.size.y / coord.y)
	var off: Vector2 = mr.position + (mr.size - coord * k) * 0.5
	return (p - off) / maxf(k, 0.0001)


## 锚点（坐标空间）：三角剖分里面积最大的三角形的重心——凹多边形上也保证落在形内（引出线端点，AC-18）。
func anchor_of(r: int) -> Vector2:
	var poly: PackedVector2Array = regions[r]["poly"]
	var tri: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	if tri.size() < 3:
		var c: Vector2 = Vector2.ZERO
		for p: Vector2 in poly:
			c += p
		return c / float(maxi(poly.size(), 1))
	var best: Vector2 = Vector2.ZERO
	var best_a: float = -1.0
	var i: int = 0
	while i + 2 < tri.size():
		var a: Vector2 = poly[tri[i]]
		var b: Vector2 = poly[tri[i + 1]]
		var c2: Vector2 = poly[tri[i + 2]]
		var area: float = absf((b - a).cross(c2 - a)) * 0.5
		if area > best_a:
			best_a = area
			best = (a + b + c2) / 3.0
		i += 3
	return best


## 两区公共边界上的一点（坐标空间）：按 a 的顶点顺序取两区共有的顶点，取中间那段的中点；
## 没有共有顶点（轮廓不贴合）时退回两锚点的中点。
func border_point(a: int, b: int) -> Vector2:
	var pa: PackedVector2Array = regions[a]["poly"]
	var pb: PackedVector2Array = regions[b]["poly"]
	var shared: PackedVector2Array = PackedVector2Array()
	for v: Vector2 in pa:
		if pb.has(v):
			shared.append(v)
	if shared.size() == 0:
		return (anchor_of(a) + anchor_of(b)) * 0.5
	if shared.size() == 1:
		return shared[0]
	@warning_ignore("integer_division")
	var k: int = (shared.size() - 1) / 2
	return (shared[k] + shared[k + 1]) * 0.5


func region_at(local_pos: Vector2) -> int:
	var cp: Vector2 = to_coord_pt(local_pos)
	for r: int in regions.size():
		if Geometry2D.is_point_in_polygon(cp, regions[r]["poly"]):
			return r
	return -1


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
			and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var r: int = region_at((ev as InputEventMouseButton).position)
		if r < 0:
			return
		if (ev as InputEventMouseButton).double_click:
			region_opened.emit(r)
		else:
			selected = r
			region_selected.emit(r)
			queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), JwTheme.c("bg.abyss"), true)
	var font: Font = JwTheme.font("caption")
	var fs: int = JwTheme.size("caption")
	# 多边形：图层填色 + 细描边；选中区 3 lu 描边（不改颜色）。
	for r: int in regions.size():
		var poly: PackedVector2Array = regions[r]["poly"]
		var pts: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in poly:
			pts.append(to_local_pt(p))
		if Geometry2D.triangulate_polygon(pts).size() >= 3:
			draw_colored_polygon(pts, JwTheme.c(String(regions[r]["token"])))
		var ring: PackedVector2Array = pts.duplicate()
		if ring.size() > 0:
			ring.append(ring[0])
		draw_polyline(ring, JwTheme.c("bg.abyss"), 2.0, true)
	if selected >= 0 and selected < regions.size():
		var sel: PackedVector2Array = PackedVector2Array()
		for p2: Vector2 in (regions[selected]["poly"] as PackedVector2Array):
			sel.append(to_local_pt(p2))
		if sel.size() > 0:
			sel.append(sel[0])
		draw_polyline(sel, JwTheme.c("text.primary"), 3.0, true)
	# 邻接边：锚点 → 两区共享边界上的点 → 锚点（折线穿过真实的公共边界，不会看起来「经第三区」）；
	# 成本系数标在边界点上（剧本逐条声明的边都画出来，AC-20）。
	for e: Variant in edges:
		var ed: Array = e
		var pa: Vector2 = to_local_pt(anchor_of(int(ed[0])))
		var pb: Vector2 = to_local_pt(anchor_of(int(ed[1])))
		var mid: Vector2 = to_local_pt(border_point(int(ed[0]), int(ed[1])))
		draw_dashed_line(pa, mid, JwTheme.c("text.secondary"), 1.5, 6.0)
		draw_dashed_line(mid, pb, JwTheme.c("text.secondary"), 1.5, 6.0)
		var txt: String = JwFormat.pct(int(ed[2]))
		var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_rect(Rect2(mid - Vector2(tw * 0.5 + 4, fs * 0.8), Vector2(tw + 8, fs * 1.4)), JwTheme.c("bg.abyss"), true)
		draw_string(font, mid + Vector2(-tw * 0.5, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				JwTheme.c("text.secondary"))
	# 锚点与引出线（标签栏在右侧；线从标签左缘中点连到多边形内的锚点）。
	for r3: int in regions.size():
		var ap: Vector2 = to_local_pt(anchor_of(r3))
		draw_circle(ap, 4.0, JwTheme.c("text.primary"))
		if r3 < label_nodes.size() and label_nodes[r3] != null:
			var ln: Control = label_nodes[r3]
			var lp: Vector2 = label_bar.position + ln.position + Vector2(0, ln.size.y * 0.5)
			draw_line(ap, lp, JwTheme.c("text.secondary"), 1.0, true)
