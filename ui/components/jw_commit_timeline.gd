## 承诺时间轴（docs/20 §13.1 JwCommitTimeline，T1：12 季静态视窗，四泳道；D-02 落在总览页 L2 区块与季度报告）。
## 四泳道 = 计划书 §07 财政页必须展示的四项：到期本金、利息、已签项目付款、设施运行费（含政策项目期）。
## 数据来自 JWGame.commitment_schedule（SimCore 同口径函数）；界面只做坐标映射与格式化。
class_name JwCommitTimeline
extends JwChartFrame

const LANES: PackedStringArray = ["principal", "interest", "projects", "opex"]
const LANE_TOKENS: PackedStringArray = ["series.2", "series.4", "series.1", "series.3"]

var schedule: Dictionary = {}
var n_q: int = 12


static func make(sched: Dictionary, n: int, paper: bool = false) -> JwCommitTimeline:
	var c: JwCommitTimeline = JwCommitTimeline.new()
	c.schedule = sched
	c.n_q = n
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var q0: int = int(sched.get("q0", 0))
	var meta: JwChartMeta = JwChartMeta.make(JwText.render("ct.range", {"a": JwFormat.q2(q0), "b": JwFormat.q2(q0 + n - 1)}),
			JwText.t("chart.unit.u_q"), JwText.t("chart.pb.nominal"), JwText.t("chart.na"))
	c.setup_frame(JwText.render("ct.title", {"n": str(n)}), meta, paper)
	JwUi.tag(c, "CommitTimeline")
	return c


func build_plot() -> Control:
	var p: JwCommitPlot = JwCommitPlot.new()
	p.timeline = self
	p.custom_minimum_size = Vector2(560, 214)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	JwUi.tag(p, "CommitPlot")
	return p


func lane_values(lane: String) -> PackedInt64Array:
	var v: Variant = schedule.get(lane, PackedInt64Array())
	return v if v is PackedInt64Array else PackedInt64Array()


## 某季四泳道之和（界面显示用的汇总行；只相加同单位的同季金额）。
func total_at(t: int) -> int:
	var s: int = 0
	for lane: String in LANES:
		var v: PackedInt64Array = lane_values(lane)
		if t < v.size():
			s += v[t]
	return s
