## 两头的刻度条：中间一道竖线，值从中间往左（负）或往右（正）填，−100…100。
## 用在政令页的「国家形态」：仁政—严苛、集权—放任、开放—闭关、维新—守旧。
class_name JcAxis
extends Control

var value: int = 0
var left_tone: String = "ochre.core"
var right_tone: String = "teal.core"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var h: float = size.y
	var y: float = h * 0.5
	var w: float = size.x
	var track: Rect2 = Rect2(0.0, y - 4.0, w, 8.0)
	draw_rect(track, JwTheme.c("bg.abyss"))
	var mid: float = w * 0.5
	var v: float = clampf(float(value) / 100.0, -1.0, 1.0)
	if v > 0.0:
		draw_rect(Rect2(mid, y - 4.0, mid * v, 8.0), JwTheme.c(right_tone))
	elif v < 0.0:
		draw_rect(Rect2(mid + mid * v, y - 4.0, -mid * v, 8.0), JwTheme.c(left_tone))
	draw_line(Vector2(mid, 0.0), Vector2(mid, h), JwTheme.c("line.strong"), 1.5)
	var x: float = mid + mid * v
	draw_circle(Vector2(x, y), 7.0, JwTheme.c("text.primary"))
	draw_circle(Vector2(x, y), 4.5, JwTheme.c(right_tone if v >= 0.0 else left_tone))
