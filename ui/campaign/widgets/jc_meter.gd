## 横向进度条（可带一条刻度线，比如「目标」或「期待」）。
class_name JcMeter
extends Control

var value: int = 0
var token: String = "teal.core"
var marker: int = -1


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(r, JwTheme.c("bg.abyss"), true)
	var w: float = size.x * clampf(float(value) / 1_000_000.0, 0.0, 1.0)
	if w > 0.5:
		draw_rect(Rect2(Vector2.ZERO, Vector2(w, size.y)), JwTheme.c(token), true)
	if marker >= 0:
		var x: float = size.x * clampf(float(marker) / 1_000_000.0, 0.0, 1.0)
		draw_line(Vector2(x, -2), Vector2(x, size.y + 2), JwTheme.c("text.primary"), 2.0)
