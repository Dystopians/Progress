## 三类信息的左标尺（docs/20 §3.3 通道③）：3 lu 宽，实线 / 短划 6-3 / 点线 2-4。
## 用逐段 draw_line 画出不同笔形，灰度与色觉异常下仍可区分（不靠色相）。
class_name JwClassRule
extends Control

var cls: int = JwInfo.Cls.NONE
var paper: bool = false


static func make(c: int, on_paper: bool = false) -> JwClassRule:
	var r: JwClassRule = JwClassRule.new()
	r.cls = c
	r.paper = on_paper
	r.custom_minimum_size = Vector2(3, 16)
	r.size_flags_vertical = Control.SIZE_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _draw() -> void:
	if cls == JwInfo.Cls.NONE:
		return
	var col: Color = JwTheme.c(JwInfo.color_token(cls, paper))
	var x: float = 1.5
	var h: float = size.y
	match cls:
		JwInfo.Cls.ACTUAL:
			draw_line(Vector2(x, 0), Vector2(x, h), col, 3.0)
		JwInfo.Cls.DERIVED:
			var y: float = 0.0
			while y < h:
				draw_line(Vector2(x, y), Vector2(x, minf(y + 6.0, h)), col, 3.0)
				y += 9.0
		JwInfo.Cls.PROJECTED:
			var y2: float = 0.0
			while y2 < h:
				draw_line(Vector2(x, y2), Vector2(x, minf(y2 + 2.0, h)), col, 3.0)
				y2 += 6.0
