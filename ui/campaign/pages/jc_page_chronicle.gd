## 纪事：大事记（可按类别筛）与托管记录（托管替你做了什么、为什么、办成没有）。
class_name JcPageChronicle
extends JcPage

const KINDS: PackedStringArray = ["all", "era", "crisis", "event", "build", "invest", "research", "decree", "fiscal", "trade",
		"landmark"]

var _tab: String = "chron"
var _kind: String = "all"


func refresh() -> void:
	clear()
	if not session.has_game():
		return
	var g: JCGame = game()
	var tabs: HBoxContainer = JwUi.hbox(4)
	for id: String in ["chron", "steward"]:
		var b: Button = JwUi.button(t("jc.chr.tab." + id), "TabBtn")
		b.toggle_mode = true
		b.set_pressed_no_signal(_tab == id)
		b.pressed.connect(func() -> void:
			_tab = id
			refresh())
		tabs.add_child(b)
	content.add_child(tabs)
	if _tab == "steward":
		_steward(g)
		return
	var fl: HFlowContainer = JcUi.flow(4, 4)
	for k: String in KINDS:
		var b2: Button = JwUi.button(t("jc.chr.kind." + k))
		b2.toggle_mode = true
		b2.set_pressed_no_signal(_kind == k)
		b2.pressed.connect(func() -> void:
			_kind = k
			refresh())
		fl.add_child(b2)
	content.add_child(fl)
	var box: VBoxContainer = JwUi.vbox(2)
	var last_year: int = -1
	var n: int = 0
	for e: Dictionary in views().chronicle(400):
		var kind: String = String(e.get("kind", ""))
		if kind == "steward" or kind == "advisor":
			continue
		if _kind != "all" and kind != _kind:
			continue
		var q: int = int(e["q"])
		@warning_ignore("integer_division")
		var y: int = g.st.start_year + q / 4
		if y != last_year:
			last_year = y
			box.add_child(JwUi.label(rt("jc.chr.year", {"year": str(y)}), "title_sub", "text.primary"))
		var h: HBoxContainer = JwUi.hbox(10)
		var d: Label = JwUi.label(t("jc.u.season.%d" % (q % 4)), "caption", "text.muted")
		d.custom_minimum_size = Vector2(28, 0)
		h.add_child(d)
		var tok: String = "text.secondary"
		if kind == "era" or kind == "landmark":
			tok = JcUi.GOOD
		elif kind == "crisis":
			tok = JcUi.BAD
		elif kind == "event":
			tok = JcUi.WARN
		h.add_child(JwUi.label(JcFmt.chron(g, e), "body", tok, true))
		box.add_child(h)
		n += 1
		if n >= 240:
			break
	if n == 0:
		box.add_child(JwUi.para(t("jc.chr.empty"), "text.muted"))
	content.add_child(box)


func _steward(g: JCGame) -> void:
	content.add_child(JwUi.para(t("jc.chr.steward_intro"), "text.muted"))
	var box: VBoxContainer = JwUi.vbox(4)
	var recs: Array = views().steward_log(200)
	if recs.is_empty():
		box.add_child(JwUi.para(t("jc.chr.steward_empty"), "text.muted"))
	for rec: Dictionary in recs:
		var h: HBoxContainer = JwUi.hbox(10)
		var d: Label = JwUi.label(JcFmt.date(int(rec["q"]), g.st.start_year), "caption", "text.muted")
		d.custom_minimum_size = Vector2(90, 0)
		h.add_child(d)
		h.add_child(JcUi.chip(t("jc.stw.domain." + String(rec["domain"])), JcUi.MUTED))
		var ok: bool = bool(rec.get("ok", false))
		var txt: String = JcFmt.r(String(rec["reason"]), JcFmt.slots(g, rec.get("slots", {})))
		if not ok:
			txt += rt("jc.chr.failed", {"why": JcFmt.reason(g, {"reason": String(rec.get("why", ""))})})
		h.add_child(JwUi.label(txt, "body", "text.secondary" if ok else JcUi.WARN, true))
		box.add_child(h)
	content.add_child(box)
