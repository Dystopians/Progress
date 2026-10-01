## 占位圆章：图没到时代替图标——一个描边的圆，中间写一个字（名字的头一个字）。
## 给了 image 就在圈里放图（小脸这类：图太小看不出表情时，圈的颜色照样说明好坏）。
class_name JcGlyph
extends Control

var text: String = ""
var tone: String = "line.strong"
var fill: String = "bg.abyss"
var image: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5 - 1.5
	var c: Vector2 = size * 0.5
	var ring: float = maxf(1.5, r * (0.12 if image != null else 0.06))
	draw_circle(c, r, JwTheme.c(fill).lerp(JwTheme.c(tone), 0.18 if image != null else 0.0))
	if image != null:
		var s: float = (r - ring) * 1.7
		draw_texture_rect(image, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false)
	draw_arc(c, r - ring * 0.5 + 0.75, 0.0, TAU, 48, JwTheme.c(tone), ring, true)
	if text == "" or image != null:
		return
	var font: Font = JwTheme.font("title_block")
	var fs: int = int(maxf(10.0, r * 0.95))
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(c.x - w * 0.5, c.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, JwTheme.c(tone))
