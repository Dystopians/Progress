## 国史时间轴：1600—2000 一条横轴；本国所处的时代按年份着色成段，世界进入新时代处画小三角，
## 大事画成圆点（按好坏上色），竖线标出今年。点一下某处，发出那一年所在的年代（页面滚过去）。
class_name JcTimeline
extends Control

signal decade_picked(decade: int)

var start_year: int = 1600
var end_year: int = 2000
var year_now: int = 1600
## [{year, era}]（每年一个点，来自逐年统计）
var eras: Array = []
## [{year, era}] 世界进入新时代
var world: Array = []
## [{year, tone}] 大事
var marks: Array = []

const ERA_TONE: Array = ["", "series.1", "series.2", "series.3", "series.4"]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _x(year: float) -> float:
	var span: float = maxf(1.0, float(end_year - start_year))
	return 16.0 + (size.x - 32.0) * clampf((year - float(start_year)) / span, 0.0, 1.0)


func _draw() -> void:
	var h: float = size.y
	var band_y: float = h * 0.42
	var band_h: float = 14.0
	draw_rect(Rect2(_x(start_year), band_y, _x(end_year) - _x(start_year), band_h), JwTheme.c("bg.abyss"))
	# 本国时代的色段
	for i: int in eras.size():
		var e: Dictionary = eras[i]
		var y0: float = float(int(e["year"]))
		var y1: float = float(int(eras[i + 1]["year"])) if i + 1 < eras.size() else float(year_now)
		var tok: String = String(ERA_TONE[clampi(int(e["era"]), 1, 4)])
		draw_rect(Rect2(_x(y0), band_y, maxf(1.0, _x(y1) - _x(y0)), band_h), JwTheme.c(tok))
	# 每五十年一个刻度
	var small: Font = JwTheme.font("caption")
	var fs: int = JwTheme.size("caption")
	var y: int = start_year
	while y <= end_year:
		var x: float = _x(y)
		draw_line(Vector2(x, band_y + band_h), Vector2(x, band_y + band_h + 6.0), JwTheme.c("line.strong"), 1.0)
		var lbl: String = str(y)
		var w: float = small.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(small, Vector2(x - w * 0.5, band_y + band_h + 8.0 + fs), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				JwTheme.c("text.muted"))
		y += 50
	# 世界进入新时代：小三角
	for wv: Dictionary in world:
		var wx: float = _x(int(wv["year"]))
		draw_colored_polygon(PackedVector2Array([Vector2(wx, band_y - 2.0), Vector2(wx - 6.0, band_y - 12.0),
				Vector2(wx + 6.0, band_y - 12.0)]), JwTheme.c("text.secondary"))
	# 大事：圆点
	for mv: Dictionary in marks:
		var mx: float = _x(int(mv["year"]))
		draw_circle(Vector2(mx, band_y + band_h * 0.5), 5.0, JwTheme.c(String(mv["tone"])))
		draw_arc(Vector2(mx, band_y + band_h * 0.5), 5.0, 0.0, TAU, 16, JwTheme.c("bg.base"), 1.5, true)
	# 今年
	var nx: float = _x(year_now)
	draw_line(Vector2(nx, 4.0), Vector2(nx, h - 4.0), JwTheme.c("text.primary"), 2.0)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
			and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var px: float = (ev as InputEventMouseButton).position.x
		var span: float = maxf(1.0, size.x - 32.0)
		var yr: int = start_year + int(round((px - 16.0) / span * float(end_year - start_year)))
		@warning_ignore("integer_division")
		decade_picked.emit(clampi(yr, start_year, end_year) / 10 * 10)
		accept_event()
