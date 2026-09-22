## 项目自带的单色矢量图标（docs/20 §12.4：禁止系统 emoji）。
##
## 种类：
##   actual 实心方 / derived 半填菱 / projected 空心菱（三类信息，实心度递减）
##   note 圆内一竖点 / warn 三角叹号 / block 八角横杠（三级风险，形状两两不同）
##   rule 规则角标（书页）/ settling 结算中（缺口圆）/ loading 重算中 / ok 对勾 / region 地区点
class_name JwIcon
extends Control

var kind: String = "note"
var color: Color = Color.WHITE
var px: int = 14


static func make(k: String, col: Color, size_px: int = 14) -> JwIcon:
	var ic: JwIcon = JwIcon.new()
	ic.kind = k
	ic.color = col
	ic.px = size_px
	ic.custom_minimum_size = Vector2(size_px, size_px)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return ic


func set_kind(k: String, col: Color) -> void:
	kind = k
	color = col
	queue_redraw()


func _draw() -> void:
	var s: float = float(px)
	var off: Vector2 = Vector2(0.0, (size.y - s) * 0.5)
	var cx: float = s * 0.5
	var cy: float = s * 0.5
	match kind:
		"actual":
			draw_rect(Rect2(off + Vector2(1, 1), Vector2(s - 2, s - 2)), color, true)
		"derived":
			var pts: PackedVector2Array = _diamond(off, s)
			draw_polyline(_closed(pts), color, 1.5, true)
			var half: PackedVector2Array = PackedVector2Array([pts[0], pts[1], pts[2]])
			draw_colored_polygon(half, color)
		"projected":
			draw_polyline(_closed(_diamond(off, s)), color, 1.5, true)
		"note":
			draw_arc(off + Vector2(cx, cy), s * 0.45, 0.0, TAU, 24, color, 1.5, true)
			draw_line(off + Vector2(cx, cy - 1), off + Vector2(cx, cy + s * 0.28), color, 2.0)
			draw_circle(off + Vector2(cx, cy - s * 0.24), 1.3, color)
		"warn":
			var tri: PackedVector2Array = PackedVector2Array([
				off + Vector2(cx, 1), off + Vector2(s - 1, s - 1), off + Vector2(1, s - 1)])
			draw_polyline(_closed(tri), color, 1.5, true)
			draw_line(off + Vector2(cx, s * 0.36), off + Vector2(cx, s * 0.66), color, 2.0)
			draw_circle(off + Vector2(cx, s * 0.80), 1.2, color)
		"block":
			var oct: PackedVector2Array = PackedVector2Array()
			var r: float = s * 0.48
			for i: int in 8:
				var a: float = TAU * (float(i) + 0.5) / 8.0
				oct.append(off + Vector2(cx, cy) + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(oct, color)
			draw_line(off + Vector2(s * 0.24, cy), off + Vector2(s * 0.76, cy),
					JwTheme.c("bg.abyss"), 2.4)
		"rule":
			draw_rect(Rect2(off + Vector2(2, 1), Vector2(s - 4, s - 2)), color, false, 1.2)
			draw_line(off + Vector2(4.5, s * 0.35), off + Vector2(s - 4.5, s * 0.35), color, 1.0)
			draw_line(off + Vector2(4.5, s * 0.55), off + Vector2(s - 4.5, s * 0.55), color, 1.0)
			draw_line(off + Vector2(4.5, s * 0.75), off + Vector2(s - 6.5, s * 0.75), color, 1.0)
		"settling":
			draw_arc(off + Vector2(cx, cy), s * 0.42, 0.3, TAU - 0.9, 20, color, 2.0, true)
			draw_circle(off + Vector2(cx, cy), 1.6, color)
		"loading":
			draw_arc(off + Vector2(cx, cy), s * 0.42, 0.0, PI * 1.4, 18, color, 2.0, true)
		"ok":
			draw_polyline(PackedVector2Array([off + Vector2(2, cy), off + Vector2(cx - 1, s - 3),
					off + Vector2(s - 2, 3)]), color, 2.0, true)
		"region":
			draw_circle(off + Vector2(cx, cy), s * 0.3, color)
		_:
			draw_rect(Rect2(off, Vector2(s, s)), color, false, 1.0)


static func _diamond(off: Vector2, s: float) -> PackedVector2Array:
	return PackedVector2Array([
		off + Vector2(s * 0.5, 1), off + Vector2(s - 1, s * 0.5),
		off + Vector2(s * 0.5, s - 1), off + Vector2(1, s * 0.5)])


static func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var q: PackedVector2Array = p.duplicate()
	q.append(p[0])
	return q
