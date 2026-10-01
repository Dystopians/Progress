## 产业链图：五列——原料的原料、原料、这样货、拿它做原料的货、百姓的需要；格子按紧缺（橙红）、
## 积压（赭）、平稳（青绿）描边，格子之间画连线；点任一样货就跳过去看它的来龙去脉。
class_name JcChainGraph
extends Control

signal picked(gid: String)

const COLS: PackedStringArray = ["up2", "up1", "center", "down", "needs"]

var _row: HBoxContainer = null
var _cells: Dictionary = {}          # 商品或需要的 id → 格子（Control）
var _links: Array = []               # [[起点 id, 终点 id], ...]


func _ready() -> void:
	resized.connect(queue_redraw)


func set_data(d: Dictionary) -> void:
	for c: Node in get_children():
		c.queue_free()
	_cells = {}
	_links = []
	if d.is_empty():
		return
	# 高度按格子最多的那一列定（每格约 46 像素，外加列名）
	var rows: int = 1
	for key: String in ["up2", "up1", "down", "needs"]:
		rows = maxi(rows, (d[key] as Array).size())
	custom_minimum_size = Vector2(0, 34 + rows * 56)
	_row = JwUi.hbox(22)
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	var center: Dictionary = d["center"]
	var cid: String = String(center["id"])
	for col: String in COLS:
		var v: VBoxContainer = JwUi.vbox(6)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.sort_children.connect(queue_redraw)
		_row.add_child(v)
		var head: Label = JwUi.label(JwText.t("jc.chain.col." + col), "caption", "text.muted")
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(head)
		match col:
			"up2":
				for it: Dictionary in d["up2"]:
					v.add_child(_cell(it, false, ""))
			"up1":
				for it2: Dictionary in d["up1"]:
					v.add_child(_cell(it2, false, "", int(it2["fill"])))
					_links.append([String(it2["id"]), cid])
			"center":
				v.add_child(_cell(center, true, ""))
			"down":
				for it3: Dictionary in d["down"]:
					v.add_child(_cell(it3, false, String(it3.get("via", ""))))
					_links.append([cid, String(it3["id"])])
			"needs":
				for nd: Dictionary in d["needs"]:
					var nid: String = "need:" + String(nd["id"])
					var l: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.raised", "line.hair", 1, 8, 4, 8, 4))
					var nh: HBoxContainer = JwUi.hbox(6)
					nh.mouse_filter = Control.MOUSE_FILTER_IGNORE
					nh.add_child(JcUi.badge(JcUi.NEED_ICON % String(nd["id"]), 26.0, String(nd["name"]), "line.strong"))
					nh.add_child(JwUi.label(String(nd["name"]) + (JwText.t("jc.soc.ess_mark") if bool(nd["essential"]) else ""),
							"caption", "text.secondary"))
					l.add_child(nh)
					l.mouse_filter = Control.MOUSE_FILTER_IGNORE
					v.add_child(l)
					_cells[nid] = l
					_links.append([cid, nid])
		# 「拿它做原料」一列空着、右边又有百姓的需要时，连线正好横穿这一列，就不写「没有」了
		var crossed: bool = col == "down" and not (d["needs"] as Array).is_empty()
		if v.get_child_count() == 1 and not crossed:
			var none: Label = JwUi.label(JwText.t("jc.chain.none"), "caption", "text.muted")
			none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(none)
	for lk: Array in d["links2"]:
		_links.append([String(lk[0]), String(lk[1])])
	call_deferred("queue_redraw")


## fill ≥ 0：原料格底下画一条到货率的小条（满条 = 要多少到多少），数字在悬停提示里。
func _cell(it: Dictionary, big: bool, sub: String, fill: int = -1) -> Control:
	var gid: String = String(it["id"])
	var state: String = String(it["state"])
	var tok: String = JcUi.BAD if state == "short" else (JcUi.WARN if state == "glut" else "line.strong")
	var b: Button = Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 54 if big else (48 if sub != "" or fill >= 0 else 40))
	b.tooltip_text = JwText.t("jc.chain.tip." + state)
	if fill >= 0:
		b.tooltip_text += "\n" + JwText.render("jc.chain.fill", {"v": JcFmt.pct(fill, 0)})
	var p: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.raised" if big else "bg.panel", tok, 2 if big else 1,
			10, 4, 10, 4))
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(p)
	var hb: HBoxContainer = JwUi.hbox(6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(hb)
	var ic: Control = JcUi.badge(JcUi.res(String(it.get("art", ""))), 40.0 if big else 30.0, String(it["name"]), tok)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ic)
	var v: VBoxContainer = JwUi.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(v)
	var name_l: Label = JwUi.label(String(it["name"]), "body_bold" if big else "caption",
			JcUi.BAD if state == "short" else "text.primary")
	v.add_child(name_l)
	if sub != "":
		var s: Label = JwUi.label(sub, "caption", "text.muted")
		s.clip_text = true
		v.add_child(s)
	if fill >= 0:
		var m: JcMeter = JcUi.meter(fill, JcUi.tone(fill >= 900_000, fill >= 600_000), 48.0, 5.0)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(m)
	if not big:
		b.pressed.connect(func() -> void: picked.emit(gid))
	_cells[gid] = b
	return b


func _draw() -> void:
	var me: Rect2 = get_global_rect()
	for lk: Array in _links:
		var a: Control = _cells.get(String(lk[0]), null)
		var z: Control = _cells.get(String(lk[1]), null)
		if a == null or z == null or not is_instance_valid(a) or not is_instance_valid(z):
			continue
		var ra: Rect2 = a.get_global_rect()
		var rz: Rect2 = z.get_global_rect()
		var p0: Vector2 = Vector2(ra.end.x, ra.position.y + ra.size.y * 0.5) - me.position
		var p3: Vector2 = Vector2(rz.position.x, rz.position.y + rz.size.y * 0.5) - me.position
		var dx: float = maxf(20.0, (p3.x - p0.x) * 0.5)
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in 17:
			var t: float = float(i) / 16.0
			var q0: Vector2 = p0.lerp(p0 + Vector2(dx, 0), t)
			var q1: Vector2 = (p0 + Vector2(dx, 0)).lerp(p3 - Vector2(dx, 0), t)
			var q2: Vector2 = (p3 - Vector2(dx, 0)).lerp(p3, t)
			pts.append(q0.lerp(q1, t).lerp(q1.lerp(q2, t), t))
		var col: Color = JwTheme.c("line.strong")
		col.a = 0.9
		draw_polyline(pts, col, 1.5, true)

