## 横条原语（docs/20 §13.1 JwBarRow）：约束阶梯与分布条共用。自绘，比例由调用方传入。
## 只画一根条与可选的标记线；数值文字由相邻 Label 承载（不在条内写字，避免裁切）。
class_name JwBar
extends Control

var ratio: float = 0.0
## 填充起点（0..1）：分布条的色带从 start 画到 ratio；约束阶梯等普通横条保持 0。
var start: float = 0.0
var color_token: String = "teal.dim"
var outline_token: String = ""
var markers: Array = []
var paper: bool = false


static func make(r: float, tok: String, outline: String = "", h: int = 18) -> JwBar:
	var b: JwBar = JwBar.new()
	b.ratio = clampf(r, 0.0, 1.0)
	b.color_token = tok
	b.outline_token = outline
	b.custom_minimum_size = Vector2(120, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _draw() -> void:
	var bg: Color = JwTheme.c("bg.paper2" if paper else "bg.abyss")
	draw_rect(Rect2(Vector2.ZERO, size), bg, true)
	var x0: float = size.x * clampf(start, 0.0, 1.0)
	var w: float = maxf(size.x * ratio - x0, 0.0)
	draw_rect(Rect2(Vector2(x0, 0), Vector2(w, size.y)), JwTheme.c(color_token), true)
	if outline_token != "":
		draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), JwTheme.c(outline_token), false, 2.0)
	for mk: Variant in markers:
		var md: Dictionary = mk
		var x: float = size.x * clampf(float(md.get("at", 0.0)), 0.0, 1.0)
		var col: Color = JwTheme.c(String(md.get("token", "text.primary")))
		draw_line(Vector2(x, -2), Vector2(x, size.y + 2), col, float(md.get("w", 2.0)))
