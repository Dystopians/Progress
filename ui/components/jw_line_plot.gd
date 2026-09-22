## JwLineChart 的绘图区（自绘）：三条水平参考线与刻度、各序列折线与末点、首末季标签、左上角图例。
## 坐标映射用浮点只为画图；显示出来的数字一律由 JwLineChart.format_tick（JwFormat）给出。
class_name JwLinePlot
extends Control

var chart: JwLineChart = null

const PAD_L: float = 92.0
const PAD_R: float = 14.0
const PAD_T: float = 30.0
const PAD_B: float = 22.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), JwTheme.c("bg.abyss"), true)
	if chart == null:
		return
	var font: Font = JwTheme.font("caption")
	var fs: int = JwTheme.size("caption")
	var n: int = chart.quarters.size()
	if n < 2:
		draw_string(font, Vector2(12, size.y * 0.5), JwText.t("chart.empty"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				JwTheme.c("text.secondary"))
		return
	var lo: int = 0
	var hi: int = 0
	var first: bool = true
	for s: Dictionary in chart.series:
		for v: int in (s["values"] as PackedInt64Array):
			if first:
				lo = v
				hi = v
				first = false
			else:
				lo = mini(lo, v)
				hi = maxi(hi, v)
	if hi == lo:
		# 常数序列：上下各留 5% 的边（至少 1 个单位），免得折线贴着边框。
		@warning_ignore("integer_division")
		var pad: int = maxi(absi(lo) / 20, 1)
		hi = lo + pad
		lo = lo - pad
	var span: float = float(hi - lo)
	var x0: float = PAD_L
	var x1: float = size.x - PAD_R
	var y0: float = PAD_T
	var y1: float = size.y - PAD_B
	# 参考线与刻度（上 / 中 / 下）。
	for k: int in 3:
		var fy: float = y0 + (y1 - y0) * float(k) / 2.0
		draw_line(Vector2(x0, fy), Vector2(x1, fy), JwTheme.c("line.hair"), 1.0)
		@warning_ignore("integer_division")
		var tv: int = hi - (hi - lo) * k / 2
		draw_string(font, Vector2(6, fy + fs * 0.35), chart.format_tick(tv), HORIZONTAL_ALIGNMENT_LEFT, PAD_L - 10, fs,
				JwTheme.c("text.secondary"))
	# 首末季标签。
	draw_string(font, Vector2(x0, size.y - 4), JwText.render("chart.q", {"q": JwFormat.q2(int(chart.quarters[0]))}),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, JwTheme.c("text.secondary"))
	draw_string(font, Vector2(x1 - 40, size.y - 4), JwText.render("chart.q", {"q": JwFormat.q2(int(chart.quarters[n - 1]))}),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, JwTheme.c("text.secondary"))
	# 折线与末点。
	var lx: float = x0
	for s: Dictionary in chart.series:
		var vals: PackedInt64Array = s["values"]
		var col: Color = JwTheme.c(String(s.get("token", "series.1")))
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in vals.size():
			var px: float = x0 + (x1 - x0) * float(i) / float(maxi(n - 1, 1))
			var py: float = y1 - (y1 - y0) * float(vals[i] - lo) / span
			pts.append(Vector2(px, py))
		if pts.size() >= 2:
			draw_polyline(pts, col, 2.5, true)
		if pts.size() >= 1:
			draw_circle(pts[pts.size() - 1], 3.5, col)
		# 图例：序列色短线 + 名称（text.secondary 允许画在 bg.abyss 上）。
		draw_line(Vector2(lx, 12), Vector2(lx + 18, 12), col, 3.0)
		var label: String = String(s.get("label", ""))
		draw_string(font, Vector2(lx + 24, 12 + fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				JwTheme.c("text.secondary"))
		lx += 24.0 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 22.0
