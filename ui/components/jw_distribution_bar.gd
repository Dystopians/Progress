## 分布条（docs/20 §13.1 JwDistributionBar，T1）：P10 / P50 / 均值 / P90 同时显示。
## 色带从 P10 画到 P90，粗线为 P50、细线为均值；数字由相邻的「实」行承载（不在条内写字）。
## 条体一律画在 bg.abyss 上（序列色只允许画在它上面，palette.json allowed_on），纸面页也一样。
class_name JwDistributionBar
extends VBoxContainer


## q：{p10, p50, mean, p90}（读模型给出；任一为 −1 表示未结算）；fmt："pct" / "index" / "uu_pc"。
static func make(title_text: String, q: Dictionary, fmt: String, paper: bool = false) -> JwDistributionBar:
	var d: JwDistributionBar = JwDistributionBar.new()
	d.add_theme_constant_override("separation", 4)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	JwUi.tag(d, "DistributionBar")
	d.set_meta("distribution", true)
	d.add_child(JwUi.label(title_text, "body_bold", "text.ink" if paper else "text.primary"))
	if int(q.get("p50", -1)) < 0:
		d.add_child(JwUi.label(JwText.t("dist.cold"), "body", "text.ink2" if paper else "text.muted", true))
		return d
	# 刻度：两端各留 P10–P90 跨度的四分之一（不低于 0）；刻度起点不是 0，说明里写明，免得误读差距。
	var p10: int = int(q["p10"])
	var p90: int = int(q["p90"])
	var span: int = p90 - p10
	if span <= 0:
		@warning_ignore("integer_division")
		span = maxi(absi(int(q["p50"])) / 10, 1)
	@warning_ignore("integer_division")
	var lo: int = maxi(p10 - span / 4, 0)
	@warning_ignore("integer_division")
	var hi: int = p90 + span / 4
	var den: float = float(maxi(hi - lo, 1))
	var bar: JwBar = JwBar.make(float(p90 - lo) / den, "teal.dim", "", 20)
	bar.start = float(p10 - lo) / den
	bar.markers = [
		{"at": float(int(q["p50"]) - lo) / den, "token": "text.primary", "w": 3.0},
		{"at": float(int(q["mean"]) - lo) / den, "token": "warm.text"},
	]
	d.add_child(bar)
	d.add_child(JwUi.class_line(JwInfo.Cls.ACTUAL, JwText.render("dist.line", {"p10": _fmt(p10, fmt),
			"p50": _fmt(int(q["p50"]), fmt), "mean": _fmt(int(q["mean"]), fmt), "p90": _fmt(p90, fmt)}), paper))
	d.add_child(JwUi.label(JwText.render("dist.caption", {"lo": _fmt(lo, fmt), "hi": _fmt(hi, fmt)}), "caption",
			"text.ink2" if paper else "text.muted", true))
	return d


static func _fmt(v: int, fmt: String) -> String:
	match fmt:
		"pct":
			return JwFormat.pct(v)
		"index":
			return JwFormat.index(v)
		"uu_pc":
			return JwFormat.uu_pc(v)
	return JwFormat.u(v)
