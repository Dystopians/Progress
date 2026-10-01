## 科技树（仿文明 6）：四个时代从左到右排开，同一时代里按前后关系分列，前置科技之间连线；
## 每项一个节点：圆形图标、名称、进度、解锁的小图标（建筑、新做法、政令）。
## 点节点选中（页面下方出详情）；按住空白处拖动、或滚动滚轮，左右移动。
class_name JcTechTree
extends Control

signal picked(id: String)

const NODE_W: float = 276.0
const NODE_H: float = 112.0
const COL_W: float = 332.0
const ROW_H: float = 130.0
const HEAD_H: float = 56.0
const PAD: float = 22.0
## 一列最多几项（多出来的往右挪一列，免得树太高）
const MAX_ROWS: int = 6
const ICON: float = 64.0
const UNLOCK_ICON: float = 24.0
const UNLOCK_MAX: int = 6

var techs: Array = []
var selected: String = ""
var cur_era: int = 1
var _pos: Dictionary = {}
var _era_x: Dictionary = {}
var _idx: Dictionary = {}
var _drag: bool = false
var _drag_from: Vector2 = Vector2.ZERO
var _scroll_from: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_data(list: Array, sel: String, era_now: int) -> void:
	techs = list
	selected = sel
	cur_era = era_now
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_layout()
	for tv: Dictionary in techs:
		add_child(_node(tv))
	queue_redraw()


## 某时代最左边一列的横坐标（页面用它把视野挪到本国所在的时代）。
func era_left(era: int) -> float:
	var x: Vector2 = _era_x.get(era, Vector2.ZERO)
	return x.x


# ── 布局 ────────────────────────────────────────────────────────────────
func _layout() -> void:
	_pos.clear()
	_era_x.clear()
	_idx.clear()
	for i: int in techs.size():
		_idx[String(techs[i]["id"])] = i
	var col: Dictionary = {}
	var start: int = 0
	for era: int in range(1, 5):
		var ids: Array = []
		for tv: Dictionary in techs:
			if int(tv["era"]) == era:
				ids.append(String(tv["id"]))
		if ids.is_empty():
			continue
		for id: String in ids:
			col[id] = start
		_push_right(ids, col, era)
		# 一列最多 MAX_ROWS 项：多出来的（排在后面的）挪到下一列，依赖它们的再往右推
		var c: int = start
		for guard: int in 64:
			var in_col: Array = []
			var maxc: int = start
			for id2: String in ids:
				maxc = maxi(maxc, int(col[id2]))
				if int(col[id2]) == c:
					in_col.append(id2)
			if c > maxc:
				break
			if in_col.size() > MAX_ROWS:
				in_col.sort_custom(func(a: String, b: String) -> bool:
					return _same_era_prereqs(a, era) > _same_era_prereqs(b, era) or \
							(_same_era_prereqs(a, era) == _same_era_prereqs(b, era) and int(_idx[a]) < int(_idx[b])))
				for id3: String in in_col.slice(MAX_ROWS):
					col[id3] = c + 1
				_push_right(ids, col, era)
			c += 1
		var end: int = start
		for id4: String in ids:
			end = maxi(end, int(col[id4]))
		_era_x[era] = Vector2(PAD + start * COL_W - 16.0, PAD + end * COL_W + NODE_W + 16.0)
		start = end + 1
	# 每列里排行：按前置所在行的平均值排（连线少交叉），没有前置的按原顺序排在后面
	var rows: Dictionary = {}
	var by_col: Dictionary = {}
	for id5: Variant in col.keys():
		var cc: int = int(col[id5])
		if not by_col.has(cc):
			by_col[cc] = []
		(by_col[cc] as Array).append(String(id5))
	var keys: Array = by_col.keys()
	keys.sort()
	var max_row: int = 0
	for cc2: Variant in keys:
		var arr: Array = by_col[cc2]
		var score: Dictionary = {}
		for id6: String in arr:
			var s: float = 0.0
			var n: int = 0
			for p: Variant in techs[int(_idx[id6])]["prereq"]:
				if rows.has(String(p)):
					s += float(rows[String(p)])
					n += 1
			score[id6] = (s / float(n)) if n > 0 else 100.0 + float(_idx[id6])
		arr.sort_custom(func(a: String, b: String) -> bool:
			return float(score[a]) < float(score[b]) or (float(score[a]) == float(score[b]) and int(_idx[a]) < int(_idx[b])))
		for r: int in arr.size():
			rows[arr[r]] = r
			max_row = maxi(max_row, r)
	for id7: Variant in col.keys():
		_pos[String(id7)] = Vector2(PAD + int(col[id7]) * COL_W, HEAD_H + PAD + int(rows[id7]) * ROW_H)
	custom_minimum_size = Vector2(PAD * 2.0 + maxi(0, start - 1) * COL_W + NODE_W,
			HEAD_H + PAD * 2.0 + (max_row + 1) * ROW_H - (ROW_H - NODE_H))


## 同一时代里，一项的列不能在它的前置左边或同列。
func _push_right(ids: Array, col: Dictionary, era: int) -> void:
	for guard: int in 64:
		var changed: bool = false
		for id: String in ids:
			for p: Variant in techs[int(_idx[id])]["prereq"]:
				var ps: String = String(p)
				if col.has(ps) and int(techs[int(_idx[ps])]["era"]) == era and int(col[id]) < int(col[ps]) + 1:
					col[id] = int(col[ps]) + 1
					changed = true
		if not changed:
			return


func _same_era_prereqs(id: String, era: int) -> int:
	var n: int = 0
	for p: Variant in techs[int(_idx[id])]["prereq"]:
		if _idx.has(String(p)) and int(techs[int(_idx[String(p)])]["era"]) == era:
			n += 1
	return n


func _done(id: String) -> bool:
	return _idx.has(id) and bool(techs[int(_idx[id])]["done"])


# ── 画：时代底色与标题、连线 ─────────────────────────────────────────────
func _draw() -> void:
	var font: Font = JwTheme.font("title_sub")
	var fs: int = JwTheme.size("title_sub")
	var small: Font = JwTheme.font("caption")
	var sfs: int = JwTheme.size("caption")
	for era: Variant in _era_x.keys():
		var e: int = int(era)
		var x: Vector2 = _era_x[e]
		var tint: Color = JwTheme.c("bg.panel") if e % 2 == 1 else JwTheme.c("bg.base")
		if e == cur_era:
			tint = tint.lerp(JwTheme.c("teal.core"), 0.07)
		draw_rect(Rect2(x.x, 0.0, x.y - x.x, size.y), tint)
		var art: String = "res://assets/techs/bg/tree_era%d.png" % e
		if ResourceLoader.exists(art):
			var tex: Texture2D = load(art) as Texture2D
			draw_texture_rect(tex, Rect2(x.x, 0.0, x.y - x.x, size.y), false, Color(1, 1, 1, 0.18))
		var state: String = "jc.tech.era_now" if e == cur_era else ("jc.tech.era_past" if e < cur_era else
				("jc.tech.era_next" if e == cur_era + 1 else "jc.tech.era_far"))
		draw_string(font, Vector2(x.x + 16.0, 30.0), JcFmt.era_name(e), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				JwTheme.c("text.primary") if e <= cur_era + 1 else JwTheme.c("text.muted"))
		draw_string(small, Vector2(x.x + 16.0, 30.0 + sfs + 6.0), JwText.t(state), HORIZONTAL_ALIGNMENT_LEFT, -1, sfs,
				JwTheme.c("teal.core") if e == cur_era else JwTheme.c("text.muted"))
	for tv: Dictionary in techs:
		var id: String = String(tv["id"])
		if not _pos.has(id):
			continue
		var to: Vector2 = (_pos[id] as Vector2) + Vector2(0.0, NODE_H * 0.5)
		for p: Variant in tv["prereq"]:
			var ps: String = String(p)
			if not _pos.has(ps):
				continue
			var from: Vector2 = (_pos[ps] as Vector2) + Vector2(NODE_W, NODE_H * 0.5)
			if to.x <= from.x:
				continue
			var done: bool = _done(ps)
			var lit: bool = id == selected or ps == selected
			var col: Color = JwTheme.c("teal.core") if done else JwTheme.c("line.strong")
			if lit:
				col = JwTheme.c("ochre.core")
			var mid: float = from.x + minf(28.0, (to.x - from.x) * 0.5)
			var pts: PackedVector2Array = PackedVector2Array([from, Vector2(mid, from.y), Vector2(mid, to.y), to + Vector2(-6.0, 0.0)])
			draw_polyline(pts, col, 3.0 if lit else (2.5 if done else 2.0), true)
			draw_colored_polygon(PackedVector2Array([to, to + Vector2(-9.0, -5.5), to + Vector2(-9.0, 5.5)]), col)


# ── 节点 ────────────────────────────────────────────────────────────────
func _node(tv: Dictionary) -> Control:
	var id: String = String(tv["id"])
	var done: bool = bool(tv["done"])
	var focus: bool = bool(tv["focus"])
	var avail: bool = bool(tv["available"])
	var sel: bool = id == selected
	var rule: String = JcUi.GOOD if done else (JcUi.WARN if focus else ("text.secondary" if avail else "line.hair"))
	var bw: int = 3 if (sel or focus) else 1
	var box: StyleBoxFlat = JwTheme.box4("bg.raised" if (avail or focus or sel) else "bg.panel", "ochre.core" if sel else rule,
			bw, 10, 8, 10, 8)
	box.set_corner_radius_all(10)
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", box)
	p.position = _pos[id]
	p.custom_minimum_size = Vector2(NODE_W, NODE_H)
	p.size = Vector2(NODE_W, NODE_H)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.tooltip_text = String(tv["name"]) + "\n" + String(tv["desc"])
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			p.accept_event()
			picked.emit(id))
	if not done and not avail and not focus:
		p.modulate = Color(1, 1, 1, 0.6)
	var h: HBoxContainer = JwUi.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var ic: Control = JcUi.badge(JcUi.TECH_ART % id, ICON, String(tv["name"]),
			JcUi.GOOD if done else (JcUi.WARN if focus else "line.strong"))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v: VBoxContainer = JwUi.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var top: HBoxContainer = JwUi.hbox(6)
	top.add_child(JwUi.label(String(tv["name"]), "body_bold", "text.primary" if (avail or done or focus) else "text.muted"))
	if bool(tv["era_key"]) and not done:
		top.add_child(JwUi.spacer())
		top.add_child(JcUi.chip(JwText.t("jc.tech.key_short"), JcUi.WARN))
	v.add_child(top)
	if done:
		v.add_child(JwUi.label(JwText.t("jc.tech.state.done"), "caption", JcUi.GOOD))
	else:
		var cost: int = maxi(1, int(tv["cost"]))
		v.add_child(JcUi.meter(JCMath.ratio_ppm(int(tv["progress"]), cost), JcUi.WARN if focus else JcUi.GOOD,
				NODE_W - ICON - 44.0, 6.0))
		var eta: String = JcFmt.quarters(int(tv["eta_q"]))
		var status: String = ""
		if focus:
			status = JwText.render("jc.tech.state.focus", {"eta": eta})
		elif avail:
			status = JwText.render("jc.tech.state.avail", {"eta": eta})
		else:
			var names: PackedStringArray = PackedStringArray()
			for pp: Variant in tv["prereq"]:
				if not _done(String(pp)) and _idx.has(String(pp)):
					names.append(String(techs[int(_idx[String(pp)])]["name"]))
			status = JwText.render("jc.tech.state.locked", {"list": JwText.t("jc.name_sep").join(names)})
		v.add_child(JwUi.label(status, "caption", JcUi.WARN if focus else "text.muted"))
	var u: HBoxContainer = JwUi.hbox(4)
	u.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ul: Array = tv.get("unlocks", [])
	for k: int in mini(ul.size(), UNLOCK_MAX):
		var un: Dictionary = ul[k]
		var path: String = String(un["art"])
		if String(un["kind"]) == "decree":
			path = JcUi.decree_art(String(un["id"]), int(un.get("level", -1)))
		var b: Control = JcUi.badge(path, UNLOCK_ICON, String(un["name"]), "line.hair")
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.tooltip_text = JcPageTech.unlock_text(un)
		u.add_child(b)
	if ul.size() > UNLOCK_MAX:
		u.add_child(JwUi.label("+%d" % (ul.size() - UNLOCK_MAX), "caption", "text.muted"))
	v.add_child(u)
	return p


# ── 拖动与滚轮 ───────────────────────────────────────────────────────────
func _gui_input(ev: InputEvent) -> void:
	var sc: ScrollContainer = get_parent() as ScrollContainer
	if sc == null:
		return
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
			_drag_from = mb.global_position
			_scroll_from = Vector2(sc.scroll_horizontal, sc.scroll_vertical)
			accept_event()
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			# 树是横着长的：滚轮左右移动；按住 Shift 才上下
			var step: int = 160 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -160
			if mb.shift_pressed:
				sc.scroll_vertical += step
			else:
				sc.scroll_horizontal += step
			accept_event()
	elif ev is InputEventMouseMotion and _drag:
		var d: Vector2 = (ev as InputEventMouseMotion).global_position - _drag_from
		sc.scroll_horizontal = int(_scroll_from.x - d.x)
		sc.scroll_vertical = int(_scroll_from.y - d.y)
		accept_event()
