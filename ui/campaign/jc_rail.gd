## v2 右侧栏：顾问（最多三条，「照此办理」「不必再提」）、托管拟办（批准 / 驳回）、本季已下的命令（可撤回）。
class_name JcRail
extends PanelContainer

var session: JcSession = null
var root_ui: Node = null
var box: VBoxContainer = null


func setup(s: JcSession, r: Node) -> void:
	session = s
	root_ui = r
	name = "Rail"
	add_theme_stylebox_override("panel", JwTheme.box4("bg.panel", "line.hair", 1, 12, 12, 12, 12))
	custom_minimum_size = Vector2(360, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	box = JwUi.vbox(12)
	var sc: ScrollContainer = JwUi.scroll(box)
	add_child(sc)


func refresh() -> void:
	JwUi.clear(box)
	if not session.has_game():
		return
	var g: JCGame = session.game
	# 顾问
	var head: HBoxContainer = JwUi.hbox(8)
	head.add_child(JwUi.label(JwText.t("jc.rail.advisors"), "title_sub", "text.primary"))
	head.add_child(JwUi.spacer())
	head.add_child(JcUi.link(JwText.render("jc.rail.all_advice", {"n": str(g.advisors.items.size())}),
			func() -> void: root_ui.call("open_overlay", "advisors", {})))
	box.add_child(head)
	var top: Array = g.advisors.top(3)
	if top.is_empty():
		box.add_child(JwUi.para(JwText.t("jc.rail.no_advice"), "text.muted"))
	for it: Dictionary in top:
		box.add_child(advice_card(session, it, true))
	# 托管拟办
	if not g.proposals.is_empty():
		box.add_child(JwUi.hsep())
		var ph: HBoxContainer = JwUi.hbox(8)
		ph.add_child(JwUi.label(JwText.t("jc.rail.proposals"), "title_sub", "text.primary"))
		ph.add_child(JwUi.spacer())
		ph.add_child(JcUi.button(JwText.t("jc.rail.approve_all"), true, func() -> void: session.approve_all()))
		box.add_child(ph)
		for i: int in mini(g.proposals.size(), 8):
			var p: Dictionary = g.proposals[i]
			var row: HBoxContainer = JwUi.hbox(6)
			var txt: String = JcFmt.r(String(p["reason"]), JcFmt.slots(g, p["slots"]))
			var l: Label = JwUi.label(txt, "body", "text.secondary", true)
			row.add_child(l)
			var idx: int = i
			row.add_child(JcUi.button(JwText.t("jc.rail.approve"), false, func() -> void: session.approve(idx)))
			row.add_child(JcUi.button(JwText.t("jc.rail.reject"), false, func() -> void: session.reject(idx)))
			box.add_child(row)
	# 本季命令
	box.add_child(JwUi.hsep())
	var oh: HBoxContainer = JwUi.hbox(8)
	oh.add_child(JwUi.label(JwText.t("jc.rail.orders"), "title_sub", "text.primary"))
	oh.add_child(JwUi.spacer())
	var orders: Array = g.turn_orders()
	if not orders.is_empty():
		oh.add_child(JcUi.button(JwText.t("jc.rail.undo"), false, func() -> void: session.undo()))
	box.add_child(oh)
	if orders.is_empty():
		box.add_child(JwUi.para(JwText.t("jc.rail.no_orders"), "text.muted"))
	for e: Dictionary in orders:
		box.add_child(JwUi.label("· " + order_text(g, e["cmd"]), "body", "text.secondary", true))


## 一条顾问建议的卡片（右侧栏与顾问面板共用）。
static func advice_card(s: JcSession, it: Dictionary, compact: bool) -> PanelContainer:
	var g: JCGame = s.game
	var sev: int = int(it["sev"])
	var tok: String = JcUi.BAD if sev >= 3 else (JcUi.WARN if sev == 2 else JcUi.GOOD)
	var p: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.raised", tok, 4, 10))
	var v: VBoxContainer = JwUi.vbox(6)
	p.add_child(v)
	var hh: HBoxContainer = JwUi.hbox(8)
	hh.add_child(JcUi.icon(JcUi.ADVISOR_ART % String(it["ministry"]), 30.0 if compact else 40.0))
	hh.add_child(JcUi.chip(JwText.t("jc.adv.m." + String(it["ministry"])), tok))
	var sl: Dictionary = JcFmt.slots(g, it.get("slots", {}))
	hh.add_child(JwUi.label(JcFmt.r(String(it["title"]), sl), "body_bold", "text.primary", true))
	v.add_child(hh)
	v.add_child(JwUi.para(JcFmt.r(String(it["body"]), sl), "text.secondary"))
	var bh: HBoxContainer = JwUi.hbox(8)
	var cmds: Array = it.get("cmds", [])
	if not cmds.is_empty():
		var lab: String = JwText.t("jc.adv.do")
		if int(it.get("cost_li", 0)) > 0:
			lab = JwText.render("jc.adv.do_cost", {"cost": JcFmt.money(int(it["cost_li"]))})
		var id: String = String(it["id"])
		bh.add_child(JcUi.button(lab, true, func() -> void: s.accept_advice(id)))
	var id2: String = String(it["id"])
	bh.add_child(JcUi.link(JwText.t("jc.adv.dismiss"), func() -> void: s.dismiss_advice(id2)))
	v.add_child(bh)
	return p


## 一条命令 → 一句话（本季命令列表、存档里的命令簿）。
static func order_text(g: JCGame, cmd: Dictionary) -> String:
	var kind: String = String(cmd.get("kind", ""))
	var raw: Dictionary = {}
	for k: Variant in cmd.keys():
		if String(k) != "kind" and String(k) != "source":
			raw[String(k)] = cmd[k]
	match kind:
		"upgrade", "mothball", "reopen", "demolish":
			var info: Dictionary = g.stack_info(int(cmd.get("uid", -1)))
			if not info.is_empty():
				raw["building"] = info["building"]
				raw["region"] = info["region"]
		"budget":
			raw["line"] = int(cmd.get("line", 0))
			raw["value"] = int(cmd.get("level", 0))
		"event":
			raw["option"] = int(cmd.get("option", 0))
		"loan", "repay":
			raw["amount_li"] = int(cmd.get("amount", 0))
	var s: Dictionary = JcFmt.slots(g, raw)
	if kind == "decree":
		s["level_text"] = JcFmt._decree_level(g, String(cmd.get("decree", "")), int(cmd.get("level", 0)))
	var src: String = String(cmd.get("source", "player"))
	var who: String = ""
	if src.begins_with("steward"):
		who = JwText.t("jc.order.by_steward")
	elif src.begins_with("advisor"):
		who = JwText.t("jc.order.by_advisor")
	var txt: String = JwText.render("jc.order." + kind, s)
	return (who + txt) if txt != "" else kind
