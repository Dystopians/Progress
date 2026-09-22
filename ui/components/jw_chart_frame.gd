## 图表外框（docs/20 §4.4、AC-16）：标题 + 绘图区 + 四标注行，四标注渲染在图框之内。
## 元数据用 @export 注入（不是构造参数）；任一标注为空即 push_error，并在图框里渲染红底占位「图表元数据缺失：{字段}」。
## 方法名是 get_chart_meta()——不得叫 get_meta()（那是 Object 的原生方法）。
@tool
class_name JwChartFrame
extends VBoxContainer

@export var meta: JwChartMeta = null
var chart_title: String = ""
var _meta_label: Label = null
var _placeholder: Control = null


func get_chart_meta() -> JwChartMeta:
	return meta


## 组装外框（子类在 build_plot() 里给出绘图区）。paper：纸面页（报告、档案）上用深色字。
func setup_frame(title_text: String, m: JwChartMeta, paper: bool = false) -> void:
	chart_title = title_text
	meta = m
	add_theme_constant_override("separation", 4)
	JwUi.tag(self, "ChartFrame")
	add_child(JwUi.label(title_text, "body_bold", "text.ink" if paper else "text.primary"))
	var plot: Control = build_plot()
	if plot != null:
		add_child(plot)
	var miss: PackedStringArray = PackedStringArray(["time_range", "unit", "price_base", "denominator"]) \
			if meta == null else meta.missing()
	if not miss.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for f: String in miss:
			names.append(JwText.t("chart.meta.field." + f))
		push_error("JwChartFrame: chart meta missing " + ",".join(miss) + " in " + title_text)
		var ph: PanelContainer = JwUi.panel_style(JwTheme.box("debug.missing", "", 0, 2, 6))
		ph.add_child(JwUi.label(JwText.render("chart.meta.missing", {"field": "、".join(names)}), "body_bold", "text.primary"))
		JwUi.tag(ph, "ChartMetaMissing")
		_placeholder = ph
		add_child(ph)
		return
	_meta_label = JwUi.label(JwText.render("chart.meta.line", {"time_range": meta.time_range, "unit": meta.unit,
			"price_base": meta.price_base, "denominator": meta.denominator}), "caption", "text.ink2" if paper else "text.muted", true)
	JwUi.tag(_meta_label, "ChartMeta")
	add_child(_meta_label)


## 子类覆盖：返回绘图区控件。
func build_plot() -> Control:
	return null


func _get_configuration_warnings() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if meta == null:
		out.append("JwChartFrame: meta is required (docs/20 §4.4)")
	else:
		for f: String in meta.missing():
			out.append("JwChartFrame: meta." + f + " is empty (write the not-applicable text explicitly)")
	return out
