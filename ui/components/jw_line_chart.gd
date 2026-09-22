## 时序图（docs/20 §13.1 JwLineChart，T1）：继承 JwChartFrame，自绘折线。
## 序列只接收读模型给出的整数（μU 或 ppm），界面只做坐标映射与格式化（B-02）；刻度文字一律经 JwFormat。
## 绘图区用 bg.abyss 底色：序列色 series.* 只允许画在它上面（palette.json allowed_on），图例也画在绘图区内。
class_name JwLineChart
extends JwChartFrame

## 每条序列：{"label": String, "values": PackedInt64Array, "token": "series.N"}。
var series: Array[Dictionary] = []
## 横轴：与各序列等长的内部季号。
var quarters: PackedInt64Array = PackedInt64Array()
## 刻度格式："u"（金额）/ "pct"（ppm → %）/ "index"。
var fmt: String = "u"
var plot_height: int = 150


static func make(title_text: String, m: JwChartMeta, p_series: Array[Dictionary], p_quarters: PackedInt64Array,
		p_fmt: String, paper: bool = false, h: int = 150) -> JwLineChart:
	var c: JwLineChart = JwLineChart.new()
	c.series = p_series
	c.quarters = p_quarters
	c.fmt = p_fmt
	c.plot_height = h
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.setup_frame(title_text, m, paper)
	return c


func build_plot() -> Control:
	var p: JwLinePlot = JwLinePlot.new()
	p.chart = self
	p.custom_minimum_size = Vector2(260, plot_height)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	JwUi.tag(p, "ChartPlot")
	return p


func format_tick(v: int) -> String:
	match fmt:
		"pct":
			return JwFormat.pct(v)
		"index":
			return JwFormat.index(v)
	return JwFormat.u(v)
