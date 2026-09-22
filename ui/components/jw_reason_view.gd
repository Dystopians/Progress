## 单条原因的呈现（docs/20 §9.2 五行版式；RC-13：政策目录、政策卡、预算审查、确认框四处同一函数）。
##
## 文本一律来自 JwReasons.render_lines(r)；本组件只把第 4 行（出口）换成可点击的命令按钮，
## 并在 meta 里保存完整文本（reason_text）供测试逐字比对。风险用 图标 + 等级词 + 颜色 三通道表达。
class_name JwReasonView
extends PanelContainer

var reason: Dictionary = {}
var session: JwSession = null
var root_ui: Node = null


static func make(r: Dictionary, s: JwSession, root: Node, paper: bool = false) -> JwReasonView:
	var v: JwReasonView = JwReasonView.new()
	v.reason = r
	v.session = s
	v.root_ui = root
	v._build(paper)
	return v


func _build(paper: bool) -> void:
	var sev: int = int(reason.get("severity", JwInfo.Sev.NOTE))
	var tok: String = JwInfo.sev_color_token(sev, paper)
	add_theme_stylebox_override("panel", JwTheme.box_left_rule("bg.paper2" if paper else "bg.raised", tok, 3, 10))
	var lines: PackedStringArray = JwReasons.render_lines(reason)
	set_meta("reason_text", "\n".join(lines))
	set_meta("reason_code", String(reason.get("code", "")))
	set_meta("severity", sev)
	var v: VBoxContainer = JwUi.vbox(4)
	add_child(v)
	var head: HBoxContainer = JwUi.hbox(8)
	head.add_child(JwUi.risk_badge(sev, JwInfo.sev_word(sev), paper))
	var t: Label = JwUi.label(lines[0], "body_bold", "text.ink" if paper else "text.primary", true)
	head.add_child(t)
	v.add_child(head)
	var body_tok: String = "text.ink" if paper else "text.secondary"
	v.add_child(JwUi.label(lines[1], "body", body_tok, true))
	var idx: int = 2
	if not (reason.get("drivers", []) as Array).is_empty():
		v.add_child(JwUi.label(lines[idx], "body", body_tok, true))
		idx += 1
	var exits: Array = reason.get("exits", [])
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	var marks: PackedStringArray = ["①", "②", "③", "④"]
	for i: int in mini(exits.size(), 4):
		var ex: Dictionary = exits[i]
		var b: Button = JwUi.button(marks[i] + " " + String(ex.get("text", "")))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(280, 34)
		var action: Dictionary = ex.get("action", {})
		b.set_meta("exit_action", action)
		b.pressed.connect(func() -> void:
			if session != null:
				session.apply_exit(action))
		flow.add_child(b)
	var ex_head: Label = JwUi.label(JwText.t("reason.exits_head"), "body_bold", body_tok)
	v.add_child(ex_head)
	v.add_child(flow)
	if bool(reason.get("bound", false)):
		v.add_child(JwUi.label(JwText.render("reason.bound", {"path": JwText.t("gap.path." + String(reason.get("bound_path", "")))}),
				"body_bold", "teal.deep" if paper else "teal.core"))
	var links: HBoxContainer = JwUi.hbox(8)
	for l: Variant in reason.get("links", []):
		var ld: Dictionary = l
		var lb: Button = JwUi.link("▸" + JwText.t("ledger.name." + String(ld.get("ledger", ""))))
		var led: String = String(ld.get("ledger", ""))
		lb.pressed.connect(func() -> void:
			if root_ui != null and root_ui.has_method("open_ledger"):
				root_ui.call("open_ledger", led, 0))
		links.add_child(lb)
	v.add_child(links)
	if session != null:
		session.log_event("ev.reason_shown", {"code": String(reason.get("code", "")), "severity": sev})
