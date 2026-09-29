## 折线（近几十年的走势）：只画线与最后一个点，最低最高标在两端。
class_name JcSpark
extends Control

var values: Array = []
var token: String = "teal.core"


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), JwTheme.c("bg.abyss"), true)
	if values.size() < 2:
		return
	var lo: float = INF
	var hi: float = -INF
	for v: Variant in values:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	if hi - lo < 1e-9:
		hi = lo + 1.0
	var pad: float = 4.0
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in values.size():
		var x: float = pad + (size.x - 2 * pad) * float(i) / float(values.size() - 1)
		var y: float = size.y - pad - (size.y - 2 * pad) * (float(values[i]) - lo) / (hi - lo)
		pts.append(Vector2(x, y))
	draw_polyline(pts, JwTheme.c(token), 2.0, true)
	draw_circle(pts[pts.size() - 1], 3.0, JwTheme.c(token))
