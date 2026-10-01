## 占位圆章：图没到时代替图标——一个描边的圆，中间写一个字（名字的头一个字）。
class_name JcGlyph
extends Control

var text: String = ""
var tone: String = "line.strong"
var fill: String = "bg.abyss"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5 - 1.5
	var c: Vector2 = size * 0.5
	draw_circle(c, r, JwTheme.c(fill))
	draw_arc(c, r, 0.0, TAU, 48, JwTheme.c(tone), maxf(1.5, r * 0.06), true)
	if text == "":
		return
	var font: Font = JwTheme.font("title_block")
	var fs: int = int(maxf(10.0, r * 0.95))
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(c.x - w * 0.5, c.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, JwTheme.c(tone))
