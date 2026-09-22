## 一切独立展示的数字（docs/20 §4 形态 A，IM-1：单个自绘 Control）。
##
## 同屏呈现「值 + 单位 + 三类徽章」；口径五元组放在 meta 与相邻的口径角标行里。
## 交互（docs/20 §3.6）：点击数字本体 = 打开台账；悬停/聚焦时右上出规则角标，点击角标 = 规则卡；
## 键盘：Enter 打开台账，Alt+R 打开规则卡。info_class 是必填项：NONE 即缺陷（push_error + 红底占位）。
class_name JwNumberCell
extends Control

signal ledger_requested(ledger: String, row: int)
signal rule_requested(rule_key: String)

var value_text: String = ""
var unit_text: String = ""
var cls: int = JwInfo.Cls.NONE
var role: String = "num"
var paper: bool = false
var meta: Dictionary = {}
var value_color_token: String = ""
var _hover: bool = false
var _rule_rect: Rect2 = Rect2()

const GAP_BADGE: float = 8.0
const GAP_UNIT: float = 6.0
const RULE_W: float = 16.0


static func make(v_text: String, u_text: String, c: int, r: String = "num",
		m: Dictionary = {}, on_paper: bool = false) -> JwNumberCell:
	var n: JwNumberCell = JwNumberCell.new()
	n.value_text = v_text
	n.unit_text = u_text
	n.cls = c
	n.role = r
	n.meta = m
	n.paper = on_paper
	n.focus_mode = Control.FOCUS_ALL
	n.mouse_filter = Control.MOUSE_FILTER_STOP
	n.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	n.set_meta("info_class", c)
	n.set_meta("jw_role", r)
	if c == JwInfo.Cls.NONE:
		push_error("JwNumberCell: info_class is required")
	return n


func set_value(v_text: String, u_text: String, c: int, m: Dictionary = {}) -> void:
	value_text = v_text
	unit_text = u_text
	cls = c
	if not m.is_empty():
		meta = m
	set_meta("info_class", c)
	update_minimum_size()
	queue_redraw()


func _badge_text() -> String:
	return JwInfo.badge(cls)


func _get_minimum_size() -> Vector2:
	var fv: Font = JwTheme.font(role)
	var fs: int = JwTheme.size(role)
	var fb: Font = JwTheme.font("body_bold")
	var bs: int = JwTheme.size("body")
	var w: float = 12.0 + 3.0 + fb.get_string_size(_badge_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, bs).x
	w += GAP_BADGE + fv.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if unit_text != "":
		w += GAP_UNIT + JwTheme.font("body").get_string_size(unit_text, HORIZONTAL_ALIGNMENT_LEFT, -1, bs).x
	w += RULE_W + 2.0
	var h: float = maxf(fv.get_height(fs), 24.0) + 4.0
	return Vector2(ceilf(w), ceilf(maxf(h, 32.0 if role == "num" else h)))


func _draw() -> void:
	var fv: Font = JwTheme.font(role)
	var fs: int = JwTheme.size(role)
	var fb: Font = JwTheme.font("body_bold")
	var fu: Font = JwTheme.font("body")
	var bs: int = JwTheme.size("body")
	if cls == JwInfo.Cls.NONE:
		draw_rect(Rect2(Vector2.ZERO, size), JwTheme.c("debug.missing"), true)
	var base_y: float = (size.y + fv.get_ascent(fs) - fv.get_descent(fs)) * 0.5
	var x: float = 0.0
	if cls != JwInfo.Cls.NONE:
		var tok: String = JwInfo.color_token(cls, paper)
		var col: Color = JwTheme.c(tok)
		_draw_class_icon(Vector2(x, base_y - 11.0), col)
		x += 15.0
		var bt: String = _badge_text()
		draw_string(fb, Vector2(x, base_y), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, col)
		x += fb.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, bs).x + GAP_BADGE
	var vtok: String = value_color_token
	if vtok == "":
		vtok = "text.ink" if paper else "text.primary"
	draw_string(fv, Vector2(x, base_y), value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, JwTheme.c(vtok))
	x += fv.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if unit_text != "":
		x += GAP_UNIT
		draw_string(fu, Vector2(x, base_y), unit_text, HORIZONTAL_ALIGNMENT_LEFT, -1, bs,
				JwTheme.c("text.ink2" if paper else "text.secondary"))
		x += fu.get_string_size(unit_text, HORIZONTAL_ALIGNMENT_LEFT, -1, bs).x
	_rule_rect = Rect2(Vector2(x + 3.0, 0.0), Vector2(RULE_W, RULE_W))
	if _hover or has_focus():
		var rc: Color = JwTheme.c("teal.deep" if paper else "focus.ring")
		_draw_rule_chip(_rule_rect.position + Vector2(2, 2), rc)
	if has_focus():
		draw_rect(Rect2(Vector2(-2, -2), size + Vector2(4, 4)), JwTheme.c("focus.ring"), false, 2.0)


func _draw_class_icon(p: Vector2, col: Color) -> void:
	var s: float = 12.0
	match cls:
		JwInfo.Cls.ACTUAL:
			draw_rect(Rect2(p + Vector2(1, 1), Vector2(s - 2, s - 2)), col, true)
		JwInfo.Cls.DERIVED:
			var d: PackedVector2Array = PackedVector2Array([p + Vector2(s * 0.5, 0), p + Vector2(s, s * 0.5),
					p + Vector2(s * 0.5, s), p + Vector2(0, s * 0.5), p + Vector2(s * 0.5, 0)])
			draw_polyline(d, col, 1.5, true)
			draw_colored_polygon(PackedVector2Array([d[0], d[1], d[2]]), col)
		JwInfo.Cls.PROJECTED:
			var d2: PackedVector2Array = PackedVector2Array([p + Vector2(s * 0.5, 0), p + Vector2(s, s * 0.5),
					p + Vector2(s * 0.5, s), p + Vector2(0, s * 0.5), p + Vector2(s * 0.5, 0)])
			draw_polyline(d2, col, 1.5, true)


func _draw_rule_chip(p: Vector2, col: Color) -> void:
	var s: float = 12.0
	draw_rect(Rect2(p, Vector2(s - 2, s)), col, false, 1.2)
	draw_line(p + Vector2(2.5, s * 0.35), p + Vector2(s - 4.5, s * 0.35), col, 1.0)
	draw_line(p + Vector2(2.5, s * 0.6), p + Vector2(s - 4.5, s * 0.6), col, 1.0)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			queue_redraw()
		NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT:
			queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if _rule_rect.has_point(mb.position):
				rule_requested.emit(String(meta.get("rule_key", "")))
			else:
				ledger_requested.emit(String(meta.get("ledger", "")), int(meta.get("row", 0)))
	elif event is InputEventKey:
		var k: InputEventKey = event
		if not k.pressed:
			return
		if k.keycode == KEY_R and k.alt_pressed:
			accept_event()
			rule_requested.emit(String(meta.get("rule_key", "")))
		elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			accept_event()
			ledger_requested.emit(String(meta.get("ledger", "")), int(meta.get("row", 0)))


func _get_tooltip(_at_position: Vector2) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(JwInfo.cls_name(cls))
	for k: String in ["measure", "period", "price_base", "denominator", "index_base"]:
		if meta.has(k) and String(meta[k]) != "":
			parts.append(String(meta[k]))
	var s: String = " · ".join(parts)
	if meta.has("citation") and String(meta["citation"]) != "":
		s += "\n" + String(meta["citation"])
	if meta.has("rule_id") and String(meta["rule_id"]) != "":
		s += "\n" + String(meta["rule_id"])
	if meta.has("raw") and String(meta["raw"]) != "":
		s += "\n" + String(meta["raw"])
	return s
