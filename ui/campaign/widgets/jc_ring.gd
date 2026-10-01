## 图标环：外圈一道弧表示满足了几成（满一圈 = 100%），按好坏上色；中间是图标（没图时写一个字）。
## 用在民生页的「每项需要」。
class_name JcRing
extends Control

var value: int = 0
var tone: String = "teal.core"
var icon_path: String = ""
var text: String = ""
var _tex: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if JcUi.has_art(icon_path):
		_tex = JcUi.tex(icon_path)


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 - 3.0
	var w: float = maxf(3.0, r * 0.14)
	draw_circle(c, r, JwTheme.c("bg.abyss"))
	draw_arc(c, r - w * 0.5, 0.0, TAU, 48, JwTheme.c("line.hair"), w, true)
	var f: float = clampf(float(value) / 1_000_000.0, 0.0, 1.0)
	if f > 0.0:
		draw_arc(c, r - w * 0.5, -PI * 0.5, -PI * 0.5 + TAU * f, 48, JwTheme.c(tone), w, true)
	var inner: float = (r - w) * 1.25
	if _tex != null:
		draw_texture_rect(_tex, Rect2(c - Vector2(inner, inner) * 0.5, Vector2(inner, inner)), false)
	elif text != "":
		var font: Font = JwTheme.font("title_sub")
		var fs: int = int(maxf(10.0, r * 0.75))
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - tw * 0.5, c.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				JwTheme.c("text.secondary"))
